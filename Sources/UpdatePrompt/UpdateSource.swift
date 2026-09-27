import Foundation

/// Anything that can tell which version of the app is the newest.
///
/// The package ships with ``AppStoreUpdateSource``, ``RemoteJSONUpdateSource``
/// and ``CombinedUpdateSource``. Conform your own type to read from Firebase
/// Remote Config, your backend or a fixed value in tests and previews.
public protocol UpdateSource: Sendable {
    /// Fetches information about the newest version.
    func latestUpdate() async throws -> UpdateInfo
}

/// Errors thrown by the built-in sources.
public enum UpdateSourceError: Error, Sendable, Hashable {
    /// No bundle identifier was given and `Bundle.main` has none.
    case missingBundleIdentifier
    /// The App Store lookup returned no app for the bundle identifier and country.
    case appNotFound
    /// The server answered with a non-2xx HTTP status code.
    case httpStatus(Int)
    /// A version string in the response could not be parsed.
    case invalidVersion(String)
    /// The response was not in the expected format.
    case invalidResponse
    /// A ``CombinedUpdateSource`` has no sources.
    case noSources
}

/// Performs HTTP requests for the built-in sources.
///
/// Uses `URLSession` by default; tests inject a closure that returns fixture data.
public struct HTTPTransport: Sendable {
    public typealias Load = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let load: Load

    public init(_ load: @escaping Load) {
        self.load = load
    }

    /// A transport backed by `session`.
    public static func urlSession(_ session: URLSession) -> HTTPTransport {
        HTTPTransport { request in try await session.data(for: request) }
    }

    /// A transport backed by `URLSession.shared`.
    public static var shared: HTTPTransport { .urlSession(.shared) }

    /// Loads `url` and returns the body, throwing for non-2xx status codes.
    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateSourceError.httpStatus(http.statusCode)
        }
        return data
    }
}

/// Merges several sources into one.
///
/// The typical setup reads the newest version and release notes from the App
/// Store and the minimum supported version from your own JSON file:
///
/// ```swift
/// let source = CombinedUpdateSource(
///     AppStoreUpdateSource(),
///     RemoteJSONUpdateSource(url: URL(string: "https://example.com/app-version.json")!)
/// )
/// ```
///
/// The newest version wins (the first source on a tie). Missing fields are
/// filled from the other sources, and the highest ``UpdateInfo/minimumRequiredVersion``
/// is used. Sources that fail are ignored; the call only throws when all of them fail.
public struct CombinedUpdateSource: UpdateSource {
    public let sources: [any UpdateSource]

    public init(_ sources: [any UpdateSource]) {
        self.sources = sources
    }

    public init(_ sources: any UpdateSource...) {
        self.init(sources)
    }

    public func latestUpdate() async throws -> UpdateInfo {
        var results: [UpdateInfo] = []
        var firstError: (any Error)?
        for source in sources {
            do {
                results.append(try await source.latestUpdate())
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        try Task.checkCancellation()
        guard !results.isEmpty else {
            throw firstError ?? UpdateSourceError.noSources
        }
        return Self.merge(results)
    }

    /// Merges results in source order. Exposed for testing.
    static func merge(_ results: [UpdateInfo]) -> UpdateInfo {
        var merged = results[0]
        for info in results.dropFirst() where info.version > merged.version {
            merged = info
        }
        merged.minimumRequiredVersion = results.compactMap(\.minimumRequiredVersion).max()
        merged.releaseNotes = merged.releaseNotes ?? results.lazy.compactMap(\.releaseNotes).first
        merged.releaseDate = merged.releaseDate ?? results.lazy.compactMap(\.releaseDate).first
        merged.minimumOSVersion = merged.minimumOSVersion ?? results.lazy.compactMap(\.minimumOSVersion).first
        merged.storeURL = merged.storeURL ?? results.lazy.compactMap(\.storeURL).first
        return merged
    }
}
