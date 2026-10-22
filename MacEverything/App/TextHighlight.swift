import SwiftUI

/// Shared highlight function used by ResultRow and ContentResultRow.
/// Finds all case-insensitive, non-overlapping occurrences of `keyword`
/// in `text` and renders matched segments in bold + `highlightColor`.
/// For glob-style keywords containing `*` or `?`, highlights the literal
/// (non-wildcard) segments extracted from the pattern.
func highlightMatches(in text: String, keyword: String,
                      font: Font, color: Color,
                      highlightColor: Color = .accentColor) -> Text {
    guard !keyword.isEmpty else {
        return Text(text).font(font).foregroundColor(color)
    }

    let lowerKey = keyword.lowercased()

    // Glob patterns — highlight literal (non-wildcard) segments
    if lowerKey.contains("*") || lowerKey.contains("?") {
        let literals = extractGlobLiterals(keyword)
        if literals.isEmpty {
            return Text(text).font(font).foregroundColor(color)
        }
        let ranges = findAllLiteralRanges(in: text, literals: literals)
        return buildHighlightedText(text: text, ranges: ranges, font: font, color: color, highlightColor: highlightColor)
    }

    // Multi-keyword: split by spaces and find all matches for each word
    let words = keyword.components(separatedBy: " ").filter { !$0.isEmpty }
    if words.isEmpty {
        return Text(text).font(font).foregroundColor(color)
    }

    // NOTE: ranges must always be computed on `text` itself (never on a
    // lowercased() copy) — String.Index values are only valid for the
    // string instance that produced them.
    let ranges: [Range<String.Index>]
    if words.count == 1 {
        // Single keyword — simple forward scan, case-insensitive
        var singleRanges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: words[0], options: [.caseInsensitive],
                                     range: searchStart..<text.endIndex) {
            singleRanges.append(range)
            searchStart = range.upperBound
        }
        ranges = singleRanges
    } else {
        // Multiple keywords — find all matches for each, merge ranges
        ranges = findAllLiteralRanges(in: text, literals: words)
    }

    if ranges.isEmpty {
        return Text(text).font(font).foregroundColor(color)
    }

    return buildHighlightedText(text: text, ranges: ranges, font: font,
                                color: color, highlightColor: highlightColor)
}

/// Cross-boundary highlight: matches keyword against `path + "/" + name` (the full path),
/// then maps matched ranges back to path and name individually.
/// This handles keywords like "test/goodprice" where "test" is at the end of `path`
/// and "goodprice" is the `name`.
///
/// Only activates cross-boundary logic when keyword contains "/"; otherwise falls back
/// to independent matching on each component.
func highlightCrossMatches(path: String, name: String, keyword: String,
                           nameFont: Font, nameColor: Color,
                           pathFont: Font, pathColor: Color,
                           highlightColor: Color = .accentColor) -> (nameText: Text, pathText: Text) {
    // Fast path: no keyword or no "/" in keyword — independent matching works fine
    if keyword.isEmpty || !keyword.contains("/") ||
       keyword.lowercased().contains("*") || keyword.lowercased().contains("?") {
        let nameText = highlightMatches(in: name, keyword: keyword, font: nameFont, color: nameColor, highlightColor: highlightColor)
        let pathText = highlightMatches(in: path, keyword: keyword, font: pathFont, color: pathColor, highlightColor: highlightColor)
        return (nameText, pathText)
    }

    let fullPath = path + "/" + name

    // Find all matches in fullPath (supports multi-keyword via space splitting)
    let words = keyword.components(separatedBy: " ").filter { !$0.isEmpty }
    var fullRanges: [Range<String.Index>]
    if words.count <= 1 {
        fullRanges = []
        var searchStart = fullPath.startIndex
        while searchStart < fullPath.endIndex,
              let range = fullPath.range(of: keyword, options: [.caseInsensitive],
                                         range: searchStart..<fullPath.endIndex) {
            fullRanges.append(range)
            searchStart = range.upperBound
        }
    } else {
        fullRanges = findAllLiteralRanges(in: fullPath, literals: words)
    }

    if fullRanges.isEmpty {
        // No matches at all — return plain text
        return (Text(name).font(nameFont).foregroundColor(nameColor),
                Text(path).font(pathFont).foregroundColor(pathColor))
    }

    // Map fullPath ranges back onto path and name (rebuilding indices per string)
    let (pathRanges, nameRanges) = mapFullPathRanges(fullRanges,
                                                     fullPath: fullPath,
                                                     path: path,
                                                     name: name)

    // Build highlighted Text for name
    let nameText = buildHighlightedText(text: name, ranges: nameRanges, font: nameFont, color: nameColor, highlightColor: highlightColor)
    // Build highlighted Text for path
    let pathText = buildHighlightedText(text: path, ranges: pathRanges, font: pathFont, color: pathColor, highlightColor: highlightColor)

    return (nameText, pathText)
}

/// Extract literal (non-wildcard) segments from a glob pattern.
/// Splits by `*` and `?`, returns non-empty segments.
func extractGlobLiterals(_ pattern: String) -> [String] {
    pattern.components(separatedBy: CharacterSet(charactersIn: "*?"))
           .filter { !$0.isEmpty }
}

/// Find all case-insensitive occurrences of any literal in `text`,
/// merge overlapping ranges, and return sorted non-overlapping ranges.
/// Ranges are always relative to `text` itself so they stay valid for slicing.
func findAllLiteralRanges(in text: String, literals: [String],
                          caseInsensitive: Bool = true) -> [Range<String.Index>] {
    var allRanges: [Range<String.Index>] = []
    let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
    for literal in literals where !literal.isEmpty {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: literal, options: options,
                                     range: searchStart..<text.endIndex) {
            allRanges.append(range)
            searchStart = range.upperBound
        }
    }
    guard !allRanges.isEmpty else { return [] }

    // Sort by start position, then merge overlapping/adjacent ranges
    allRanges.sort { $0.lowerBound < $1.lowerBound }
    var merged: [Range<String.Index>] = [allRanges[0]]
    for range in allRanges.dropFirst() {
        if range.lowerBound <= merged[merged.count - 1].upperBound {
            let last = merged[merged.count - 1]
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
        } else {
            merged.append(range)
        }
    }
    return merged
}

/// Helper: build a SwiftUI Text with specified ranges highlighted.
/// The result is a single AttributedString rendered via `Text(attr)` —
/// concatenating `Text` values with `+` is avoided on purpose, because
/// SwiftUI can drop trailing runs of a concatenated Text when it is
/// clipped/truncated to one line, which silently cuts off file names.
func buildHighlightedText(text: String, ranges: [Range<String.Index>],
                                  font: Font, color: Color,
                                  highlightColor: Color) -> Text {
    if ranges.isEmpty {
        return Text(text).font(font).foregroundColor(color)
    }

    var result = AttributedString()
    var currentIndex = text.startIndex

    for range in ranges {
        if currentIndex < range.lowerBound {
            var segment = AttributedString(String(text[currentIndex..<range.lowerBound]))
            segment.font = font
            segment.foregroundColor = color
            result.append(segment)
        }
        var segment = AttributedString(String(text[range]))
        segment.font = font.bold()
        segment.foregroundColor = highlightColor
        result.append(segment)
        currentIndex = range.upperBound
    }

    if currentIndex < text.endIndex {
        var segment = AttributedString(String(text[currentIndex..<text.endIndex]))
        segment.font = font
        segment.foregroundColor = color
        result.append(segment)
    }

    return Text(result)
}

// MARK: - Hint-based highlighting

/// Compute matching ranges for a single HighlightHint in the given text.
func computeRangesForHint(in text: String, hint: HighlightHint) -> [Range<String.Index>] {
    guard !hint.text.isEmpty else { return [] }

    // Always search `text` itself. `String.Index` values belong to the
    // string instance that created them, so searching a lowercased() copy
    // and slicing the original silently corrupts or truncates the output.
    let searchKey = hint.text
    let options: String.CompareOptions = hint.caseSensitive ? [] : [.caseInsensitive]

    switch hint.matchMode {
    case .substring:
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: searchKey, options: options,
                                     range: start..<text.endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges

    case .glob:
        let literals = extractGlobLiterals(searchKey)
        if literals.isEmpty { return [] }
        return findAllLiteralRanges(in: text, literals: literals,
                                    caseInsensitive: !hint.caseSensitive)

    case .regex:
        var options: NSRegularExpression.Options = []
        if !hint.caseSensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: hint.text, options: options) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        return matches.compactMap { Range($0.range, in: text) }

    case .wholeWord:
        let escaped = NSRegularExpression.escapedPattern(for: hint.text)
        let pattern = "\\b\(escaped)\\b"
        var options: NSRegularExpression.Options = []
        if !hint.caseSensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        return matches.compactMap { Range($0.range, in: text) }

    case .wholeFilename:
        if hint.caseSensitive {
            return text == hint.text ? [text.startIndex..<text.endIndex] : []
        } else {
            return text.lowercased() == hint.text.lowercased()
                ? [text.startIndex..<text.endIndex] : []
        }
    }
}

/// Compute merged highlight ranges from multiple hints.
func computeHighlightRanges(in text: String, hints: [HighlightHint]) -> [Range<String.Index>] {
    guard !hints.isEmpty else { return [] }
    var allRanges: [Range<String.Index>] = []
    for hint in hints {
        allRanges.append(contentsOf: computeRangesForHint(in: text, hint: hint))
    }
    return mergeRanges(allRanges, in: text)
}

/// Merge overlapping/adjacent ranges, sorted by start position.
private func mergeRanges(_ ranges: [Range<String.Index>], in text: String) -> [Range<String.Index>] {
    guard !ranges.isEmpty else { return [] }
    let sorted = ranges.sorted { text.distance(from: text.startIndex, to: $0.lowerBound)
                                < text.distance(from: text.startIndex, to: $1.lowerBound) }
    var merged: [Range<String.Index>] = [sorted[0]]
    for range in sorted.dropFirst() {
        let last = merged[merged.count - 1]
        if range.lowerBound <= last.upperBound {
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
        } else {
            merged.append(range)
        }
    }
    return merged
}

/// Hint-based highlight: applies all matching hints to render highlighted Text.
func highlightMatches(in text: String, hints: [HighlightHint],
                      font: Font, color: Color,
                      highlightColor: Color = .accentColor) -> Text {
    let ranges = computeHighlightRanges(in: text, hints: hints)
    return buildHighlightedText(text: text, ranges: ranges, font: font,
                                color: color, highlightColor: highlightColor)
}

/// Hint-based cross-boundary highlight with field-aware dispatching.
/// NAME hints only highlight in name, PATH hints only in path,
/// ANY hints highlight across path+"/"+name boundary when text contains "/".
func highlightCrossMatches(path: String, name: String, hints: [HighlightHint],
                           nameFont: Font, nameColor: Color,
                           pathFont: Font, pathColor: Color,
                           highlightColor: Color = .accentColor) -> (nameText: Text, pathText: Text) {
    guard !hints.isEmpty else {
        return (Text(name).font(nameFont).foregroundColor(nameColor),
                Text(path).font(pathFont).foregroundColor(pathColor))
    }

    var nameRanges: [Range<String.Index>] = []
    var pathRanges: [Range<String.Index>] = []

    for hint in hints {
        switch hint.field {
        case .name:
            nameRanges.append(contentsOf: computeRangesForHint(in: name, hint: hint))
        case .path:
            pathRanges.append(contentsOf: computeRangesForHint(in: path, hint: hint))
        case .any:
            if hint.matchMode == .substring && hint.text.contains("/") {
                let fullPath = path + "/" + name
                let fullRanges = computeRangesForHint(in: fullPath, hint: hint)
                let (pRanges, nRanges) = mapFullPathRanges(fullRanges,
                    fullPath: fullPath, path: path, name: name)
                pathRanges.append(contentsOf: pRanges)
                nameRanges.append(contentsOf: nRanges)
            } else {
                nameRanges.append(contentsOf: computeRangesForHint(in: name, hint: hint))
                pathRanges.append(contentsOf: computeRangesForHint(in: path, hint: hint))
            }
        }
    }

    nameRanges = mergeRanges(nameRanges, in: name)
    pathRanges = mergeRanges(pathRanges, in: path)

    let nameText = buildHighlightedText(text: name, ranges: nameRanges,
                                        font: nameFont, color: nameColor,
                                        highlightColor: highlightColor)
    let pathText = buildHighlightedText(text: path, ranges: pathRanges,
                                        font: pathFont, color: pathColor,
                                        highlightColor: highlightColor)
    return (nameText, pathText)
}

/// Map ranges from fullPath (path+"/"+name) back to individual path and name ranges.
/// Indices from `fullPath` are converted through character offsets before being
/// rebuilt on `path` / `name`, since String.Index values are not interchangeable
/// between different string instances.
private func mapFullPathRanges(_ fullRanges: [Range<String.Index>],
                               fullPath: String, path: String,
                               name: String) -> (pathRanges: [Range<String.Index>],
                                                 nameRanges: [Range<String.Index>]) {
    let pathLength = path.count
    let nameStartOffset = pathLength + 1 // skip the "/" separator

    var pathRanges: [Range<String.Index>] = []
    var nameRanges: [Range<String.Index>] = []

    for range in fullRanges {
        let startOffset = fullPath.distance(from: fullPath.startIndex, to: range.lowerBound)
        let endOffset = fullPath.distance(from: fullPath.startIndex, to: range.upperBound)

        if startOffset < pathLength {
            let pEnd = min(endOffset, pathLength)
            let pStart = path.index(path.startIndex, offsetBy: startOffset)
            let pEndIndex = path.index(path.startIndex, offsetBy: pEnd)
            pathRanges.append(pStart..<pEndIndex)
        }

        if endOffset > nameStartOffset {
            let nStart = max(startOffset, nameStartOffset) - nameStartOffset
            let nEnd = min(endOffset - nameStartOffset, name.count)
            if nStart < nEnd {
                let nStartIndex = name.index(name.startIndex, offsetBy: nStart)
                let nEndIndex = name.index(name.startIndex, offsetBy: nEnd)
                nameRanges.append(nStartIndex..<nEndIndex)
            }
        }
    }
    return (pathRanges, nameRanges)
}
