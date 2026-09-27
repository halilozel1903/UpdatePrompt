import Foundation

/// Scenes used by CI to capture the README screenshots.
/// Launch with `-screenshot <scene>`; normal launches are unaffected.
enum ScreenshotScene: String {
    case optional
    case forced

    static var current: ScreenshotScene? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return ScreenshotScene(rawValue: arguments[index + 1])
    }

    /// Both scenes come from the in-memory fake source, no network involved.
    var scenario: FakeUpdateSource.Scenario {
        switch self {
        case .optional: .optional
        case .forced: .forced
        }
    }
}
