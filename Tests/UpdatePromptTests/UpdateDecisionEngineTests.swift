import Foundation
import Testing
@testable import UpdatePrompt

@Suite("UpdateDecisionEngine")
struct UpdateDecisionEngineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let os: AppVersion = "26.0"
    let day: TimeInterval = 24 * 60 * 60

    private func decide(
        _ update: UpdateInfo,
        current: AppVersion,
        os: AppVersion? = nil,
        state: UpdatePromptState = UpdatePromptState(),
        policy: UpdatePolicy = .default
    ) -> UpdateDecision {
        UpdateDecisionEngine.decide(
            update: update,
            currentVersion: current,
            osVersion: os ?? self.os,
            state: state,
            policy: policy,
            now: now
        )
    }

    @Test func sameVersionIsUpToDate() {
        #expect(decide(UpdateInfo(version: "2.4"), current: "2.4.0") == .upToDate)
    }

    @Test func olderStoreVersionIsUpToDate() {
        // Common while a release is rolling out or during TestFlight builds.
        #expect(decide(UpdateInfo(version: "2.3"), current: "2.4") == .upToDate)
    }

    @Test func newerVersionIsAvailable() {
        let update = UpdateInfo(version: "1.10")
        #expect(decide(update, current: "1.9") == .available(update))
    }

    @Test func versionBelowMinimumIsRequired() {
        let update = UpdateInfo(version: "3.1", minimumRequiredVersion: "3.0")
        #expect(decide(update, current: "2.9.9") == .required(update))
    }

    @Test func versionAtMinimumIsOnlyOptional() {
        let update = UpdateInfo(version: "3.1", minimumRequiredVersion: "3.0")
        #expect(decide(update, current: "3.0") == .available(update))
    }

    @Test func requiredIgnoresSkipAndReaskInterval() {
        let update = UpdateInfo(version: "3.1", minimumRequiredVersion: "3.0")
        let state = UpdatePromptState(skippedVersion: "3.1", lastPromptDate: now)
        #expect(decide(update, current: "2.0", state: state) == .required(update))
    }

    @Test func skippedVersionIsNotOfferedAgain() {
        let update = UpdateInfo(version: "2.5")
        let state = UpdatePromptState(skippedVersion: "2.5.0")
        #expect(decide(update, current: "2.4", state: state) == .skipped(update))
    }

    @Test func newerThanSkippedVersionIsOffered() {
        let update = UpdateInfo(version: "2.6")
        let state = UpdatePromptState(skippedVersion: "2.5")
        #expect(decide(update, current: "2.4", state: state) == .available(update))
    }

    @Test func skippingCanBeDisabled() {
        let update = UpdateInfo(version: "2.5")
        let state = UpdatePromptState(skippedVersion: "2.5")
        let policy = UpdatePolicy(allowsSkipping: false)
        #expect(decide(update, current: "2.4", state: state, policy: policy) == .available(update))
    }

    @Test func recentPromptIsPostponedUntilIntervalEnds() {
        let update = UpdateInfo(version: "2.5")
        let asked = now.addingTimeInterval(-2 * 60 * 60)
        let state = UpdatePromptState(lastPromptDate: asked)
        #expect(decide(update, current: "2.4", state: state) == .postponed(update, until: asked.addingTimeInterval(day)))
    }

    @Test func promptReturnsAfterInterval() {
        let update = UpdateInfo(version: "2.5")
        let state = UpdatePromptState(lastPromptDate: now.addingTimeInterval(-day))
        #expect(decide(update, current: "2.4", state: state) == .available(update))
    }

    @Test func customInterval() {
        let update = UpdateInfo(version: "2.5")
        let state = UpdatePromptState(lastPromptDate: now.addingTimeInterval(-2 * day))
        #expect(decide(update, current: "2.4", state: state, policy: .reasking(everyDays: 3)).shouldPrompt == false)
        #expect(decide(update, current: "2.4", state: state, policy: .reasking(everyDays: 1)).shouldPrompt)
        #expect(decide(update, current: "2.4", state: state, policy: UpdatePolicy(reaskInterval: 0)).shouldPrompt)
    }

    @Test func tooOldOSIsUnsupported() {
        let update = UpdateInfo(version: "5.0", minimumOSVersion: "26.0")
        #expect(decide(update, current: "4.0", os: "18.6") == .unsupportedOS(update))
    }

    @Test func unsupportedOSWinsOverRequired() {
        // Forcing an update that cannot be installed would lock the user out.
        let update = UpdateInfo(version: "5.0", minimumRequiredVersion: "5.0", minimumOSVersion: "26.0")
        #expect(decide(update, current: "4.0", os: "18.6") == .unsupportedOS(update))
    }

    @Test func compatibleOSIsOffered() {
        let update = UpdateInfo(version: "5.0", minimumOSVersion: "17.0")
        #expect(decide(update, current: "4.0", os: "17.0.1") == .available(update))
    }

    @Test func upToDateOnOldOSIsStillUpToDate() {
        let update = UpdateInfo(version: "4.0", minimumOSVersion: "26.0")
        #expect(decide(update, current: "4.0", os: "17.0") == .upToDate)
    }

    @Test func decisionHelpers() {
        let update = UpdateInfo(version: "2.0")
        #expect(UpdateDecision.upToDate.update == nil)
        #expect(UpdateDecision.available(update).update == update)
        #expect(UpdateDecision.required(update).shouldPrompt)
        #expect(UpdateDecision.available(update).shouldPrompt)
        #expect(!UpdateDecision.skipped(update).shouldPrompt)
        #expect(!UpdateDecision.postponed(update, until: now).shouldPrompt)
        #expect(!UpdateDecision.unsupportedOS(update).shouldPrompt)
        #expect(!UpdateDecision.upToDate.shouldPrompt)
    }
}
