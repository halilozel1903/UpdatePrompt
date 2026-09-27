import Foundation

/// Rules that decide how often an optional update is offered.
public struct UpdatePolicy: Sendable, Hashable {
    /// After the user taps *Later*, wait this many seconds before asking again. Default: one day.
    public var reaskInterval: TimeInterval
    /// Offers *Skip This Version* and honors it. Default: `true`.
    public var allowsSkipping: Bool

    public init(reaskInterval: TimeInterval = 24 * 60 * 60, allowsSkipping: Bool = true) {
        self.reaskInterval = max(0, reaskInterval)
        self.allowsSkipping = allowsSkipping
    }

    public static let `default` = UpdatePolicy()

    /// Asks again after `days` days.
    public static func reasking(everyDays days: Double, allowsSkipping: Bool = true) -> UpdatePolicy {
        UpdatePolicy(reaskInterval: days * 24 * 60 * 60, allowsSkipping: allowsSkipping)
    }
}

/// The outcome of comparing the installed app with an ``UpdateInfo``.
public enum UpdateDecision: Sendable, Hashable {
    /// The installed version is the newest one.
    case upToDate
    /// A newer version exists and the user should be asked.
    case available(UpdateInfo)
    /// The installed version is below the minimum; the user must update.
    case required(UpdateInfo)
    /// A newer version exists but the user chose to skip it.
    case skipped(UpdateInfo)
    /// A newer version exists but the user was asked recently.
    case postponed(UpdateInfo, until: Date)
    /// A newer version exists but it does not run on this OS version.
    case unsupportedOS(UpdateInfo)

    /// The update this decision is about, if any.
    public var update: UpdateInfo? {
        switch self {
        case .upToDate: nil
        case let .available(info), let .required(info), let .skipped(info),
             let .postponed(info, _), let .unsupportedOS(info): info
        }
    }

    /// `true` for ``available(_:)`` and ``required(_:)``: the prompt should be shown.
    public var shouldPrompt: Bool {
        switch self {
        case .available, .required: true
        case .upToDate, .skipped, .postponed, .unsupportedOS: false
        }
    }
}

/// The pure decision logic behind ``UpdateChecker``. No I/O, no clock, fully deterministic.
public enum UpdateDecisionEngine {
    /// Decides whether and how to prompt.
    ///
    /// Rules, in order:
    /// 1. If the new version needs a newer OS than `osVersion`: ``UpdateDecision/unsupportedOS(_:)``.
    /// 2. If `currentVersion` is below ``UpdateInfo/minimumRequiredVersion``: ``UpdateDecision/required(_:)``.
    ///    Skipping and the re-ask interval do not apply.
    /// 3. If `update.version` is not newer than `currentVersion`: ``UpdateDecision/upToDate``.
    /// 4. If the user skipped exactly this version: ``UpdateDecision/skipped(_:)``.
    /// 5. If the user was asked less than `policy.reaskInterval` ago: ``UpdateDecision/postponed(_:until:)``.
    /// 6. Otherwise: ``UpdateDecision/available(_:)``.
    public static func decide(
        update: UpdateInfo,
        currentVersion: AppVersion,
        osVersion: AppVersion,
        state: UpdatePromptState = UpdatePromptState(),
        policy: UpdatePolicy = .default,
        now: Date
    ) -> UpdateDecision {
        if let minimumOS = update.minimumOSVersion, osVersion < minimumOS, update.version > currentVersion {
            return .unsupportedOS(update)
        }
        if let minimum = update.minimumRequiredVersion, currentVersion < minimum {
            return .required(update)
        }
        guard update.version > currentVersion else {
            return .upToDate
        }
        if policy.allowsSkipping, state.skippedVersion == update.version {
            return .skipped(update)
        }
        if let last = state.lastPromptDate {
            let next = last.addingTimeInterval(policy.reaskInterval)
            if now < next {
                return .postponed(update, until: next)
            }
        }
        return .available(update)
    }
}
