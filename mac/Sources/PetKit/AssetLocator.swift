import Foundation

/// Finds the ignored `Assets/` folder holding the local game rips.
/// Order: `NINTENDOGS_ASSETS` env, the app bundle's `Resources/Assets`,
/// then `mac/Assets` relative to this source tree (for `swift run` / `swift test`).
public enum AssetLocator {
    public static func assetsRoot() -> URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["NINTENDOGS_ASSETS"], fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Assets", isDirectory: true),
           fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets", isDirectory: true)
        return fm.fileExists(atPath: source.path) ? source : nil
    }

    /// Coat B is the black-and-tan Shiba variant from the local Nintendogs rip.
    public static func shibaModel(coat: String = "b") -> URL? {
        assetsRoot()?.appendingPathComponent("shiba/aSib_\(coat).nsbmd/Sib_\(coat).dae")
    }
}
