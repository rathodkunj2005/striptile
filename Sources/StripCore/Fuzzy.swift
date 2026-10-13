public func fuzzyScore(_ query: String, in text: String) -> Int? {
    let needle = Array(query.lowercased().filter { !$0.isWhitespace })
    let hay = Array(text.lowercased())
    guard !needle.isEmpty else { return 0 }
    var score = 0
    var next = 0
    var previous = -2
    for ch in needle {
        guard let found = hay[next...].firstIndex(of: ch) else { return nil }
        score += 10
        if found == previous + 1 { score += 15 }
        if found == 0 || !(hay[found - 1].isLetter || hay[found - 1].isNumber) { score += 12 }
        score -= min(found - next, 8)
        previous = found
        next = found + 1
    }
    return score
}
