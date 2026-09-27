import Foundation

/// What an ``UpdateSource`` knows about the newest version of the app.
public struct UpdateInfo: Sendable, Hashable, Codable {
    /// The newest version that is available.
    public var version: AppVersion
    /// Installed versions below this one must update before they can be used.
    public var minimumRequiredVersion: AppVersion?
    /// "What's New" text shown in the prompt.
    public var releaseNotes: String?
    /// When the newest version was released.
    public var releaseDate: Date?
    /// The oldest OS version the newest app version runs on.
    public var minimumOSVersion: AppVersion?
    /// Where the user can install the update, usually the App Store product page.
    public var storeURL: URL?

    public init(
        version: AppVersion,
        minimumRequiredVersion: AppVersion? = nil,
        releaseNotes: String? = nil,
        releaseDate: Date? = nil,
        minimumOSVersion: AppVersion? = nil,
        storeURL: URL? = nil
    ) {
        self.version = version
        self.minimumRequiredVersion = minimumRequiredVersion
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.minimumOSVersion = minimumOSVersion
        self.storeURL = storeURL
    }
}

/// An update the user should be asked about. Drives the prompt sheet.
public struct UpdateOffer: Identifiable, Sendable, Hashable {
    public var update: UpdateInfo
    /// The version that is installed right now.
    public var currentVersion: AppVersion
    /// A forced update has no *Later* or *Skip* button and cannot be dismissed.
    public var isForced: Bool
    /// Shows the *Skip This Version* button for optional updates.
    public var allowsSkipping: Bool

    public init(update: UpdateInfo, currentVersion: AppVersion, isForced: Bool, allowsSkipping: Bool = true) {
        self.update = update
        self.currentVersion = currentVersion
        self.isForced = isForced
        self.allowsSkipping = allowsSkipping
    }

    public var id: String { "\(update.version)-\(isForced ? "forced" : "optional")" }
}
