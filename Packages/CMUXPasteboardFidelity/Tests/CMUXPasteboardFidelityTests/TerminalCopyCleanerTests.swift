import XCTest
@testable import CMUXPasteboardFidelity

final class TerminalCopyCleanerTests: XCTestCase {
    func testCleanedSelectionMergesSoftWrappedProse() {
        let source = "This terminal selection is long enough to look like it wrapped in the middle of a\nsentence that should continue as prose."

        XCTAssertEqual(
            TerminalCopyCleaner.cleanedSelectionText(for: source),
            "This terminal selection is long enough to look like it wrapped in the middle of a sentence that should continue as prose."
        )
    }

    func testCleanedSelectionMergesPathContinuationWithPathSignal() {
        let source = "/Users/example/Library/Developer/Xcode/DerivedData/cmux-pr4808/Build/Products/Debug\n/cmux DEV pr4808.app"

        XCTAssertEqual(
            TerminalCopyCleaner.cleanedSelectionText(for: source),
            "/Users/example/Library/Developer/Xcode/DerivedData/cmux-pr4808/Build/Products/Debug/cmux DEV pr4808.app"
        )
    }

    func testCleanedSelectionDoesNotMergePathWithShortProseToken() {
        let source = "/Users/example/Library/Developer\nto continue reading the note"

        XCTAssertEqual(TerminalCopyCleaner.cleanedSelectionText(for: source), source)
    }

    func testCleanedSelectionLeavesStructuredDiffRaw() {
        let source = "diff --git a/file.swift b/file.swift\n@@ -1,2 +1,2 @@\n- old\n+ new"

        XCTAssertNil(TerminalCopyCleaner.cleanedSelectionText(for: source))
    }
}
