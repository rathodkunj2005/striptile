import AppKit
import StripCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs.shared
    private let manager = WindowManager()
    private let hotKeys = HotKeys()
    private let picker = WindowPicker()
    private let overview = RowOverview()
    private let settings = SettingsWindowController()
    private var statusItem: NSStatusItem!
    private var conflictItem: NSMenuItem?
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch trusted=\(AX.isTrusted(prompt: false))")

        picker.provider = { [m = manager] in m.windowInfos() }
        picker.onChoose = { [m = manager] in m.activate($0) }
        overview.provider = { [m = manager] in m.overview() }
        overview.onChoose = { [m = manager] in m.activate($0) }

        SwipeScroll.shared.fingers = prefs.swipeFingers
        SwipeScroll.shared.onScroll = { [m = manager] dx in m.scrollRow(by: dx) }
        SwipeScroll.shared.onSettle = { [m = manager] in m.settleScroll() }
        if !SwipeScroll.shared.start() { Log.write("multitouch unavailable: swipe disabled") }

        registerHotKeys()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarGlyph()
        rebuildMenu()

        NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            SwipeScroll.shared.fingers = prefs.swipeFingers
            registerHotKeys()
            rebuildMenu()
        }
        startWhenTrusted()
        if CommandLine.arguments.contains("--show-settings") { settings.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.saveRow()
    }

    private func perform(_ action: Action) {
        switch action {
        case .focusLeft: manager.moveFocus(.left)
        case .focusRight: manager.moveFocus(.right)
        case .swapLeft: manager.swap(.left)
        case .swapRight: manager.swap(.right)
        case .cycleWidth: manager.cycleWidth()
        case .fill: manager.fill()
        case .center: manager.center()
        case .stackLeft: manager.stack(.left)
        case .stackRight: manager.stack(.right)
        case .popLeft: manager.popOut(.left)
        case .popRight: manager.popOut(.right)
        case .toggleFloat: manager.toggleFloat()
        case .sendToNextDisplay: manager.sendToNextDisplay()
        case .picker: picker.toggle()
        case .overview: overview.toggle()
        case .pin: manager.cyclePin()
        }
    }

    private func registerHotKeys() {
        hotKeys.register(Action.allCases.map { action in
            (binding: prefs.binding(for: action), action: { [weak self] in self?.perform(action) })
        })
    }

    private func startWhenTrusted() {
        if AX.isTrusted(prompt: true) {
            Log.write("trusted at launch, starting manager")
            manager.start()
            return
        }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AX.isTrusted(prompt: false) else { return }
            timer.invalidate()
            Log.write("trust granted, starting manager")
            self?.manager.start()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let pause = NSMenuItem(title: manager.paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        for action in [Action.picker, .overview] {
            let item = NSMenuItem(title: "\(action.label)   \(prefs.binding(for: action).display)", action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let conflict = NSMenuItem(title: "", action: #selector(openTrackpadSettings), keyEquivalent: "")
        conflict.target = self
        conflict.isHidden = true
        menu.addItem(conflict)
        conflictItem = conflict

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for action in Action.allCases {
            let item = NSMenuItem(title: "\(prefs.binding(for: action).display)   \(action.label)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit StripTile", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private static func menuBarGlyph() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { _ in
            let tiles: [(x: CGFloat, w: CGFloat, alpha: CGFloat)] = [(-3, 7, 0.45), (5, 10, 1), (17, 7, 0.45)]
            for tile in tiles {
                NSColor.black.withAlphaComponent(tile.alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: tile.x, y: 1, width: tile.w, height: 12), xRadius: 2.2, yRadius: 2.2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let conflict = trackpadConflict()
        conflictItem?.isHidden = conflict == nil
        conflictItem?.title = conflict.map { "⚠︎ \($0) — open Trackpad settings" } ?? ""
    }

    private func trackpadConflict() -> String? {
        guard let defaults = UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad") else { return nil }
        if prefs.swipeFingers == 4 {
            return defaults.integer(forKey: "TrackpadFourFingerHorizSwipeGesture") != 0 ? "macOS still uses 4-finger sideways swipes" : nil
        }
        let threeFinger = defaults.integer(forKey: "TrackpadThreeFingerHorizSwipeGesture") != 0
            || defaults.bool(forKey: "TrackpadThreeFingerDrag")
        return threeFinger ? "macOS still uses 3-finger gestures" : nil
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        perform(action)
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func openTrackpadSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    @objc private func togglePause() {
        manager.setPaused(!manager.paused)
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
