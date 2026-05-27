import Foundation

public enum TerminalCopyCleaner {
    public static func cleanedSelectionText(for text: String) -> String? {
        cleanedSelectionTextForCopy(text)
    }

    /// Overall selection-level safety gate: returns true when the selection
    /// looks like code, structured text, logs, diffs, or command output.
    /// This prevents smart line-merging from damaging structured content.
    private static func selectionIsStructuredOrCode(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonEmptyLines = rawLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonEmptyLines.count >= 2 else { return false }
        if selectionLooksLikeSingleSoftWrappedPath(nonEmptyLines) {
            return false
        }

        var structuredScore = 0
        var inFence = false
        var fenceLines = 0
        var tableLines = 0

        for line in nonEmptyLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inFence.toggle()
                structuredScore += 2
                continue
            }

            if inFence {
                fenceLines += 1
                structuredScore += 2
                continue
            }

            // Stack trace patterns (e.g., "  at com.Example.method(File.swift:42)")
            if matchesStackTracePattern(trimmed) { structuredScore += 2; continue }
            // Diff hunks
            if startsWithDiffMarker(trimmed) { structuredScore += 2; continue }
            // Markdown or ASCII table rows
            if trimmed.hasPrefix("|") { tableLines += 1; structuredScore += 1; continue }
            // JSON/YAML key-value lines
            if matchesKeyValuePattern(trimmed) { structuredScore += 1; continue }
            // Log level / timestamp patterns
            if matchesLogPattern(trimmed) { structuredScore += 2; continue }
            // Command/shell/REPL prompts
            if startsWithPromptMarker(trimmed) { structuredScore += 1; continue }
            // Path-like lines
            if startsWithPathPattern(trimmed) { structuredScore += 1; continue }

            // Indented lines that contain code symbols
            if line.first?.isWhitespace == true && containsCodeSymbols(trimmed) {
                structuredScore += 1
                continue
            }

            // Lines dominated by punctuation / brackets (JSON, code)
            if hasHighSymbolDensity(trimmed) { structuredScore += 1; continue }
        }

        // If a significant portion of the selection is fenced code
        if fenceLines >= 3 && Double(fenceLines) / Double(nonEmptyLines.count) > 0.4 {
            return true
        }

        // If table rows dominate the selection
        if tableLines >= 2 && Double(tableLines) / Double(nonEmptyLines.count) > 0.3 {
            return true
        }

        let totalLines = nonEmptyLines.count
        let ratio = Double(structuredScore) / Double(totalLines * 2) // max score per line is 2
        return ratio > 0.35
    }

    private static func cleanedSelectionTextForCopy(_ text: String) -> String? {
        // Selection-level safety gate: bail out to raw for code/structured text
        guard !selectionIsStructuredOrCode(text) else { return nil }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        var mergedLines: [String] = []
        mergedLines.reserveCapacity(lines.count)
        var inFencedBlock = false
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track fenced code block state
            if trimmed.hasPrefix("```") {
                inFencedBlock.toggle()
                mergedLines.append(line)
                continue
            }

            // Inside a fenced code block — never merge
            if inFencedBlock {
                mergedLines.append(line)
                continue
            }

            // Track table state
            if trimmed.hasPrefix("|") {
                // Table separator row: |---| or |:---| etc.
                if trimmed.range(of: #"^\|[\s\-:]+\|"#, options: .regularExpression) != nil {
                    inTable = true
                }
                if inTable {
                    mergedLines.append(line)
                    continue
                }
                // First table row; enter table mode
                if trimmed.range(of: #"^\|\s*[^|]+\s*\|"#, options: .regularExpression) != nil {
                    inTable = true
                    mergedLines.append(line)
                    continue
                }
            }
            if inTable && trimmed.isEmpty {
                inTable = false
                mergedLines.append(line)
                continue
            }
            if inTable {
                mergedLines.append(line)
                continue
            }

            // Indented code / logs / prompts / stack traces: don't merge
            if line.first?.isWhitespace == true && !trimmed.isEmpty {
                if containsCodeSymbols(trimmed) || matchesLogPattern(trimmed) ||
                   matchesStackTracePattern(trimmed) || startsWithDiffMarker(trimmed) ||
                   matchesKeyValuePattern(trimmed) || startsWithPromptMarker(trimmed) {
                    mergedLines.append(line)
                    continue
                }
            }

            // Try merge
            if let previous = mergedLines.last,
               shouldMergeSoftWrappedLine(previous: previous, next: line) {
                mergedLines[mergedLines.count - 1] = joinSoftWrappedLines(previous: previous, next: line)
            } else {
                mergedLines.append(line)
            }
        }

        let cleaned = mergedLines.joined(separator: "\n")
        let pathCleaned = cleanPathWrapPadding(in: cleaned)
        let proseCleaned = cleanProseWrapPadding(in: pathCleaned)
        guard !proseCleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return proseCleaned
    }

    private static func shouldMergeSoftWrappedLine(previous: String, next: String) -> Bool {
        let previousTrimmed = previous.trimmingCharacters(in: .whitespaces)
        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
        guard !previousTrimmed.isEmpty, !nextTrimmed.isEmpty else { return false }

        if shouldMergePathContinuation(previous: previousTrimmed, next: nextTrimmed) {
            return true
        }

        // Next line starts with whitespace = intentional indentation, don't merge.
        // Path continuations are handled above with a trimmed next line.
        guard next.first?.isWhitespace != true else { return false }

        // Neither line should start a structured block
        guard !startsNewStructuredBlock(previousTrimmed) else { return false }
        guard !startsNewStructuredBlock(nextTrimmed) else { return false }

        // Hard boundary: previous line ends a sentence/statement
        guard !endsWithHardBoundary(previousTrimmed) else { return false }

        // Log, stack trace, diff, prompt, key-value: don't merge either side
        if matchesLogPattern(previousTrimmed) || matchesLogPattern(nextTrimmed) { return false }
        if matchesStackTracePattern(previousTrimmed) || matchesStackTracePattern(nextTrimmed) { return false }
        if startsWithDiffMarker(previousTrimmed) || startsWithDiffMarker(nextTrimmed) { return false }
        if startsWithPromptMarker(previousTrimmed) || startsWithPromptMarker(nextTrimmed) { return false }
        if matchesKeyValuePattern(previousTrimmed) || matchesKeyValuePattern(nextTrimmed) { return false }

        let nextStartsLowercaseASCII = nextTrimmed.unicodeScalars.first.map(isLowercaseASCII) ?? false
        let nextStartsCJK = nextTrimmed.unicodeScalars.first.map(isCJKScalar) ?? false
        let previousContainsCJK = containsCJK(previousTrimmed)
        let nextContainsCJK = containsCJK(nextTrimmed)

        // CJK prose: merge if both contain CJK and previous looks terminal-wrapped
        if nextStartsCJK || (previousContainsCJK && nextContainsCJK) {
            return previousLineLooksTerminalWrapped(previousTrimmed)
        }

        // English prose: only merge if next starts lowercase AND previous looks wrapped
        guard nextStartsLowercaseASCII else { return false }
        return previousLineLooksTerminalWrapped(previousTrimmed)
    }

    /// Returns true if a line looks like it was wrapped by a terminal at ~width boundary,
    /// rather than being an intentional short line (prompt output, code, log, etc.).
    /// Requires the line to be at least 40 chars OR end mid-word for CJK.
    static func previousLineLooksTerminalWrapped(_ line: String) -> Bool {
        let count = line.count
        // Short lines (under 20 chars) are almost never soft wraps; they're intentional newlines
        if count < 20 { return false }
        // Full-ish lines (>= 40 chars) that don't end in sentence-ending punctuation are likely wraps
        if count >= 40 {
            let last = line.unicodeScalars.last
            let sentenceEnders: Set<UInt32> = [
                0x002E, // .
                0x0021, // !
                0x003F, // ?
                0x3002, // 。
                0xFF01, // ！
                0xFF1F, // ？
                0x003A, // :
                0xFF1A, // ：
                0x003B, // ;
                0xFF1B, // ；
            ]
            if let last = last {
                // Comma alone at <60 chars often means the line isn't fully wrapped yet
                if last.value == 0x002C || last.value == 0xFF0C { // , or ，
                    return count >= 60
                }
                if sentenceEnders.contains(last.value) {
                    return false
                }
            }
            return true
        }
        // 20-39 chars: only merge for unambiguous continuations (start mid-sentence)
        return false  // 20-39 chars: shouldMergeSoftWrappedLine already handles next-line start features; short lines should not default-merge
    }

}
