import Foundation

/// Reads version rules from a JSON file you host, for example on your website,
/// a CDN or GitHub Pages. This is how you force users off old versions.
///
/// ```json
/// {
///   "latestVersion": "2.4.0",
///   "minimumVersion": "2.0.0",
///   "releaseNotes": "Faster sync and a brand-new widget.",
///   "minimumOSVersion": "17.0",
///   "updateURL": "https://apps.apple.com/app/id1234567890"
/// }
/// ```
///
/// Only `latestVersion` is required.
public struct RemoteJSONUpdateSource: UpdateSource {
    public let url: URL
    private let transport: HTTPTransport

    public init(url: URL, session: URLSession = .shared) {
        self.init(url: url, transport: .urlSession(session))
    }

    public init(url: URL, transport: HTTPTransport) {
        self.url = url
        self.transport = transport
    }

    public func latestUpdate() async throws -> UpdateInfo {
        try Self.decode(try await transport.data(from: url))
    }

    /// Parses a manifest.
    public static func decode(_ data: Data) throws -> UpdateInfo {
        let manifest: RemoteUpdateManifest
        do {
            manifest = try JSONDecoder().decode(RemoteUpdateManifest.self, from: data)
        } catch {
            throw UpdateSourceError.invalidResponse
        }
        return try manifest.updateInfo()
    }
}

/// The JSON format read by ``RemoteJSONUpdateSource``.
public struct RemoteUpdateManifest: Sendable, Hashable, Codable {
    public var latestVersion: String
    public var minimumVersion: String?
    public var releaseNotes: String?
    public var minimumOSVersion: String?
    public var updateURL: URL?

    public init(
        latestVersion: String,
        minimumVersion: String? = nil,
        releaseNotes: String? = nil,
        minimumOSVersion: String? = nil,
        updateURL: URL? = nil
    ) {
        self.latestVersion = latestVersion
        self.minimumVersion = minimumVersion
        self.releaseNotes = releaseNotes
        self.minimumOSVersion = minimumOSVersion
        self.updateURL = updateURL
    }

    public func updateInfo() throws -> UpdateInfo {
        func parse(_ string: String) throws -> AppVersion {
            guard let version = AppVersion(string) else { throw UpdateSourceError.invalidVersion(string) }
            return version
        }
        return UpdateInfo(
            version: try parse(latestVersion),
            minimumRequiredVersion: try minimumVersion.map(parse),
            releaseNotes: releaseNotes,
            minimumOSVersion: try minimumOSVersion.map(parse),
            storeURL: updateURL
        )
    }
}
