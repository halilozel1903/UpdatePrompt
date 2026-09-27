import SwiftUI
import UpdatePrompt

struct ContentView: View {
    let source: FakeUpdateSource

    @Environment(UpdateChecker.self) private var checker
    @State private var scenario: FakeUpdateSource.Scenario

    init(source: FakeUpdateSource) {
        self.source = source
        _scenario = State(initialValue: source.scenario)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Installed version", value: checker.currentVersion.description)
                    LabeledContent("Last result") {
                        if checker.isChecking {
                            ProgressView()
                        } else {
                            Text(resultText)
                        }
                    }
                } header: {
                    Text("This app")
                }

                Section {
                    Picker("Server says", selection: $scenario) {
                        ForEach(FakeUpdateSource.Scenario.allCases) { scenario in
                            Text(scenario.rawValue).tag(scenario)
                        }
                    }
                    Button("Check for Updates") {
                        source.scenario = scenario
                        Task { await checker.check() }
                    }
                    .disabled(checker.isChecking)
                } header: {
                    Text("Simulate")
                } footer: {
                    Text("The demo uses an in-memory source, so nothing is fetched from the network.")
                }

                Section {
                    Button("Forget Skip & Later") {
                        checker.resetPromptState()
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("Optional updates are offered again one day after tapping Later. A skipped version is never offered again.")
                }
            }
            .navigationTitle("UpdatePrompt")
        }
    }

    private var resultText: String {
        switch checker.decision {
        case nil: "Not checked"
        case .upToDate: "Up to date"
        case let .available(update): "\(update.version) available"
        case let .required(update): "\(update.version) required"
        case let .skipped(update): "\(update.version) skipped"
        case .postponed: "Asked recently"
        case let .unsupportedOS(update): "\(update.version) needs a newer OS"
        }
    }
}

#Preview {
    let source = FakeUpdateSource(scenario: .optional)
    ContentView(source: source)
        .updatePrompt(UpdateChecker(source: source, currentVersion: "2.3.1", store: InMemoryUpdatePromptStore()))
}
