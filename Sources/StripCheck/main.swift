import CoreGraphics
import Foundation
import StripCore

var failures = 0
func expect(_ ok: Bool, _ name: String, line: Int = #line) {
    if !ok {
        failures += 1
        print("FAIL \(name) (line \(line))")
    }
}
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

do {
    var s = Strip()
    s.insert(1); s.insert(2); s.setFocus(1); s.insert(3)
    expect(s.windowIDs == [1, 3, 2], "insert goes after focused column")
    expect(s.focus == 3, "insert focuses new window")
}

do {
    var s = Strip()
    s.insert(1); s.insert(2)
    let f = s.layout(in: screen, gap: 10)
    expect(near(f[1]!.minX, 10), "two halves: left edge")
    expect(near(f[1]!.maxX + 10, f[2]!.minX), "two halves: gap between")
    expect(near(f[2]!.maxX, 990), "two halves: right edge")
    expect(near(f[1]!.height, 780), "height respects outer gap")
}

do {
    var s = Strip()
    [1, 2, 3].forEach { s.insert($0) }
    let f = s.layout(in: screen, gap: 10)
    expect(near(f[3]!.maxX, 990), "row scrolls to reveal new window")
    expect(f[1]!.maxX <= 0.001, "earlier window slides off-screen")
    expect(near(f[1]!.width, f[3]!.width), "existing sizes preserved")
    s.setFocus(1)
    let g = s.layout(in: screen, gap: 10)
    expect(near(g[1]!.minX, 10), "row scrolls back on focus")
}

do {
    var s = Strip()
    [1, 2, 3].forEach { s.insert($0) }
    s.setFocus(2); s.remove(2)
    expect(s.windowIDs == [1, 3] && s.focus == 3, "remove focused moves focus right")
    s.remove(3)
    expect(s.focus == 1, "remove last falls back left")
    s.remove(1)
    expect(s.focus == nil, "empty strip has no focus")
}

do {
    var s = Strip()
    [1, 2].forEach { s.insert($0) }
    s.stack(.left)
    expect(s.columns.count == 1 && s.columns[0].windows == [1, 2], "stack merges columns")
    let f = s.layout(in: screen, gap: 10)
    expect(near(f[1]!.height, 385), "stacked windows split height")
    expect(near(f[2]!.minY, f[1]!.maxY + 10), "stacked windows have gap")
    s.popOut(.right)
    expect(s.columns.map(\.windows) == [[1], [2]], "pop out splits column")
}

do {
    var s = Strip()
    [1, 2, 3].forEach { s.insert($0) }
    s.swap(.left)
    expect(s.windowIDs == [1, 3, 2], "swap with left neighbor")
}

do {
    var s = Strip()
    s.insert(1)
    s.cycleWidth()
    expect(near(CGFloat(s.columns[0].width), 2.0 / 3.0), "cycle: half to two thirds")
    s.cycleWidth()
    expect(near(CGFloat(s.columns[0].width), 1), "cycle: two thirds to full")
    s.cycleWidth()
    expect(near(CGFloat(s.columns[0].width), 0.5), "cycle: full wraps to half")
}

do {
    var s = Strip()
    [1, 2, 3].forEach { s.insert($0) }
    s.setFocus(2); s.center()
    let f = s.layout(in: screen, gap: 10)
    expect(near(f[2]!.midX, 500), "center puts focused column mid-screen")
}

do {
    var s = Strip()
    [1, 2, 3].forEach { s.insert($0) }
    _ = s.layout(in: screen, gap: 10)
    s.scroll(by: 300)
    let f = s.layout(in: screen, gap: 10)
    expect(near(f[3]!.minX, 505 + 300), "scroll right moves content with fingers")
    expect(near(f[3]!.width, 485), "scroll keeps sizes")
    s.scroll(by: 10_000)
    expect(near(s.layout(in: screen, gap: 10)[1]!.minX, 10), "scroll clamps at start")
    s.scroll(by: -10_000)
    expect(near(s.layout(in: screen, gap: 10)[3]!.maxX, 990), "scroll clamps at end")
    s.scroll(by: 300)
    _ = s.layout(in: screen, gap: 10)
    s.setFocus(1)
    expect(near(s.layout(in: screen, gap: 10)[1]!.minX, 10), "focus change cancels manual scroll")
    s.scroll(by: 100)
    let g = s.layout(in: screen, gap: 10)
    expect(near(g[1]!.minX, 10), "cannot scroll past start from offset 0")
}

do {
    var s = Strip()
    [1, 2, 3, 4].forEach { s.insert($0) }
    s.stack(.left)
    s.arrange([ColumnPlan(windows: [3], width: 1), ColumnPlan(windows: [1, 99], width: 2.0 / 3.0)])
    expect(s.columns.map(\.windows) == [[3], [1], [2], [4]], "arrange: plan first, unknown dropped, leftovers appended")
    expect(near(CGFloat(s.columns[0].width), 1) && near(CGFloat(s.columns[1].width), 2.0 / 3.0), "arrange keeps planned widths")
}

do {
    var s = Strip()
    [1, 2, 3].forEach { s.insert($0) }
    _ = s.layout(in: screen, gap: 10)
    s.scroll(by: 200)
    _ = s.layout(in: screen, gap: 10)
    let delta = s.snapDelta(in: screen, gap: 10)
    s.scroll(by: delta)
    let f = s.layout(in: screen, gap: 10)
    let aligned = f.values.contains { near($0.minX, 10) }
    expect(aligned, "snap aligns a column to the left edge")
    expect(near(s.snapDelta(in: screen, gap: 10), 0), "snap is idempotent")
    var fresh = Strip()
    fresh.insert(1)
    expect(near(fresh.snapDelta(in: screen, gap: 10), 0), "no snap without manual scroll")
}

do {
    expect(fuzzyScore("sfr", in: "Safari – Reading List") != nil, "fuzzy subsequence matches")
    expect(fuzzyScore("zzz", in: "Safari") == nil, "fuzzy rejects non-subsequence")
    let strong = fuzzyScore("saf", in: "Safari")!
    let weak = fuzzyScore("saf", in: "Some Archive File")!
    expect(strong > weak, "fuzzy prefers consecutive matches")
    expect(fuzzyScore("", in: "anything") == 0, "empty query matches everything")
}

print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
