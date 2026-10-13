import AppKit
import Carbon.HIToolbox
import SwiftUI

private final class RecorderView: NSView {
    var binding = KeyBinding(keyCode: 0, modifiers: 0) { didSet { needsDisplay = true } }
    var onChange: (KeyBinding) -> Void = { _ in }
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 26) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.quaternaryLabelColor.withAlphaComponent(0.25)).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = (recording ? "Press shortcut…" : binding.display) as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(in: NSRect(x: 0, y: 4, width: bounds.width, height: 18),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            return
        }
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        recording = false
        onChange(KeyBinding(keyCode: Int(event.keyCode), modifiers: modifiers))
    }
}

private struct KeyRecorder: NSViewRepresentable {
    let binding: KeyBinding
    let onChange: (KeyBinding) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.binding = binding
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? RecorderView else { return }
        view.binding = binding
        view.onChange = onChange
    }
}

private struct GeneralTab: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        Form {
            Section("Layout") {
                HStack {
                    Text("Spacing")
                    Slider(value: $prefs.gap, in: 0...32, step: 2)
                    Text("\(Int(prefs.gap)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Pinned window width")
                    Slider(value: $prefs.pinWidth, in: 0.15...0.4, step: 0.05)
                    Text("\(Int(prefs.pinWidth * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle("Restore the row order when StripTile starts", isOn: $prefs.restoreRow)
            }
            Section("Trackpad") {
                Picker("Swipe with", selection: $prefs.swipeFingers) {
                    Text("3 fingers").tag(3)
                    Text("4 fingers").tag(4)
                }
                .pickerStyle(.segmented)
                Toggle("Row follows your fingers", isOn: $prefs.naturalScroll)
                Toggle("Snap to the nearest column after a swipe", isOn: $prefs.snapToColumns)
                HStack {
                    Text("Swipe speed")
                    Slider(value: $prefs.swipeGain, in: 0.6...3.5)
                    Text(String(format: "%.1f×", prefs.swipeGain)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Button("Open Trackpad Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsTab: View {
    @ObservedObject var prefs: Prefs

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && prefs.rule(for: $0.bundleIdentifier!) == nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose how each app behaves. Tile joins the row, Float is left alone, Ignore is never touched. Width applies to new windows.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach($prefs.rules) { $rule in
                    HStack {
                        Text(rule.name).frame(minWidth: 120, alignment: .leading)
                        Spacer()
                        Picker("", selection: $rule.mode) {
                            ForEach(RuleMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        Picker("", selection: Binding(get: { rule.width ?? 0 }, set: { rule.width = $0 == 0 ? nil : $0 })) {
                            Text("Default").tag(0.0)
                            Text("½").tag(0.5)
                            Text("⅔").tag(2.0 / 3.0)
                            Text("Full").tag(1.0)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        .disabled(rule.mode != .tile)
                        Button(role: .destructive) {
                            prefs.rules.removeAll { $0.bundleID == rule.bundleID }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Menu("Add a running app…") {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier!) {
                        prefs.rules.append(AppRule(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!, mode: .float, width: nil))
                    }
                }
            }
            .fixedSize()
        }
        .padding()
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        List(Action.allCases, id: \.self) { action in
            HStack {
                Text(action.label)
                Spacer()
                KeyRecorder(binding: prefs.binding(for: action)) { prefs.bindings[action.rawValue] = $0 }
                    .frame(width: 130, height: 26)
                Button {
                    prefs.bindings[action.rawValue] = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
                .disabled(prefs.bindings[action.rawValue] == nil)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs).tabItem { Label("General", systemImage: "slider.horizontal.3") }
            AppsTab(prefs: prefs).tabItem { Label("Apps", systemImage: "app.badge") }
            ShortcutsTab(prefs: prefs).tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 580, height: 470)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "StripTile Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
