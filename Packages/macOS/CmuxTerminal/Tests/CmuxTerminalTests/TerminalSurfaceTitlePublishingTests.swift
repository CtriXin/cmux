import Testing
@testable import CmuxTerminal

@Suite struct TerminalSurfaceTitlePublishingTests {
    @Test func stableTerminalNotificationTitleStripsSpinnerPrefix() {
        #expect(TerminalSurface.stableTerminalNotificationTitle("⠋ Building") == "Building")
        #expect(TerminalSurface.stableTerminalNotificationTitle("⠙  Running tests") == "Running tests")
        #expect(TerminalSurface.stableTerminalNotificationTitle("Plain title") == "Plain title")
        #expect(TerminalSurface.stableTerminalNotificationTitle("⠋NoSpace") == "⠋NoSpace")
    }
}
