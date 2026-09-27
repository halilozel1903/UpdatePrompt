import Foundation

/// Reads the newest version from the public App Store lookup API
/// (`https://itunes.apple.com/lookup`).
///
/// ```swift
/// let checker = UpdateChecker(source: AppStoreUpdateSource())
/// ```
///
/// The App Store only knows the newest version, so updates found this way are
/// always optional. Combine it with a ``RemoteJSONUpdateSource`` to force updates.
public struct AppStoreUpdateSource: UpdateSource {
    /// The bundle identifier to look up. `nil` uses `Bundle.main`.
    public var bundleID: String?
    /// Two-letter App Store country code such as `"us"` or `"tr"`. `nil` uses
    /// the region of the current locale. Apps that are not sold in the US must
    /// pass the right storefront, or the lookup finds nothing.
    public var country: String?

    private let transport: HTTPTransport

    public init(bundleID: String? = nil, country: String? = nil, session: URLSession = .shared) {
        self.init(bundleID: bundleID, country: country, transport: .urlSession(session))
    }

    public init(bundleID: String? = nil, country: String? = nil, transport: HTTPTransport) {
        self.bundleID = bundleID
        self.country = country
        self.transport = transport
    }

    /// The lookup URL that will be requested.
    public func lookupURL() throws -> URL {
        guard let bundleID = bundleID ?? Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            throw UpdateSourceError.missingBundleIdentifier
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        var items = [URLQueryItem(name: "bundleId", value: bundleID)]
        if let country = (country ?? Locale.current.region?.identifier)?.lowercased(), !country.isEmpty {
            items.append(URLQueryItem(name: "country", value: country))
        }
        components.queryItems = items
        guard let url = components.url else { throw UpdateSourceError.invalidResponse }
        return url
    }

    public func latestUpdate() async throws -> UpdateInfo {
        let data = try await transport.data(from: try lookupURL())
        return try Self.decode(data)
    }

    /// Parses a lookup API response.
    public static func decode(_ data: Data) throws -> UpdateInfo {
        let response: LookupResponse
        do {
            response = try JSONDecoder().decode(LookupResponse.self, from: data)
        } catch {
            throw UpdateSourceError.invalidResponse
        }
        guard let app = response.results.first else {
            throw UpdateSourceError.appNotFound
        }
        guard let version = AppVersion(app.version) else {
            throw UpdateSourceError.invalidVersion(app.version)
        }
        let storeURL = app.trackViewUrl.flatMap(URL.init(string:))
            ?? app.trackId.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") }
        let notes = app.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateInfo(
            version: version,
            releaseNotes: notes?.isEmpty == false ? notes : nil,
            releaseDate: app.currentVersionReleaseDate.flatMap { try? Date($0, strategy: .iso8601) },
            minimumOSVersion: app.minimumOsVersion.flatMap { AppVersion($0) },
            storeURL: storeURL
        )
    }

    private struct LookupResponse: Decodable {
        let results: [App]
    }

    private struct App: Decodable {
        let version: String
        let releaseNotes: String?
        let minimumOsVersion: String?
        let trackViewUrl: String?
        let trackId: Int?
        let currentVersionReleaseDate: String?
    }
}
