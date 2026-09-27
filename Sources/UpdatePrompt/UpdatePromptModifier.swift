import SwiftUI

public extension View {
    /// Shows the update prompt of `checker` as a sheet and injects the checker
    /// into the environment.
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
    ///
    /// - Parameters:
    ///   - checker: The checker that decides when to prompt.
    ///   - checksAutomatically: Checks when the view appears and every time the
    ///     app returns to the foreground. The re-ask interval keeps this from
    ///     nagging. Pass `false` to call ``UpdateChecker/check()`` yourself.
    func updatePrompt(_ checker: UpdateChecker, checksAutomatically: Bool = true) -> some View {
        modifier(UpdatePromptModifier(checker: checker, checksAutomatically: checksAutomatically))
    }
}

struct UpdatePromptModifier: ViewModifier {
    @Bindable var checker: UpdateChecker
    let checksAutomatically: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .sheet(item: $checker.offer) { offer in
                UpdatePromptSheet(checker: checker, offer: offer)
            }
            .task {
                guard checksAutomatically else { return }
                await checker.check()
            }
            .onChange(of: scenePhase) { _, phase in
                guard checksAutomatically, phase == .active else { return }
                Task { await checker.check() }
            }
            .environment(checker)
    }
}

/// Wires ``UpdatePromptView`` to the checker and to `openURL`.
struct UpdatePromptSheet: View {
    let checker: UpdateChecker
    let offer: UpdateOffer

    @Environment(\.openURL) private var openURL

    /// A partial height keeps the sheet on Liquid Glass; a forced prompt cannot be resized.
    private var detents: Set<PresentationDetent> {
        offer.isForced ? [.fraction(0.75)] : [.fraction(0.75), .large]
    }

    var body: some View {
        UpdatePromptView(
            offer: offer,
            onUpdate: {
                if let url = offer.update.storeURL {
                    openURL(url)
                }
                checker.acceptUpdate()
            },
            onLater: { checker.postpone() },
            onSkip: { checker.skipVersion() }
        )
        .interactiveDismissDisabled(offer.isForced)
        .presentationDetents(detents)
        .presentationDragIndicator(offer.isForced ? .hidden : .visible)
        .updatePromptSheetBackground()
        #if os(macOS)
        .frame(width: 440, height: 580)
        #endif
    }
}

extension View {
    /// The system Liquid Glass sheet on iOS 26 and macOS 26, a material everywhere else.
    @ViewBuilder
    func updatePromptSheetBackground() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
        } else {
            presentationBackground(.regularMaterial)
        }
    }
}
