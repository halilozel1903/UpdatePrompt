import Foundation

/// What the prompt remembers between launches.
public struct UpdatePromptState: Sendable, Hashable, Codable {
    /// The version the user chose to skip.
    public var skippedVersion: AppVersion?
    /// When an optional update was last shown or postponed.
    public var lastPromptDate: Date?

    public init(skippedVersion: AppVersion? = nil, lastPromptDate: Date? = nil) {
        self.skippedVersion = skippedVersion
        self.lastPromptDate = lastPromptDate
    }
}

/// Persists ``UpdatePromptState``.
public protocol UpdatePromptStore: Sendable {
    func load() -> UpdatePromptState
    func save(_ state: UpdatePromptState)
}

/// Stores the state as JSON in `UserDefaults`. This is the default store.
public struct UserDefaultsUpdatePromptStore: UpdatePromptStore {
    /// The defaults suite, or `nil` for `UserDefaults.standard`.
    public let suiteName: String?
    public let key: String

    public init(suiteName: String? = nil, key: String = "UpdatePrompt.state") {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func load() -> UpdatePromptState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(UpdatePromptState.self, from: data)
        else { return UpdatePromptState() }
        return state
    }

    public func save(_ state: UpdatePromptState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Keeps the state in memory only. Useful for tests, previews and demos.
public final class InMemoryUpdatePromptStore: UpdatePromptStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: UpdatePromptState

    public init(_ state: UpdatePromptState = UpdatePromptState()) {
        self.state = state
    }

    public func load() -> UpdatePromptState {
        lock.withLock { state }
    }

    public func save(_ state: UpdatePromptState) {
        lock.withLock { self.state = state }
    }
}
