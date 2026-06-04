import Foundation

enum UpdateBuildKind {
    static func isDebugLikeBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifier == "com.cmuxterm.app.debug"
            || bundleIdentifier.hasPrefix("com.cmuxterm.app.debug.")
    }

    static func isStagingBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifier == "com.cmuxterm.app.staging"
            || bundleIdentifier.hasPrefix("com.cmuxterm.app.staging.")
    }
}
