import Foundation

extension TerminalCopyCleaner {
    // MARK: - Existing helpers (preserved)
    static func selectionLooksLikeSingleSoftWrappedPath(_ lines: [String]) -> Bool {
        guard var merged = lines.first?.trimmingCharacters(in: .whitespaces), !merged.isEmpty else {
            return false
        }

        var mergedAtLeastOneLine = false
        for line in lines.dropFirst() {
            let next = line.trimmingCharacters(in: .whitespaces)
            guard shouldMergePathContinuation(previous: merged, next: next) else {
                return false
            }
            merged = joinSoftWrappedLines(previous: merged, next: next)
            mergedAtLeastOneLine = true
        }

        return mergedAtLeastOneLine
    }

    static func shouldMergePathContinuation(previous: String, next: String) -> Bool {
        let previousTrimmed = previous.trimmingCharacters(in: .whitespaces)
        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
        guard !previousTrimmed.isEmpty, !nextTrimmed.isEmpty else { return false }
        guard isPathStart(previousTrimmed) || looksLikePathFragment(previousTrimmed) else { return false }
        guard previousPathLineLooksTerminalWrapped(previousTrimmed) else { return false }
        guard !isPathStart(nextTrimmed) else { return false }
        guard !startsWithPromptMarker(nextTrimmed) else { return false }
        guard !startsWithDiffMarker(nextTrimmed) else { return false }
        guard !matchesLogPattern(nextTrimmed) else { return false }
        guard !matchesStackTracePattern(nextTrimmed) else { return false }
        guard !matchesKeyValuePattern(nextTrimmed) else { return false }
        return looksLikePathContinuation(nextTrimmed)
    }

    static func joinSoftWrappedLines(previous: String, next: String) -> String {
        let previousTrimmed = previous.trimmingCharacters(in: .whitespaces)
        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
        guard !previousTrimmed.isEmpty else { return nextTrimmed }
        guard !nextTrimmed.isEmpty else { return previousTrimmed }

        let separator = joinSeparatorForCopy(previous: previousTrimmed, next: nextTrimmed)
        return previousTrimmed + separator + nextTrimmed
    }

    static func joinSeparatorForCopy(previous: String, next: String) -> String {
        if shouldMergePathContinuation(previous: previous, next: next) {
            return ""
        }

        let previousEndsCJK = previous.unicodeScalars.last.map(isCJKScalar) ?? false
        let nextStartsCJK = next.unicodeScalars.first.map(isCJKScalar) ?? false
        return (previousEndsCJK || nextStartsCJK) ? "" : " "
    }

    /// Normalizes terminal wrap padding within path segments (same-line, not cross-line).
    /// When Ghostty wraps a long path visually, raw selection may contain 2+ spaces
    /// where the wrap occurred (e.g. "/DerivedData/  cmux-..."). This removes such
    /// padding while preserving single-space path separators for real paths.
    static func cleanPathWrapPadding(in text: String) -> String {
        guard needsPathWrapPaddingCleaning(text) else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var idx = text.startIndex

        while idx < text.endIndex {
            let char = text[idx]
            if char == "/" {
                result.append("/")
                idx = text.index(after: idx)

                var whitespaceCount = 0
                var scanIdx = idx
                while scanIdx < text.endIndex, text[scanIdx] == " " || text[scanIdx] == "\t" {
                    whitespaceCount += 1
                    scanIdx = text.index(after: scanIdx)
                }

                if whitespaceCount >= 2, scanIdx < text.endIndex,
                   isPathSegmentStartChar(text[scanIdx]) {
                    idx = scanIdx
                    continue
                }

                while idx < scanIdx {
                    result.append(text[idx])
                    idx = text.index(after: idx)
                }
            } else {
                result.append(char)
                idx = text.index(after: idx)

                var whitespaceCount = 0
                var scanIdx = idx
                while scanIdx < text.endIndex, text[scanIdx] == " " || text[scanIdx] == "\t" {
                    whitespaceCount += 1
                    scanIdx = text.index(after: scanIdx)
                }

                if whitespaceCount >= 2,
                   scanIdx < text.endIndex,
                   text[scanIdx] == "/",
                   result.unicodeScalars.last.map(isPathSafeScalar) == true {
                    idx = scanIdx
                }
            }
        }

        return result
    }

    static func needsPathWrapPaddingCleaning(_ text: String) -> Bool {
        if text.hasPrefix("/") { return true }
        if text.hasPrefix("~/") { return true }
        if text.hasPrefix("./") { return true }
        if text.hasPrefix("../") { return true }
        if text.contains("/  ") { return true }
        if text.contains("  /") { return true }
        return false
    }

    static func isPathSegmentStartChar(_ char: Character) -> Bool {
        if char.isLetter || char.isNumber { return true }
        switch char {
        case ".", "_", "-": return true
        default: return false
        }
    }

    /// Normalizes same-line padding inserted at terminal soft-wrap points in prose.
    /// CJK-to-CJK joins without a space; Latin/number boundaries collapse to one space.
    static func cleanProseWrapPadding(in text: String) -> String {
        guard text.contains("  ") || text.contains("\t") else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var idx = text.startIndex

        while idx < text.endIndex {
            let char = text[idx]
            guard char == " " || char == "\t" else {
                result.append(char)
                idx = text.index(after: idx)
                continue
            }

            var whitespaceCount = 0
            var scanIdx = idx
            while scanIdx < text.endIndex, text[scanIdx] == " " || text[scanIdx] == "\t" {
                whitespaceCount += 1
                scanIdx = text.index(after: scanIdx)
            }

            if whitespaceCount >= 2,
               let previous = result.unicodeScalars.last,
               scanIdx < text.endIndex,
               let next = String(text[scanIdx]).unicodeScalars.first,
               shouldCollapseProseWrapPadding(previous: previous, next: next) {
                if shouldInsertSpaceWhenCollapsingWrap(previous: previous, next: next) {
                    result.append(" ")
                }
                idx = scanIdx
                continue
            }

            while idx < scanIdx {
                result.append(text[idx])
                idx = text.index(after: idx)
            }
        }

        return result
    }

    static func shouldCollapseProseWrapPadding(previous: UnicodeScalar, next: UnicodeScalar) -> Bool {
        if isCJKScalar(previous) || isCJKScalar(next) { return true }
        return isAlphaNumericASCII(previous) && isAlphaNumericASCII(next)
    }

    static func shouldInsertSpaceWhenCollapsingWrap(previous: UnicodeScalar, next: UnicodeScalar) -> Bool {
        if isCJKScalar(previous) && isCJKScalar(next) { return false }
        return true
    }

    static func isAlphaNumericASCII(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 48 && scalar.value <= 57)
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    static func startsNewStructuredBlock(_ line: String) -> Bool {
        // Code fence (markdown)
        if line.hasPrefix("```") { return true }

        // Horizontal rule
        if line.range(of: #"^[-*_]{3,}\s*$"#, options: .regularExpression) != nil {
            return true
        }

        let structuredPrefixes = [
            "- ", "* ", "+ ", "$ ", "> ", "%% ",  // bullets, prompt, quote, diff
            "/Users/", "~/", "./", "../",
            "{", "}", "[", "]", "<", "</"
        ]
        if structuredPrefixes.contains(where: { line.hasPrefix($0) }) {
            return true
        }

        // Numbered list or path line with "N. " (e.g., "1. ", "12. ")
        if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
            return true
        }

        // Markdown table row
        if line.hasPrefix("|") { return true }

        return false
    }

    static func endsWithHardBoundary(_ line: String) -> Bool {
        let hardBoundarySuffixes = ["!", "?", "。", "！", "？", ":", "：", ";", "；"]
        return hardBoundarySuffixes.contains(where: { line.hasSuffix($0) })
    }

    // MARK: - New structured-text detection helpers

    /// Detects stack trace lines like "  at com.app.Main.main(Main.java:10)"
    static func matchesStackTracePattern(_ line: String) -> Bool {
        // Pattern: "at " followed by package.class.method(file:line)
        if line.range(of: #"^\s*at\s+\S+\("#, options: .regularExpression) != nil { return true }
        // "Caused by:" patterns
        if line.hasPrefix("Caused by:") { return true }
        // "... N more" frame count
        if line.range(of: #"^\s*\.\.\.\s*\d+\s+more\s*$"#, options: .regularExpression) != nil { return true }
        // File:line patterns like (File.swift:42) or (file.ts:100)
        if line.range(of: #"\([\w./_-]+\.(swift|java|py|ts|js|rs|go|kt|cpp|c|h|m|mm):\d+\)"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Detects diff/patch markers: +++, ---, @@ hunk headers
    static func startsWithDiffMarker(_ line: String) -> Bool {
        if line.hasPrefix("+++ ") || line.hasPrefix("--- ") { return true }
        if line.hasPrefix("@@") && line.contains("@@") { return true }
        if line.hasPrefix("diff ") { return true }
        if line.hasPrefix("index ") { return true }
        return false
    }

    /// Detects log patterns like "[ERROR]", "[WARN]", "[2024-01-01"
    static func matchesLogPattern(_ line: String) -> Bool {
        if line.range(of: #"^\[(INFO|WARN|ERROR|DEBUG|TRACE|FATAL|NOTICE|CRITICAL)\s*\]"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // Timestamp-prefixed log lines
        if line.range(of: #"^\d{2,4}[-/]\d{2}[-/]\d{2}[T ]\d{2}:\d{2}"#, options: .regularExpression) != nil { return true }
        // Short timestamp like "10:42:33.123"
        if line.range(of: #"^\d{2}:\d{2}:\d{2}\."#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Detects key-value or JSON/YAML property lines
    static func matchesKeyValuePattern(_ line: String) -> Bool {
        // JSON key: "key": value
        if line.range(of: #"^\s*".*"\s*:"#, options: .regularExpression) != nil { return true }
        // YAML key: value (colon not preceded by https/ftp)
        if line.range(of: #"^\s*[A-Za-z_][\w.]*\s*:"#, options: .regularExpression) != nil {
            if line.contains("://") || line.contains("ftp:") { return false }
            return true
        }
        // INI/config: key=value
        if line.range(of: #"^\s*[A-Za-z_][\w.]*\s*="#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Detects command/shell/REPL prompt markers
    static func startsWithPromptMarker(_ line: String) -> Bool {
        let promptPrefixes = ["$ ", "# ", ">>> ", "... ", "% ", ">> "]
        return promptPrefixes.contains(where: { line.hasPrefix($0) })
    }

    static func isPathStart(_ line: String) -> Bool {
        if line == "/" { return true }
        if line.hasPrefix("/") {
            return line.dropFirst().first?.isWhitespace != true
        }
        if line.hasPrefix("~/") || line.hasPrefix("./") || line.hasPrefix("../") {
            return true
        }
        if line.hasPrefix("\\") {
            return line.dropFirst(2).first?.isWhitespace != true
        }
        if line.range(of: #"^[A-Za-z]:(\\|/)"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func looksLikePathFragment(_ line: String) -> Bool {
        guard !line.isEmpty, !line.contains(where: \.isWhitespace) else { return false }
        guard line.contains("/") || line.hasSuffix("/") else { return false }
        return line.unicodeScalars.allSatisfy(isPathSafeScalar)
    }

    static func looksLikePathContinuation(_ line: String) -> Bool {
        // Guards: non-empty, no whitespace, all scalars path-safe
        guard !line.isEmpty, !line.contains(where: \.isWhitespace) else { return false }
        guard line.unicodeScalars.allSatisfy(isPathSafeScalar) else { return false }

        let count = line.count

        // Slash or backslash -> strong path signal
        if line.contains("/") || line.contains("\\") { return true }

        // Path punctuation / signal characters -> strong signal
        let pathSignals: Set<Character> = [".", "~", "_", "-", "@", "%", "+", "=", ":"]
        if line.contains(where: { pathSignals.contains($0) }) { return true }

        // Any digit + length >= 2 -> likely versioned/numbered path segment
        if line.contains(where: { $0.isNumber }) && count >= 2 { return true }

        // Longer plausible path tokens: must be >= 8 chars and not all letters
        // (all-letter tokens like "Something" without path signal are too risky)
        if count >= 8 && !line.allSatisfy({ $0.isLetter }) { return true }

        // Everything else (short all-letter words like "to", "be", "in", "of"): false
        return false
    }

    static func previousPathLineLooksTerminalWrapped(_ line: String) -> Bool {
        if previousLineLooksTerminalWrapped(line) {
            return true
        }
        return line.count >= 16 && looksLikePathFragment(line)
    }

    static func isPathSafeScalar(_ scalar: UnicodeScalar) -> Bool {
        let pathSafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._@%+=:/-\\~")
        return pathSafe.contains(scalar)
    }

    /// Detects file paths at line start
    static func startsWithPathPattern(_ line: String) -> Bool {
        isPathStart(line)
    }

    /// Returns true if the line contains code-like symbols (parens, braces, semicolons, operators)
    static func containsCodeSymbols(_ line: String) -> Bool {
        let codeChars = CharacterSet(charactersIn: "(){}[]=;:<>")
        let count = line.unicodeScalars.filter { codeChars.contains($0) }.count
        return count >= 3
    }

    /// Returns true if the line has high density of punctuation/symbols (JSON, code, etc.)
    static func hasHighSymbolDensity(_ line: String) -> Bool {
        guard line.count > 8 else { return false }
        let symbols = CharacterSet(charactersIn: "{}[]()\"':;,.<>=!@#$%^&*+-/\\|")
        let symbolCount = line.unicodeScalars.filter { symbols.contains($0) }.count
        return Double(symbolCount) / Double(line.count) > 0.25
    }

    // MARK: - Character classification helpers (preserved)

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJKScalar)
    }

    static func isLowercaseASCII(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 97 && scalar.value <= 122
    }

    static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x2CEB0...0x2EBEF,
             0x3040...0x309F,
             0x30A0...0x30FF,
             0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }


}
