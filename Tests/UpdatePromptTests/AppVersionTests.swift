import Foundation
import Testing
@testable import UpdatePrompt

@Suite("AppVersion")
struct AppVersionTests {
    @Test(arguments: [
        ("1.10", "1.9"),
        ("1.10.0", "1.9.9"),
        ("2.0", "1.99.99"),
        ("1.0.1", "1.0"),
        ("10.0", "9.0"),
        ("1.2.0", "1.2.0-beta.1"),
        ("1.2.0-beta.2", "1.2.0-beta.1"),
        ("1.2.0-beta.11", "1.2.0-beta.2"),
        ("1.2.0-rc.1", "1.2.0-beta.5"),
        ("1.2.0-beta", "1.2.0-alpha.9"),
        ("1.2.0-alpha.1", "1.2.0-alpha"),
    ])
    func newerVersionIsGreater(newer: String, older: String) throws {
        let lhs = try #require(AppVersion(newer))
        let rhs = try #require(AppVersion(older))
        #expect(lhs > rhs)
        #expect(rhs < lhs)
        #expect(lhs != rhs)
    }

    @Test(arguments: [
        ("1.0", "1.0.0"),
        ("1", "1.0.0.0"),
        ("v2.3", "2.3.0"),
        ("2.3.0+build.77", "2.3"),
        ("  4.1 ", "4.1.0"),
    ])
    func equivalentSpellingsAreEqual(lhs: String, rhs: String) throws {
        let left = try #require(AppVersion(lhs))
        let right = try #require(AppVersion(rhs))
        #expect(left == right)
        #expect(left.hashValue == right.hashValue)
        #expect(!(left < right) && !(right < left))
    }

    @Test(arguments: ["", "abc", "1..2", "1.2.", ".1", "1.2a", "1.-2", "1.0-", "1.0-beta..1", "١.٢", "99999999999999999999"])
    func rejectsInvalidStrings(_ string: String) {
        #expect(AppVersion(string) == nil)
    }

    @Test func exposesComponents() throws {
        let version = try #require(AppVersion("3.14.15-rc.1"))
        #expect(version.major == 3)
        #expect(version.minor == 14)
        #expect(version.patch == 15)
        #expect(version.prerelease == ["rc", "1"])
        #expect(version.isPrerelease)
        #expect(version.description == "3.14.15-rc.1")

        let short: AppVersion = "5"
        #expect(short.minor == 0)
        #expect(short.patch == 0)
        #expect(short.description == "5")
    }

    @Test func stringLiteralAndOperatingSystemVersion() {
        let literal: AppVersion = "17.4.1"
        let os = AppVersion(OperatingSystemVersion(majorVersion: 17, minorVersion: 4, patchVersion: 1))
        #expect(literal == os)
        #expect(AppVersion(major: 17, minor: 4, patch: 1) == os)
    }

    @Test func sortsNumerically() {
        let versions: [AppVersion] = ["1.10", "1.2", "1.9", "1.1.5", "1.10-beta"]
        #expect(versions.sorted().map(\.description) == ["1.1.5", "1.2", "1.9", "1.10-beta", "1.10"])
    }

    @Test func codableRoundTripUsesStrings() throws {
        let version: AppVersion = "2.10.1-beta.3"
        let data = try JSONEncoder().encode([version])
        #expect(String(decoding: data, as: UTF8.self) == #"["2.10.1-beta.3"]"#)
        #expect(try JSONDecoder().decode([AppVersion].self, from: data) == [version])
    }

    @Test func decodingInvalidStringThrows() {
        let data = Data(#"["not a version"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([AppVersion].self, from: data)
        }
    }
}
