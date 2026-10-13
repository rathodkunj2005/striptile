import AppKit
import StripCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class WindowPicker: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    var provider: () -> [WindowInfo] = { [] }
    var onChoose: (WindowID) -> Void = { _ in }

    private var panel: FloatingPanel?
    private let field = NSSearchField()
    private let table = NSTableView()
    private var all: [WindowInfo] = []
    private var shown: [WindowInfo] = []

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    private func show() {
        all = provider()
        shown = all
        let panel = panel ?? makePanel()
        self.panel = panel
        field.stringValue = ""
        table.reloadData()
        selectRow(0)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY + frame.height * 0.12))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    private func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self

        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        panel.contentView = background

        field.placeholderString = "Jump to a window"
        field.font = .systemFont(ofSize: 20)
        field.focusRingType = .none
        field.delegate = self
        field.frame = NSRect(x: 16, y: 366, width: 588, height: 40)
        background.addSubview(field)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.width = 580
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 44
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(choose)
        table.selectionHighlightStyle = .regular

        let scroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: 604, height: 346))
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        background.addSubview(scroll)
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func controlTextDidChange(_ notification: Notification) {
        let query = field.stringValue
        shown = all
            .compactMap { info in fuzzyScore(query, in: info.searchText).map { (info, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        table.reloadData()
        selectRow(0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            selectRow(table.selectedRow + 1)
        case #selector(NSResponder.moveUp(_:)):
            selectRow(table.selectedRow - 1)
        case #selector(NSResponder.insertNewline(_:)):
            choose()
        case #selector(NSResponder.cancelOperation(_:)):
            close()
        default:
            return false
        }
        return true
    }

    private func selectRow(_ row: Int) {
        guard !shown.isEmpty else { return }
        let clamped = min(max(0, row), shown.count - 1)
        table.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        table.scrollRowToVisible(clamped)
    }

    @objc private func choose() {
        let row = table.selectedRow
        guard shown.indices.contains(row) else { return }
        let id = shown[row].id
        close()
        onChoose(id)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let info = shown[row]
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 44))

        let icon = NSImageView(frame: NSRect(x: 8, y: 6, width: 32, height: 32))
        icon.image = info.icon
        cell.addSubview(icon)

        let name = NSTextField(labelWithString: info.appName)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.frame = NSRect(x: 50, y: 22, width: 420, height: 18)
        cell.addSubview(name)

        let title = NSTextField(labelWithString: info.title.isEmpty ? "Untitled window" : info.title)
        title.font = .systemFont(ofSize: 12)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 50, y: 4, width: 420, height: 16)
        cell.addSubview(title)

        if !info.state.isEmpty {
            let badge = NSTextField(labelWithString: info.state)
            badge.font = .systemFont(ofSize: 11, weight: .medium)
            badge.textColor = .tertiaryLabelColor
            badge.alignment = .right
            badge.frame = NSRect(x: 480, y: 14, width: 90, height: 16)
            cell.addSubview(badge)
        }
        return cell
    }
}
