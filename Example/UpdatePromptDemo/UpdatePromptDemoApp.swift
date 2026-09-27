import SwiftUI
import UpdatePrompt

@main
struct UpdatePromptDemoApp: App {
    @State private var source: FakeUpdateSource
    @State private var store: InMemoryUpdatePromptStore
    @State private var checker: UpdateChecker

    init() {
        let source = FakeUpdateSource(scenario: ScreenshotScene.current?.scenario ?? .optional)
        // In-memory, so every launch (and every screenshot) starts fresh.
        // Real apps keep the default `UserDefaultsUpdatePromptStore`.
        let store = InMemoryUpdatePromptStore()
        _source = State(initialValue: source)
        _store = State(initialValue: store)
        _checker = State(initialValue: UpdateChecker(
            source: source,
            currentVersion: FakeUpdateSource.installedVersion,
            store: store
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(source: source)
                .updatePrompt(checker)
        }
    }
}
