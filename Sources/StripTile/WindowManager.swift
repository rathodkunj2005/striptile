import ApplicationServices
import AppKit
import StripCore

private func observerCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element)
}

struct WindowInfo {
    let id: WindowID
    let appName: String
    let title: String
    let icon: NSImage?
    let state: String

    var searchText: String { title.isEmpty ? appName : "\(appName) \(title)" }
}

struct OverviewColumn {
    let width: Double
    let windows: [WindowInfo]
}

private struct SavedWindow: Codable {
    var bundleID: String?
    var title: String
}

private struct SavedColumn: Codable {
    var width: Double
    var windows: [SavedWindow]
}

final class WindowManager {
    private struct Meta {
        let pid: pid_t
        let bundleID: String?
    }

    private let prefs = Prefs.shared
    private var strips: [CGDirectDisplayID: Strip] = [:]
    private var elements: [WindowID: AXUIElement] = [:]
    private var meta: [WindowID: Meta] = [:]
    private var floating: Set<WindowID> = []
    private var pinned: [WindowID: Side] = [:]
    private var pinDisplay: [WindowID: CGDirectDisplayID] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var applied: [WindowID: CGRect] = [:]
    private var scrollFlushScheduled = false
    private var snapTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private(set) var paused = false

    private var gap: CGFloat { CGFloat(prefs.gap) }

    private var rowFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StripTile/row.json")
    }

    init() {
        NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.relayout()
        }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.observe(app) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observers[app.processIdentifier] = nil
            }
            self?.prune()
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.syncFocus()
        }
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.forEach(observe)
        if prefs.restoreRow { restoreRow() }
        relayout()
        Log.write("manager started: windows=\(elements.count) strips=\(strips.mapValues { $0.windowIDs.count }) screens=\(screens().count)")
    }

    func setPaused(_ value: Bool) {
        paused = value
        if !value { relayout() }
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        let axApp = AXUIElementCreateApplication(pid)
        var created: AXObserver?
        guard AXObserverCreate(pid, observerCallback, &created) == .success, let obs = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(obs, axApp, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
        AX.windows(of: axApp).forEach { track($0, pid: pid) }
        relayout()
    }

    private func track(_ element: AXUIElement, pid: pid_t) {
        guard let id = AX.windowID(element), elements[id] == nil, AX.isManageable(element) else { return }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let rule = bundleID.flatMap { prefs.rule(for: $0) }
        if rule?.mode == .ignore { return }

        elements[id] = element
        meta[id] = Meta(pid: pid, bundleID: bundleID)
        if let obs = observers[pid] {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                AXObserverAddNotification(obs, element, name as CFString, refcon)
            }
        }
        if rule?.mode == .float {
            floating.insert(id)
            return
        }
        guard let display = display(for: element) else { return }
        strips[display, default: Strip()].insert(id, width: rule?.width ?? Strip.widthSteps[0])
    }

    func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                track(element, pid: pid)
                relayout()
            }
        case kAXFocusedWindowChangedNotification:
            if let id = AX.windowID(element) { focusChanged(id) }
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            prune()
        case kAXWindowDeminiaturizedNotification:
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            track(element, pid: pid)
            relayout()
        default:
            break
        }
    }

    private func focusChanged(_ id: WindowID) {
        for key in strips.keys where strips[key]!.contains(id) {
            strips[key]!.setFocus(id)
        }
        relayout()
    }

    private func syncFocus() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let window = AX.element(axApp, kAXFocusedWindowAttribute), let id = AX.windowID(window) {
            focusChanged(id)
        }
    }

    private func prune() {
        for (id, element) in elements where !AX.isManageable(element) {
            elements[id] = nil
            meta[id] = nil
            applied[id] = nil
            pinned[id] = nil
            pinDisplay[id] = nil
            floating.remove(id)
            for key in strips.keys { strips[key]!.remove(id) }
        }
        relayout()
    }

    private func focusedID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AX.element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return nil }
        return AX.windowID(window)
    }

    private func screens() -> [(id: CGDirectDisplayID, bounds: CGRect, usable: CGRect)] {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let v = screen.visibleFrame
            let usable = CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
            return (id, CGDisplayBounds(id), usable)
        }
    }

    private func screenUnderMouse() -> (id: CGDirectDisplayID, bounds: CGRect, usable: CGRect)? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        return screens().first { $0.id == id }
    }

    private func display(for element: AXUIElement) -> CGDirectDisplayID? {
        let all = screens()
        guard let frame = AX.frame(element) else { return all.first?.id }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return (all.first { $0.bounds.contains(center) } ?? all.first)?.id
    }

    private func stripRect(for screen: (id: CGDirectDisplayID, bounds: CGRect, usable: CGRect)) -> (rect: CGRect, pins: [WindowID: CGRect]) {
        var rect = screen.usable
        var pins: [WindowID: CGRect] = [:]
        let width = CGFloat(prefs.pinWidth) * screen.usable.width
        for (id, side) in pinned where pinDisplay[id] == screen.id {
            let x = side == .left ? screen.usable.minX + gap : screen.usable.maxX - gap - width
            pins[id] = CGRect(x: x, y: screen.usable.minY + gap, width: width, height: screen.usable.height - 2 * gap)
            if side == .left { rect.origin.x += width + gap }
            rect.size.width -= width + gap
        }
        return (rect, pins)
    }

    func relayout(scrolling: Bool = false) {
        guard !paused else { return }
        for screen in screens() {
            let (rect, pins) = stripRect(for: screen)
            for (id, frame) in pins { apply(id, frame, scrolling: scrolling, usable: screen.usable) }
            guard var strip = strips[screen.id] else { continue }
            let frames = strip.layout(in: rect, gap: gap)
            strips[screen.id] = strip
            for (id, frame) in frames where !floating.contains(id) {
                apply(id, frame, scrolling: scrolling, usable: screen.usable)
            }
        }
        if !scrolling { scheduleSave() }
    }

    private func apply(_ id: WindowID, _ frame: CGRect, scrolling: Bool, usable: CGRect) {
        guard let element = elements[id] else { return }
        if scrolling, let previous = applied[id] {
            if isOffscreen(previous, usable) && isOffscreen(frame, usable) { return }
            if previous == frame { return }
            if previous.size == frame.size {
                AX.setPosition(element, frame.origin)
                applied[id] = frame
                return
            }
        }
        AX.setFrame(element, frame)
        applied[id] = frame
    }

    private func isOffscreen(_ frame: CGRect, _ usable: CGRect) -> Bool {
        frame.maxX <= usable.minX || frame.minX >= usable.maxX
    }

    func scrollRow(by normalizedDX: CGFloat) {
        guard !paused, let screen = screenUnderMouse(), strips[screen.id] != nil else { return }
        snapTimer?.invalidate()
        let direction: CGFloat = prefs.naturalScroll ? 1 : -1
        strips[screen.id]!.scroll(by: direction * normalizedDX * screen.bounds.width * CGFloat(prefs.swipeGain))
        guard !scrollFlushScheduled else { return }
        scrollFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [self] in
            scrollFlushScheduled = false
            relayout(scrolling: true)
        }
    }

    func settleScroll() {
        guard !paused, prefs.snapToColumns, let screen = screenUnderMouse(), let strip = strips[screen.id] else { return }
        let delta = strip.snapDelta(in: stripRect(for: screen).rect, gap: gap)
        guard abs(delta) > 1 else { return }
        let steps = 9
        var step = 0
        func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            step += 1
            let portion = ease(Double(step) / Double(steps)) - ease(Double(step - 1) / Double(steps))
            self.strips[screen.id]?.scroll(by: delta * CGFloat(portion))
            self.relayout(scrolling: true)
            if step >= steps { timer.invalidate() }
        }
    }

    private func withFocused(_ body: (WindowID, CGDirectDisplayID) -> Void) {
        guard !paused, let id = focusedID() else { return }
        guard let display = strips.first(where: { $0.value.contains(id) })?.key else { return }
        strips[display]!.setFocus(id)
        body(id, display)
        relayout()
    }

    func moveFocus(_ side: Side) {
        withFocused { _, display in
            guard let id = strips[display]!.moveFocus(side) else { return }
            raiseAndActivate(id)
        }
    }

    func swap(_ side: Side) { withFocused { _, d in strips[d]!.swap(side) } }
    func cycleWidth() { withFocused { _, d in strips[d]!.cycleWidth() } }
    func fill() { withFocused { _, d in strips[d]!.fill() } }
    func center() { withFocused { _, d in strips[d]!.center() } }
    func stack(_ side: Side) { withFocused { _, d in strips[d]!.stack(side) } }
    func popOut(_ side: Side) { withFocused { _, d in strips[d]!.popOut(side) } }

    func toggleFloat() {
        guard !paused, let id = focusedID(), let element = elements[id], pinned[id] == nil else { return }
        if floating.remove(id) != nil {
            if let d = display(for: element) { strips[d, default: Strip()].insert(id) }
        } else {
            floating.insert(id)
            for key in strips.keys { strips[key]!.remove(id) }
        }
        relayout()
    }

    func cyclePin() {
        guard !paused, let id = focusedID(), let element = elements[id] else { return }
        switch pinned[id] {
        case nil:
            pin(id, .right, element)
        case .right?:
            pin(id, .left, element)
        case .left?:
            unpin(id, element)
        }
    }

    private func pin(_ id: WindowID, _ side: Side, _ element: AXUIElement) {
        let target = strips.first(where: { $0.value.contains(id) })?.key ?? pinDisplay[id] ?? display(for: element)
        guard let target else { return }
        let displaced = pinned.filter { $0.value == side && pinDisplay[$0.key] == target && $0.key != id }.map(\.key)
        for other in displaced {
            if let otherElement = elements[other] { unpin(other, otherElement, relayoutNow: false) }
        }
        for key in strips.keys { strips[key]!.remove(id) }
        floating.remove(id)
        pinned[id] = side
        pinDisplay[id] = target
        relayout()
    }

    private func unpin(_ id: WindowID, _ element: AXUIElement, relayoutNow: Bool = true) {
        let display = pinDisplay[id]
        pinned[id] = nil
        pinDisplay[id] = nil
        if let display { strips[display, default: Strip()].insert(id) }
        if relayoutNow { relayout() }
    }

    func sendToNextDisplay() {
        guard !paused, let id = focusedID(), pinned[id] == nil, !floating.contains(id) else { return }
        let ids = screens().map(\.id)
        guard ids.count > 1, let from = strips.first(where: { $0.value.contains(id) })?.key,
              let index = ids.firstIndex(of: from) else { return }
        let to = ids[(index + 1) % ids.count]
        strips[from]!.remove(id)
        strips[to, default: Strip()].insert(id)
        relayout()
    }

    private func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private func raiseAndActivate(_ id: WindowID) {
        guard let element = elements[id] else { return }
        AX.raise(element)
        NSRunningApplication(processIdentifier: pid(of: element))?.activate()
    }

    func activate(_ id: WindowID) {
        guard elements[id] != nil else { return }
        for key in strips.keys where strips[key]!.contains(id) { strips[key]!.setFocus(id) }
        raiseAndActivate(id)
        relayout()
    }

    private func info(_ id: WindowID) -> WindowInfo? {
        guard let element = elements[id], let meta = meta[id] else { return nil }
        let app = NSRunningApplication(processIdentifier: meta.pid)
        let state = pinned[id] != nil ? "Pinned" : floating.contains(id) ? "Floating" : ""
        return WindowInfo(id: id, appName: app?.localizedName ?? "App", title: AX.string(element, kAXTitleAttribute) ?? "",
                          icon: app?.icon, state: state)
    }

    func windowInfos() -> [WindowInfo] {
        var ordered: [WindowID] = []
        for screen in screens() { ordered += strips[screen.id]?.windowIDs ?? [] }
        ordered += pinned.keys.sorted()
        ordered += floating.sorted()
        return ordered.compactMap(info)
    }

    func overview() -> (columns: [OverviewColumn], focus: WindowID?) {
        guard let screen = screenUnderMouse(), let strip = strips[screen.id] else { return ([], nil) }
        let columns = strip.columns.map { column in
            OverviewColumn(width: column.width, windows: column.windows.compactMap(info))
        }
        return (columns, strip.focus)
    }

    func saveRow() {
        saveWork?.cancel()
        var saved: [String: [SavedColumn]] = [:]
        let ordered = screens().sorted { $0.bounds.minX < $1.bounds.minX }
        for (index, screen) in ordered.enumerated() {
            guard let strip = strips[screen.id] else { continue }
            saved["\(index)"] = strip.columns.map { column in
                SavedColumn(width: column.width, windows: column.windows.map { id in
                    SavedWindow(bundleID: meta[id]?.bundleID, title: elements[id].flatMap { AX.string($0, kAXTitleAttribute) } ?? "")
                })
            }
        }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: rowFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: rowFile)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveRow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func restoreRow() {
        guard let data = try? Data(contentsOf: rowFile),
              let saved = try? JSONDecoder().decode([String: [SavedColumn]].self, from: data) else { return }
        let ordered = screens().sorted { $0.bounds.minX < $1.bounds.minX }
        for (index, screen) in ordered.enumerated() {
            guard let columns = saved["\(index)"], var strip = strips[screen.id] else { continue }
            var pool = strip.windowIDs
            var assigned: [Int: [Int: WindowID]] = [:]

            func take(_ matches: (WindowID) -> Bool) -> WindowID? {
                guard let at = pool.firstIndex(where: matches) else { return nil }
                return pool.remove(at: at)
            }
            for exactPass in [true, false] {
                for (c, column) in columns.enumerated() {
                    for (w, window) in column.windows.enumerated() where assigned[c]?[w] == nil {
                        let found = take { id in
                            guard self.meta[id]?.bundleID == window.bundleID else { return false }
                            let title = self.elements[id].flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
                            return !exactPass || title == window.title
                        }
                        if let found { assigned[c, default: [:]][w] = found }
                    }
                }
            }
            let plan = columns.enumerated().map { c, column in
                ColumnPlan(windows: column.windows.indices.compactMap { assigned[c]?[$0] }, width: column.width)
            }
            strip.arrange(plan)
            strips[screen.id] = strip
        }
    }
}
