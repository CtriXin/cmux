import Foundation

public extension TerminalSurface {
    /// Returns a de-spun terminal title only when it changed since the last publish.
    ///
    /// Ghostty can emit animated braille spinner titles for agent CLIs. Publishing
    /// each frame would thrash workspace and window titles, so this method strips
    /// the known spinner prefix, rejects empty titles, and suppresses duplicates.
    ///
    /// - Parameter title: The raw title emitted by Ghostty.
    /// - Returns: The stable title to publish, or `nil` when no update is needed.
    func publishableTerminalTitle(_ title: String) -> String? {
        let stableTitle = Self.stableTerminalNotificationTitle(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stableTitle.isEmpty else { return nil }
        guard lastPublishedTerminalTitle != stableTitle else { return nil }
        lastPublishedTerminalTitle = stableTitle
        return stableTitle
    }

    internal static func stableTerminalNotificationTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              terminalTitleSpinnerCharacters.contains(first) else {
            return title
        }

        let afterSpinner = trimmed.index(after: trimmed.startIndex)
        guard afterSpinner < trimmed.endIndex,
              trimmed[afterSpinner].isWhitespace else {
            return title
        }

        guard let remainderStart = trimmed[afterSpinner...].firstIndex(where: { !$0.isWhitespace }) else {
            return title
        }
        return String(trimmed[remainderStart...])
    }

    private static var terminalTitleSpinnerCharacters: Set<Character> {
        Set("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    }
}
