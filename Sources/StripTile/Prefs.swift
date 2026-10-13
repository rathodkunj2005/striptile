import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let prefsChanged = Notification.Name("striptile.prefsChanged")
}

enum RuleMode: String, Codable, CaseIterable {
    case tile, float, ignore

    var label: String {
        switch self {
        case .tile: return "Tile"
        case .float: return "Float"
        case .ignore: return "Ignore"
        }
    }
}

struct AppRule: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var mode: RuleMode
    var width: Double?

    var id: String { bundleID }
}

struct KeyBinding: Codable, Equatable {
    var keyCode: Int
    var modifiers: UInt32

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + KeyNames.name(for: keyCode)
    }
}

enum Action: String, CaseIterable, Codable {
    case focusLeft, focusRight, swapLeft, swapRight, cycleWidth, fill, center
    case stackLeft, stackRight, popLeft, popRight, toggleFloat, sendToNextDisplay
    case picker, overview, pin

    var label: String {
        switch self {
        case .focusLeft: return "Focus left"
        case .focusRight: return "Focus right"
        case .swapLeft: return "Swap left"
        case .swapRight: return "Swap right"
        case .cycleWidth: return "Cycle width ½ · ⅔ · full"
        case .fill: return "Fill screen"
        case .center: return "Center window"
        case .stackLeft: return "Stack into left column"
        case .stackRight: return "Stack into right column"
        case .popLeft: return "Pop out to the left"
        case .popRight: return "Pop out to the right"
        case .toggleFloat: return "Float / unfloat"
        case .sendToNextDisplay: return "Send to next display"
        case .picker: return "Window picker"
        case .overview: return "Row overview"
        case .pin: return "Pin to edge (right → left → off)"
        }
    }

    var defaultBinding: KeyBinding {
        let base = UInt32(controlKey | optionKey)
        let shifted = base | UInt32(shiftKey)
        switch self {
        case .focusLeft: return KeyBinding(keyCode: kVK_LeftArrow, modifiers: base)
        case .focusRight: return KeyBinding(keyCode: kVK_RightArrow, modifiers: base)
        case .swapLeft: return KeyBinding(keyCode: kVK_LeftArrow, modifiers: shifted)
        case .swapRight: return KeyBinding(keyCode: kVK_RightArrow, modifiers: shifted)
        case .cycleWidth: return KeyBinding(keyCode: kVK_ANSI_R, modifiers: base)
        case .fill: return KeyBinding(keyCode: kVK_ANSI_F, modifiers: base)
        case .center: return KeyBinding(keyCode: kVK_ANSI_C, modifiers: base)
        case .stackLeft: return KeyBinding(keyCode: kVK_ANSI_LeftBracket, modifiers: base)
        case .stackRight: return KeyBinding(keyCode: kVK_ANSI_RightBracket, modifiers: base)
        case .popLeft: return KeyBinding(keyCode: kVK_ANSI_LeftBracket, modifiers: shifted)
        case .popRight: return KeyBinding(keyCode: kVK_ANSI_RightBracket, modifiers: shifted)
        case .toggleFloat: return KeyBinding(keyCode: kVK_ANSI_T, modifiers: base)
        case .sendToNextDisplay: return KeyBinding(keyCode: kVK_ANSI_N, modifiers: base)
        case .picker: return KeyBinding(keyCode: kVK_Space, modifiers: base)
        case .overview: return KeyBinding(keyCode: kVK_ANSI_O, modifiers: base)
        case .pin: return KeyBinding(keyCode: kVK_ANSI_P, modifiers: base)
        }
    }
}

enum KeyNames {
    private static let table: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]

    static func name(for keyCode: Int) -> String { table[keyCode] ?? "Key \(keyCode)" }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let defaults = UserDefaults.standard

    @Published var gap: Double { didSet { store(gap, "gap") } }
    @Published var swipeFingers: Int { didSet { store(swipeFingers, "swipeFingers") } }
    @Published var naturalScroll: Bool { didSet { store(naturalScroll, "naturalScroll") } }
    @Published var swipeGain: Double { didSet { store(swipeGain, "swipeGain") } }
    @Published var snapToColumns: Bool { didSet { store(snapToColumns, "snapToColumns") } }
    @Published var pinWidth: Double { didSet { store(pinWidth, "pinWidth") } }
    @Published var restoreRow: Bool { didSet { store(restoreRow, "restoreRow") } }
    @Published var rules: [AppRule] { didSet { storeJSON(rules, "rules") } }
    @Published var bindings: [String: KeyBinding] { didSet { storeJSON(bindings, "bindings") } }

    private init() {
        let d = UserDefaults.standard
        gap = d.object(forKey: "gap") as? Double ?? 8
        let fingers = d.integer(forKey: "swipeFingers")
        swipeFingers = fingers == 3 ? 3 : 4
        naturalScroll = d.object(forKey: "naturalScroll") as? Bool ?? true
        swipeGain = d.object(forKey: "swipeGain") as? Double ?? 1.8
        snapToColumns = d.object(forKey: "snapToColumns") as? Bool ?? true
        pinWidth = d.object(forKey: "pinWidth") as? Double ?? 0.25
        restoreRow = d.object(forKey: "restoreRow") as? Bool ?? true
        rules = Self.load([AppRule].self, "rules") ?? Self.defaultRules
        bindings = Self.load([String: KeyBinding].self, "bindings") ?? [:]
    }

    static let defaultRules = [
        AppRule(bundleID: "com.apple.calculator", name: "Calculator", mode: .float, width: nil),
        AppRule(bundleID: "com.apple.systempreferences", name: "System Settings", mode: .float, width: nil),
    ]

    func binding(for action: Action) -> KeyBinding { bindings[action.rawValue] ?? action.defaultBinding }

    func rule(for bundleID: String) -> AppRule? { rules.first { $0.bundleID == bundleID } }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        announce()
    }

    private func storeJSON<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
        announce()
    }

    private func announce() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .prefsChanged, object: nil) }
    }
}
