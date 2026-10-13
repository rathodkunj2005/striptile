import CoreGraphics

public typealias WindowID = UInt32

public struct Column: Equatable {
    public var windows: [WindowID]
    public var width: Double
}

public struct ColumnPlan {
    public var windows: [WindowID]
    public var width: Double

    public init(windows: [WindowID], width: Double) {
        self.windows = windows
        self.width = width
    }
}

public enum Side {
    case left, right

    var delta: Int { self == .left ? -1 : 1 }
}

public struct Strip {
    public static let widthSteps: [Double] = [0.5, 2.0 / 3.0, 1.0]

    public private(set) var columns: [Column] = []
    public private(set) var focus: WindowID?
    public private(set) var offset: CGFloat = 0
    private var centerOnNextLayout = false
    private var manualScroll = false
    private var pendingScroll: CGFloat = 0

    public init() {}

    public var windowIDs: [WindowID] { columns.flatMap(\.windows) }

    public func contains(_ id: WindowID) -> Bool { locate(id) != nil }

    func locate(_ id: WindowID) -> (col: Int, row: Int)? {
        for (c, column) in columns.enumerated() {
            if let r = column.windows.firstIndex(of: id) { return (c, r) }
        }
        return nil
    }

    public mutating func insert(_ id: WindowID, width: Double = Strip.widthSteps[0]) {
        guard !contains(id) else { return }
        let at = focus.flatMap(locate).map { $0.col + 1 } ?? columns.count
        columns.insert(Column(windows: [id], width: width), at: at)
        focus = id
        manualScroll = false
    }

    public mutating func remove(_ id: WindowID) {
        guard let (c, r) = locate(id) else { return }
        columns[c].windows.remove(at: r)
        if columns[c].windows.isEmpty { columns.remove(at: c) }
        guard focus == id else { return }
        if columns.isEmpty {
            focus = nil
            return
        }
        let next = min(c, columns.count - 1)
        focus = columns[next].windows[min(r, columns[next].windows.count - 1)]
    }

    public mutating func setFocus(_ id: WindowID) {
        guard contains(id), focus != id else { return }
        focus = id
        manualScroll = false
    }

    public mutating func scroll(by dx: CGFloat) {
        pendingScroll -= dx
    }

    @discardableResult
    public mutating func moveFocus(_ side: Side) -> WindowID? {
        guard let (c, r) = focus.flatMap(locate) else { return nil }
        let target = c + side.delta
        guard columns.indices.contains(target) else { return focus }
        focus = columns[target].windows[min(r, columns[target].windows.count - 1)]
        manualScroll = false
        return focus
    }

    public mutating func swap(_ side: Side) {
        guard let (c, _) = focus.flatMap(locate) else { return }
        let target = c + side.delta
        guard columns.indices.contains(target) else { return }
        columns.swapAt(c, target)
        manualScroll = false
    }

    public mutating func cycleWidth() {
        guard let (c, _) = focus.flatMap(locate) else { return }
        let steps = Strip.widthSteps
        let current = steps.enumerated().min { abs($0.element - columns[c].width) < abs($1.element - columns[c].width) }!.offset
        columns[c].width = steps[(current + 1) % steps.count]
        manualScroll = false
    }

    public mutating func fill() {
        guard let (c, _) = focus.flatMap(locate) else { return }
        columns[c].width = 1
        manualScroll = false
    }

    public mutating func center() {
        centerOnNextLayout = true
        manualScroll = false
    }

    public mutating func stack(_ side: Side) {
        guard let id = focus, let (c, r) = locate(id) else { return }
        let target = c + side.delta
        guard columns.indices.contains(target) else { return }
        columns[c].windows.remove(at: r)
        columns[target].windows.append(id)
        if columns[c].windows.isEmpty { columns.remove(at: c) }
        manualScroll = false
    }

    public mutating func popOut(_ side: Side) {
        guard let id = focus, let (c, r) = locate(id), columns[c].windows.count > 1 else { return }
        columns[c].windows.remove(at: r)
        let at = side == .left ? c : c + 1
        columns.insert(Column(windows: [id], width: columns[c].width), at: at)
        manualScroll = false
    }

    private func metrics(usableW: CGFloat, gap: CGFloat) -> (lefts: [CGFloat], widths: [CGFloat], end: CGFloat) {
        var lefts: [CGFloat] = []
        var widths: [CGFloat] = []
        var cursor: CGFloat = 0
        for column in columns {
            let w = max(1, CGFloat(column.width) * (usableW + gap) - gap)
            lefts.append(cursor)
            widths.append(w)
            cursor += w + gap
        }
        return (lefts, widths, cursor)
    }

    public func snapDelta(in rect: CGRect, gap: CGFloat) -> CGFloat {
        guard manualScroll, !columns.isEmpty else { return 0 }
        let usableW = max(1, rect.width - 2 * gap)
        let m = metrics(usableW: usableW, gap: gap)
        let maxOffset = max(0, m.end - gap - usableW)
        let nearest = m.lefts.min { abs($0 - offset) < abs($1 - offset) } ?? offset
        return offset - min(nearest, maxOffset)
    }

    public mutating func arrange(_ plan: [ColumnPlan]) {
        let existing = Set(windowIDs)
        var seen = Set<WindowID>()
        var result: [Column] = []
        for entry in plan {
            let kept = entry.windows.filter { existing.contains($0) && seen.insert($0).inserted }
            if !kept.isEmpty { result.append(Column(windows: kept, width: entry.width)) }
        }
        for column in columns {
            let rest = column.windows.filter { seen.insert($0).inserted }
            if !rest.isEmpty { result.append(Column(windows: rest, width: column.width)) }
        }
        columns = result
        manualScroll = false
    }

    public mutating func layout(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        guard !columns.isEmpty else { return [:] }
        let usableW = max(1, rect.width - 2 * gap)
        let usableH = max(1, rect.height - 2 * gap)

        let m = metrics(usableW: usableW, gap: gap)
        let lefts = m.lefts
        let widths = m.widths
        let cursor = m.end

        let maxOffset = max(0, cursor - gap - usableW)
        if pendingScroll != 0 {
            offset = min(max(0, offset + pendingScroll), maxOffset)
            pendingScroll = 0
            manualScroll = true
        }

        if !manualScroll, let (c, _) = focus.flatMap(locate) {
            if centerOnNextLayout {
                offset = lefts[c] + widths[c] / 2 - usableW / 2
            } else if lefts[c] < offset {
                offset = lefts[c]
            } else if lefts[c] + widths[c] > offset + usableW {
                offset = lefts[c] + widths[c] - usableW
            }
        }
        centerOnNextLayout = false

        var frames: [WindowID: CGRect] = [:]
        for (c, column) in columns.enumerated() {
            let n = CGFloat(column.windows.count)
            let h = (usableH - (n - 1) * gap) / n
            let x = rect.minX + gap + lefts[c] - offset
            for (r, id) in column.windows.enumerated() {
                let y = rect.minY + gap + CGFloat(r) * (h + gap)
                frames[id] = CGRect(x: x, y: y, width: widths[c], height: h)
            }
        }
        return frames
    }
}
