import Foundation
import UpdatePrompt

/// An in-memory `UpdateSource` for the demo and the screenshots: no network.
/// In your app use `AppStoreUpdateSource()`, `RemoteJSONUpdateSource(url:)`
/// or both via `CombinedUpdateSource`.
final class FakeUpdateSource: UpdateSource, @unchecked Sendable {
    enum Scenario: String, CaseIterable, Identifiable {
        case optional = "Optional update"
        case forced = "Forced update"
        case upToDate = "Up to date"
        case unsupportedOS = "Needs newer iOS"

        var id: Self { self }
    }

    static let installedVersion: AppVersion = "2.3.1"

    private let lock = NSLock()
    private var storedScenario: Scenario

    init(scenario: Scenario) {
        storedScenario = scenario
    }

    var scenario: Scenario {
        get { lock.withLock { storedScenario } }
        set { lock.withLock { storedScenario = newValue } }
    }

    func latestUpdate() async throws -> UpdateInfo {
        // Pretend to talk to a server.
        try await Task.sleep(for: .milliseconds(700))
        return Self.update(for: scenario)
    }

    static func update(for scenario: Scenario) -> UpdateInfo {
        let storeURL = URL(string: "https://apps.apple.com/app/id1234567890")
        let released = Date(timeIntervalSince1970: 1_789_887_600)
        switch scenario {
        case .optional:
            return UpdateInfo(
                version: "2.4.0",
                releaseNotes: """
                • Home Screen widgets for your favorite lists
                • Sync is up to twice as fast
                • New Liquid Glass design on iOS 26
                • Bug fixes and performance improvements
                """,
                releaseDate: released,
                minimumOSVersion: "17.0",
                storeURL: storeURL
            )
        case .forced:
            return UpdateInfo(
                version: "3.0.0",
                minimumRequiredVersion: "3.0.0",
                releaseNotes: """
                • Important security fix for account sign-in
                • Required for the new sync service
                """,
                releaseDate: released,
                minimumOSVersion: "17.0",
                storeURL: storeURL
            )
        case .upToDate:
            return UpdateInfo(version: installedVersion, storeURL: storeURL)
        case .unsupportedOS:
            return UpdateInfo(version: "4.0.0", minimumOSVersion: "99.0", storeURL: storeURL)
        }
    }
}
