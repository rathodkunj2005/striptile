import AppKit
import StripCore

private final class OverviewView: NSView {
    struct Tile {
        let rect: NSRect
        let info: WindowInfo
    }

    var columns: [OverviewColumn] = [] { didSet { rebuild() } }
    var focus: WindowID?
    var selected = 0
    var onChoose: (WindowID) -> Void = { _ in }
    var onCancel: () -> Void = {}
    private var tiles: [Tile] = []

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        rebuild()
    }

    func selectFocused() {
        selected = tiles.firstIndex { $0.info.id == focus } ?? 0
        needsDisplay = true
    }

    private func rebuild() {
        tiles = []
        guard !columns.isEmpty else { return }
        let pad: CGFloat = 28
        let gap: CGFloat = 14
        let totalFraction = columns.reduce(0) { $0 + $1.width }
        let available = bounds.width - 2 * pad - gap * CGFloat(columns.count - 1)
        let unit = min(300, max(60, available / CGFloat(totalFraction)))
        let usedWidth = unit * CGFloat(totalFraction) + gap * CGFloat(columns.count - 1)
        var x = (bounds.width - usedWidth) / 2
        let height = bounds.height - 2 * pad
        for column in columns {
            let width = unit * CGFloat(column.width)
            let rows = CGFloat(max(1, column.windows.count))
            let rowHeight = (height - 10 * (rows - 1)) / rows
            for (index, info) in column.windows.enumerated() {
                let y = bounds.height - pad - CGFloat(index + 1) * rowHeight - CGFloat(index) * 10
                tiles.append(Tile(rect: NSRect(x: x, y: y, width: width, height: rowHeight), info: info))
            }
            x += width + gap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !tiles.isEmpty else {
            let text = "No windows in this row" as NSString
            text.draw(at: NSPoint(x: 28, y: bounds.midY), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor])
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        for (index, tile) in tiles.enumerated() {
            let path = NSBezierPath(roundedRect: tile.rect, xRadius: 12, yRadius: 12)
            (index == selected ? NSColor.controlAccentColor.withAlphaComponent(0.38) : NSColor.white.withAlphaComponent(0.10)).setFill()
            path.fill()
            if tile.info.id == focus {
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
            let iconSize = min(40, tile.rect.height - 40, tile.rect.width - 16)
            if iconSize > 12 {
                tile.info.icon?.draw(in: NSRect(x: tile.rect.midX - iconSize / 2, y: tile.rect.midY - iconSize / 2 + 8, width: iconSize, height: iconSize))
            }
            (tile.info.appName as NSString).draw(
                in: NSRect(x: tile.rect.minX + 8, y: tile.rect.midY - iconSize / 2 - 12, width: tile.rect.width - 16, height: 16),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
            if !tile.info.title.isEmpty, tile.rect.height > 90 {
                (tile.info.title as NSString).draw(
                    in: NSRect(x: tile.rect.minX + 8, y: tile.rect.midY - iconSize / 2 - 30, width: tile.rect.width - 16, height: 15),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let tile = tiles.first(where: { $0.rect.contains(point) }) { onChoose(tile.info.id) }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 123, 126:
            selected = max(0, selected - 1)
        case 124, 125:
            selected = min(tiles.count - 1, selected + 1)
        case 36, 76:
            if tiles.indices.contains(selected) { onChoose(tiles[selected].info.id) }
        case 53:
            onCancel()
        default:
            super.keyDown(with: event)
        }
        needsDisplay = true
    }
}

final class RowOverview: NSObject, NSWindowDelegate {
    var provider: () -> (columns: [OverviewColumn], focus: WindowID?) = { ([], nil) }
    var onChoose: (WindowID) -> Void = { _ in }

    private var panel: FloatingPanel?
    private let view = OverviewView()

    func toggle() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            show()
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let data = provider()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let width = min(frame.width - 80, 1600)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - 170, width: width, height: 340), display: true)
        }
        view.frame = panel.contentView!.bounds
        view.focus = data.focus
        view.columns = data.columns
        view.selectFocused()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 340),
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
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        panel.contentView = background

        view.frame = background.bounds
        view.autoresizingMask = [.width, .height]
        view.onChoose = { [weak self] id in
            self?.panel?.orderOut(nil)
            self?.onChoose(id)
        }
        view.onCancel = { [weak self] in self?.panel?.orderOut(nil) }
        background.addSubview(view)
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
    }
}
