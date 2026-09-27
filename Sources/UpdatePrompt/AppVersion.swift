import Foundation

/// A dotted version number such as `2.4`, `1.10.3` or `3.0.0-beta.2`.
///
/// Components are compared numerically, so `1.10` is newer than `1.9`, and
/// missing components count as zero, so `1.0` equals `1.0.0`. A pre-release
/// suffix (after `-`) sorts before the final release, following Semantic
/// Versioning. Build metadata (after `+`) and a leading `v` are ignored.
///
/// ```swift
/// let installed: AppVersion = "1.9"
/// AppVersion("1.10") > installed   // true
/// ```
///
/// - Note: Because the type is `ExpressibleByStringLiteral`, `AppVersion("1.2")`
///   written with a *literal* is not optional. Parsing a `String` variable goes
///   through the failable ``init(_:)`` and returns `nil` for invalid input.
public struct AppVersion: Sendable, Hashable, Comparable, Codable, CustomStringConvertible,
    LosslessStringConvertible, ExpressibleByStringLiteral
{
    /// Numeric components, for example `[1, 10, 3]`.
    public let components: [Int]
    /// Pre-release identifiers, for example `["beta", "2"]`. Empty for a final release.
    public let prerelease: [String]

    public init(components: [Int], prerelease: [String] = []) {
        self.components = components.isEmpty ? [0] : components.map { max(0, $0) }
        self.prerelease = prerelease
    }

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.init(components: [major, minor, patch])
    }

    /// The version of an operating system, for example `ProcessInfo.processInfo.operatingSystemVersion`.
    public init(_ version: OperatingSystemVersion) {
        self.init(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
    }

    /// Parses a version string. Returns `nil` when it is not a dotted number.
    public init?(_ description: String) {
        var text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        if let plus = text.firstIndex(of: "+") {
            text = String(text[..<plus])
        }

        var prerelease: [String] = []
        if let dash = text.firstIndex(of: "-") {
            prerelease = text[text.index(after: dash)...]
                .split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard prerelease.allSatisfy({ !$0.isEmpty }) else { return nil }
            text = String(text[..<dash])
        }

        var numbers: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part)
            else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { return nil }
        self.init(components: numbers, prerelease: prerelease)
    }

    public init(stringLiteral value: String) {
        guard let version = AppVersion(value as String) else {
            preconditionFailure("\"\(value)\" is not a valid version number")
        }
        self = version
    }

    public var major: Int { component(at: 0) }
    public var minor: Int { component(at: 1) }
    public var patch: Int { component(at: 2) }

    /// `true` when the version has a pre-release suffix such as `-beta.1`.
    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        let core = components.map(String.init).joined(separator: ".")
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    private func component(at index: Int) -> Int {
        components.indices.contains(index) ? components[index] : 0
    }

    /// Components without trailing zeros, so `1.0.0` and `1` compare and hash equal.
    private var normalizedComponents: [Int] {
        var result = components
        while result.count > 1, result.last == 0 {
            result.removeLast()
        }
        return result
    }

    // MARK: - Comparable & Hashable

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.normalizedComponents == rhs.normalizedComponents && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedComponents)
        hasher.combine(prerelease)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return comparePrerelease(lhs.prerelease, rhs.prerelease) < 0
    }

    /// Semantic Versioning precedence for pre-release identifiers.
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Int {
        switch (lhs.isEmpty, rhs.isEmpty) {
        case (true, true): return 0
        case (true, false): return 1 // a final release is newer than its pre-releases
        case (false, true): return -1
        case (false, false): break
        }
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case let (l?, r?): return l < r ? -1 : 1
            case (.some, nil): return -1 // numeric identifiers sort first
            case (nil, .some): return 1
            case (nil, nil): return left < right ? -1 : 1
            }
        }
        return lhs.count == rhs.count ? 0 : (lhs.count < rhs.count ? -1 : 1)
    }

    // MARK: - Codable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let version = AppVersion(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(string)\" is not a valid version number"
            )
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public extension AppVersion {
    /// The `CFBundleShortVersionString` of the running app, if it has one.
    static var currentApp: AppVersion? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return AppVersion(string)
    }

    /// The version of the operating system the app runs on.
    static var currentOS: AppVersion {
        AppVersion(ProcessInfo.processInfo.operatingSystemVersion)
    }
}
