import Foundation
import Testing
@testable import UpdatePrompt

@Suite("AppStoreUpdateSource")
struct AppStoreUpdateSourceTests {
    @Test func buildsLookupURL() throws {
        let source = AppStoreUpdateSource(bundleID: "com.example.notes", country: "TR", transport: .stub(Data()))
        let url = try source.lookupURL()
        #expect(url.absoluteString == "https://itunes.apple.com/lookup?bundleId=com.example.notes&country=tr")
    }

    @Test func requestsLookupURLWithoutCache() async throws {
        let recorder = RequestRecorder()
        let source = AppStoreUpdateSource(
            bundleID: "com.example.notes",
            country: "us",
            transport: .stub(try Fixture.data("appstore-lookup"), recorder: recorder)
        )
        _ = try await source.latestUpdate()

        let request = try #require(recorder.requests.first)
        #expect(request.url?.absoluteString == "https://itunes.apple.com/lookup?bundleId=com.example.notes&country=us")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func parsesLookupResponse() async throws {
        let source = AppStoreUpdateSource(
            bundleID: "com.example.notes",
            country: "us",
            transport: .stub(try Fixture.data("appstore-lookup"))
        )
        let update = try await source.latestUpdate()

        #expect(update.version == "2.10.0")
        #expect(update.version > "2.9")
        #expect(update.releaseNotes == "• Home Screen widgets\n• Faster iCloud sync\n• Bug fixes and performance improvements")
        #expect(update.minimumOSVersion == "17.0")
        #expect(update.storeURL == URL(string: "https://apps.apple.com/us/app/sample-notes/id1234567890?uo=4"))
        #expect(update.releaseDate == Date(timeIntervalSince1970: 1_789_887_600))
        #expect(update.minimumRequiredVersion == nil)
    }

    @Test func fallsBackToTrackIDAndDropsBlankNotes() throws {
        let update = try AppStoreUpdateSource.decode(try Fixture.data("appstore-no-url"))
        #expect(update.version == "1.2")
        #expect(update.storeURL == URL(string: "https://apps.apple.com/app/id42"))
        #expect(update.releaseNotes == nil)
        #expect(update.releaseDate == nil)
    }

    @Test func emptyResultMeansAppNotFound() async throws {
        let source = AppStoreUpdateSource(bundleID: "com.example.unknown", transport: .stub(try Fixture.data("appstore-empty")))
        await #expect(throws: UpdateSourceError.appNotFound) {
            try await source.latestUpdate()
        }
    }

    @Test func httpErrorsAreReported() async throws {
        let source = AppStoreUpdateSource(bundleID: "com.example.notes", transport: .stub(Data(), status: 503))
        await #expect(throws: UpdateSourceError.httpStatus(503)) {
            try await source.latestUpdate()
        }
    }

    @Test func garbageIsAnInvalidResponse() {
        #expect(throws: UpdateSourceError.invalidResponse) {
            try AppStoreUpdateSource.decode(Data("<html>".utf8))
        }
    }

    @Test func networkErrorsPassThrough() async {
        let source = AppStoreUpdateSource(bundleID: "com.example.notes", transport: .failing(.notConnectedToInternet))
        await #expect(throws: URLError.self) {
            try await source.latestUpdate()
        }
    }
}

@Suite("RemoteJSONUpdateSource")
struct RemoteJSONUpdateSourceTests {
    let url = URL(string: "https://example.com/app-version.json")!

    @Test func parsesFullManifest() async throws {
        let source = RemoteJSONUpdateSource(url: url, transport: .stub(try Fixture.data("remote-manifest")))
        let update = try await source.latestUpdate()

        #expect(update.version == "3.1.0")
        #expect(update.minimumRequiredVersion == "3.0.0")
        #expect(update.releaseNotes == "A security fix everyone needs.")
        #expect(update.minimumOSVersion == "17.2")
        #expect(update.storeURL == URL(string: "https://apps.apple.com/app/id1234567890"))
    }

    @Test func onlyLatestVersionIsRequired() throws {
        let update = try RemoteJSONUpdateSource.decode(try Fixture.data("remote-manifest-minimal"))
        #expect(update == UpdateInfo(version: "1.4"))
    }

    @Test func invalidVersionIsReported() {
        #expect(throws: UpdateSourceError.invalidVersion("latest")) {
            try RemoteJSONUpdateSource.decode(try Fixture.data("remote-manifest-invalid"))
        }
    }

    @Test func missingLatestVersionIsInvalid() {
        #expect(throws: UpdateSourceError.invalidResponse) {
            try RemoteJSONUpdateSource.decode(Data(#"{"minimumVersion":"1.0"}"#.utf8))
        }
    }
}

@Suite("CombinedUpdateSource")
struct CombinedUpdateSourceTests {
    @Test func appStoreVersionWithRemoteMinimum() async throws {
        let appStore = AppStoreUpdateSource(bundleID: "com.example.notes", country: "us", transport: .stub(try Fixture.data("appstore-lookup")))
        let remote = RemoteJSONUpdateSource(
            url: URL(string: "https://example.com/v.json")!,
            transport: .stub(Data(#"{"latestVersion":"2.9","minimumVersion":"2.5"}"#.utf8))
        )
        let update = try await CombinedUpdateSource(appStore, remote).latestUpdate()

        #expect(update.version == "2.10.0")
        #expect(update.minimumRequiredVersion == "2.5")
        #expect(update.storeURL?.host() == "apps.apple.com")
        #expect(update.releaseNotes?.hasPrefix("• Home Screen widgets") == true)
    }

    @Test func newestVersionWinsAndGapsAreFilled() {
        let merged = CombinedUpdateSource.merge([
            UpdateInfo(version: "2.0", releaseNotes: "Old notes", storeURL: URL(string: "https://apps.apple.com/app/id1")),
            UpdateInfo(version: "2.1", minimumRequiredVersion: "1.5"),
            UpdateInfo(version: "1.9", minimumRequiredVersion: "1.8", minimumOSVersion: "17.0"),
        ])
        #expect(merged.version == "2.1")
        #expect(merged.minimumRequiredVersion == "1.8")
        #expect(merged.releaseNotes == "Old notes")
        #expect(merged.minimumOSVersion == "17.0")
        #expect(merged.storeURL == URL(string: "https://apps.apple.com/app/id1"))
    }

    @Test func toleratesPartialFailure() async throws {
        let combined = CombinedUpdateSource(
            StubUpdateSource(error: .httpStatus(500)),
            StubUpdateSource(UpdateInfo(version: "4.0"))
        )
        #expect(try await combined.latestUpdate().version == "4.0")
    }

    @Test func throwsWhenEverySourceFails() async {
        let combined = CombinedUpdateSource(
            StubUpdateSource(error: .appNotFound),
            StubUpdateSource(error: .httpStatus(500))
        )
        await #expect(throws: UpdateSourceError.appNotFound) {
            try await combined.latestUpdate()
        }
    }

    @Test func throwsWithoutSources() async {
        await #expect(throws: UpdateSourceError.noSources) {
            try await CombinedUpdateSource([]).latestUpdate()
        }
    }
}
