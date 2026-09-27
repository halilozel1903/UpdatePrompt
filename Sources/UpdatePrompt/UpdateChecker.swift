import Foundation
import Observation

/// Checks an ``UpdateSource`` and decides whether to show the update prompt.
///
/// Create one at the app root and attach it with
/// ``SwiftUICore/View/updatePrompt(_:checksAutomatically:)``:
///
/// ```swift
/// @State private var updates = UpdateChecker(source: AppStoreUpdateSource())
///
/// var body: some Scene {
///     WindowGroup {
///         ContentView()
///             .updatePrompt(updates)
///     }
/// }
/// ```
@MainActor
@Observable
public final class UpdateChecker {
    /// The result of the most recent successful check.
    public private(set) var decision: UpdateDecision?
    /// The update currently offered to the user. The prompt sheet is shown while this is not `nil`.
    public internal(set) var offer: UpdateOffer?
    /// `true` while a check is running.
    public private(set) var isChecking = false
    /// The error of the most recent check, or `nil` if it succeeded.
    public private(set) var lastError: (any Error)?

    /// The installed app version.
    public let currentVersion: AppVersion
    /// The OS version the app runs on.
    public let osVersion: AppVersion
    /// How often optional updates are offered.
    public var policy: UpdatePolicy

    private let source: any UpdateSource
    private let store: any UpdatePromptStore
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - source: Where the newest version comes from.
    ///   - currentVersion: The installed version. Defaults to `CFBundleShortVersionString`.
    ///   - osVersion: The OS version. Defaults to the running OS.
    ///   - policy: How often optional updates are offered.
    ///   - store: Where *Skip* and *Later* are remembered. Defaults to `UserDefaults`.
    ///   - now: The clock. Inject a fixed date in tests.
    public init(
        source: any UpdateSource,
        currentVersion: AppVersion? = nil,
        osVersion: AppVersion? = nil,
        policy: UpdatePolicy = .default,
        store: any UpdatePromptStore = UserDefaultsUpdatePromptStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.currentVersion = currentVersion ?? AppVersion.currentApp ?? AppVersion(major: 0)
        self.osVersion = osVersion ?? AppVersion.currentOS
        self.policy = policy
        self.store = store
        self.now = now
    }

    /// The remembered *Skip* and *Later* state.
    public var promptState: UpdatePromptState { store.load() }

    /// Fetches the newest version and shows the prompt when needed.
    ///
    /// Calls made while a check is already running return the previous decision.
    /// - Returns: The decision, or `nil` if the source failed (see ``lastError``).
    @discardableResult
    public func check() async -> UpdateDecision? {
        guard !isChecking else { return decision }
        isChecking = true
        defer { isChecking = false }
        do {
            let update = try await source.latestUpdate()
            lastError = nil
            return evaluate(update)
        } catch {
            lastError = error
            return nil
        }
    }

    /// Decides about an update you already have, and shows the prompt when needed.
    @discardableResult
    public func evaluate(_ update: UpdateInfo) -> UpdateDecision {
        let decision = UpdateDecisionEngine.decide(
            update: update,
            currentVersion: currentVersion,
            osVersion: osVersion,
            state: store.load(),
            policy: policy,
            now: now()
        )
        self.decision = decision
        switch decision {
        case let .required(info):
            present(UpdateOffer(update: info, currentVersion: currentVersion, isForced: true))
        case let .available(info):
            present(UpdateOffer(
                update: info,
                currentVersion: currentVersion,
                isForced: false,
                allowsSkipping: policy.allowsSkipping
            ))
            recordPrompt()
        case .upToDate, .skipped, .postponed, .unsupportedOS:
            break
        }
        return decision
    }

    // MARK: - User actions

    /// The user tapped *Update*. Optional prompts close; a forced prompt stays
    /// so the app remains blocked until the new version is installed.
    public func acceptUpdate() {
        guard let offer, !offer.isForced else { return }
        self.offer = nil
    }

    /// The user tapped *Later* or swiped the sheet away. Asks again after
    /// ``UpdatePolicy/reaskInterval``. Has no effect on a forced update.
    public func postpone() {
        guard let offer, !offer.isForced else { return }
        recordPrompt()
        self.offer = nil
    }

    /// The user tapped *Skip This Version*. This version is never offered
    /// again; a newer one will be. Has no effect on a forced update.
    public func skipVersion() {
        guard let offer, !offer.isForced else { return }
        var state = store.load()
        state.skippedVersion = offer.update.version
        state.lastPromptDate = now()
        store.save(state)
        self.offer = nil
    }

    /// Forgets *Skip* and *Later*, so the next check can prompt again.
    public func resetPromptState() {
        store.save(UpdatePromptState())
    }

    // MARK: - Private

    private func present(_ newOffer: UpdateOffer) {
        guard offer != newOffer else { return }
        offer = newOffer
    }

    private func recordPrompt() {
        var state = store.load()
        state.lastPromptDate = now()
        store.save(state)
    }
}
