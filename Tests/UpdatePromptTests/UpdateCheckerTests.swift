import Foundation
import Testing
@testable import UpdatePrompt

@MainActor
@Suite("UpdateChecker")
struct UpdateCheckerTests {
    let clock = TestClock()
    let store = InMemoryUpdatePromptStore()

    private func makeChecker(
        _ source: any UpdateSource,
        current: AppVersion = "2.3.1",
        os: AppVersion = "26.0",
        policy: UpdatePolicy = .default
    ) -> UpdateChecker {
        let clock = clock
        return UpdateChecker(
            source: source,
            currentVersion: current,
            osVersion: os,
            policy: policy,
            store: store,
            now: { clock.now }
        )
    }

    @Test func offersOptionalUpdateAndRemembersWhen() async {
        let update = UpdateInfo(version: "2.4.0", storeURL: URL(string: "https://apps.apple.com/app/id1"))
        let checker = makeChecker(StubUpdateSource(update))

        let decision = await checker.check()

        #expect(decision == .available(update))
        #expect(checker.offer == UpdateOffer(update: update, currentVersion: "2.3.1", isForced: false))
        #expect(store.load().lastPromptDate == clock.now)
        #expect(!checker.isChecking)
    }

    @Test func upToDateShowsNothing() async {
        let checker = makeChecker(StubUpdateSource(UpdateInfo(version: "2.3.1")))
        #expect(await checker.check() == .upToDate)
        #expect(checker.offer == nil)
    }

    @Test func laterPostponesForTheReaskInterval() async {
        let source = StubUpdateSource(UpdateInfo(version: "2.4.0"))
        let checker = makeChecker(source)
        await checker.check()

        clock.advance(by: 60)
        checker.postpone()
        #expect(checker.offer == nil)
        #expect(store.load().lastPromptDate == clock.now)

        clock.advance(by: 60 * 60)
        guard case .postponed = await checker.check() else {
            Issue.record("Expected the prompt to be postponed")
            return
        }
        #expect(checker.offer == nil)

        clock.advance(by: 24 * 60 * 60)
        #expect(await checker.check()?.shouldPrompt == true)
        #expect(checker.offer != nil)
    }

    @Test func skipHidesThisVersionButNotTheNextOne() async {
        let source = StubUpdateSource(UpdateInfo(version: "2.4.0"))
        let checker = makeChecker(source, policy: UpdatePolicy(reaskInterval: 0))
        await checker.check()

        checker.skipVersion()
        #expect(checker.offer == nil)
        #expect(store.load().skippedVersion == "2.4.0")
        #expect(await checker.check() == .skipped(UpdateInfo(version: "2.4.0")))

        source.set(UpdateInfo(version: "2.5.0"))
        #expect(await checker.check() == .available(UpdateInfo(version: "2.5.0")))
        #expect(checker.offer?.update.version == "2.5.0")
    }

    @Test func forcedUpdateCannotBeDismissed() async {
        let update = UpdateInfo(version: "3.0.0", minimumRequiredVersion: "3.0.0")
        let checker = makeChecker(StubUpdateSource(update))
        await checker.check()

        #expect(checker.offer?.isForced == true)
        checker.postpone()
        checker.skipVersion()
        checker.acceptUpdate()
        #expect(checker.offer?.isForced == true)
        #expect(store.load() == UpdatePromptState())
    }

    @Test func acceptingOptionalUpdateClosesPrompt() async {
        let checker = makeChecker(StubUpdateSource(UpdateInfo(version: "2.4.0")))
        await checker.check()
        checker.acceptUpdate()
        #expect(checker.offer == nil)
    }

    @Test func policyControlsSkipButton() async {
        let checker = makeChecker(StubUpdateSource(UpdateInfo(version: "2.4.0")), policy: UpdatePolicy(allowsSkipping: false))
        await checker.check()
        #expect(checker.offer?.allowsSkipping == false)
    }

    @Test func sourceErrorsAreExposed() async {
        let checker = makeChecker(StubUpdateSource(error: .httpStatus(500)))
        #expect(await checker.check() == nil)
        #expect(checker.lastError as? UpdateSourceError == .httpStatus(500))
        #expect(checker.offer == nil)
    }

    @Test func repeatedChecksKeepTheSameOffer() async {
        let checker = makeChecker(StubUpdateSource(UpdateInfo(version: "3.0", minimumRequiredVersion: "3.0")))
        await checker.check()
        let first = checker.offer
        await checker.check()
        #expect(checker.offer == first)
    }

    @Test func resetForgetsSkipAndLater() async {
        let checker = makeChecker(StubUpdateSource(UpdateInfo(version: "2.4.0")))
        await checker.check()
        checker.skipVersion()
        checker.resetPromptState()
        #expect(checker.promptState == UpdatePromptState())
        #expect(await checker.check()?.shouldPrompt == true)
    }
}

@Suite("UpdatePromptStore")
struct UpdatePromptStoreTests {
    @Test func userDefaultsRoundTrip() throws {
        let suite = "UpdatePromptTests.\(UUID().uuidString)"
        let store = UserDefaultsUpdatePromptStore(suiteName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        #expect(store.load() == UpdatePromptState())
        let state = UpdatePromptState(skippedVersion: "1.10", lastPromptDate: Date(timeIntervalSince1970: 1_000))
        store.save(state)
        #expect(UserDefaultsUpdatePromptStore(suiteName: suite).load() == state)
    }
}
