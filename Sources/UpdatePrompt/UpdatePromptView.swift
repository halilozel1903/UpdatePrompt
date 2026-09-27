import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The content of the update sheet: app icon, versions, release notes and buttons.
///
/// ``SwiftUICore/View/updatePrompt(_:checksAutomatically:)`` presents it for you.
/// It is public so you can embed it in your own presentation, for example a
/// full-screen cover or an onboarding page.
public struct UpdatePromptView: View {
    private let offer: UpdateOffer
    private let onUpdate: () -> Void
    private let onLater: () -> Void
    private let onSkip: () -> Void

    public init(
        offer: UpdateOffer,
        onUpdate: @escaping () -> Void,
        onLater: @escaping () -> Void = {},
        onSkip: @escaping () -> Void = {}
    ) {
        self.offer = offer
        self.onUpdate = onUpdate
        self.onLater = onLater
        self.onSkip = onSkip
    }

    private var update: UpdateInfo { offer.update }

    public var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                versionBadge
                if let notes = update.releaseNotes {
                    releaseNotes(notes)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            buttons
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 520)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 16) {
            AppIconView()
            VStack(spacing: 8) {
                Text(offer.isForced ? "Update Required" : "Update Available")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String {
        if offer.isForced {
            return "This version is no longer supported. Update to version \(update.version) to keep using the app."
        }
        return "Version \(update.version) is ready to install. Enjoy the latest features and fixes."
    }

    private var versionBadge: some View {
        HStack(spacing: 10) {
            Text(offer.currentVersion.description)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(update.version.description)
                .fontWeight(.semibold)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .versionBadgeBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Installed version \(offer.currentVersion.description), new version \(update.version.description)")
    }

    private func releaseNotes(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("What's New")
                    .font(.headline)
                Spacer()
                if let date = update.releaseDate {
                    Text(date, format: .dateTime.day().month().year())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(notes)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onUpdate) {
                Label("Update Now", systemImage: "arrow.down.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .updatePromptPrimaryButtonStyle()
            .disabled(update.storeURL == nil)

            if !offer.isForced {
                HStack(spacing: 10) {
                    Button(action: onLater) {
                        Text("Later").frame(maxWidth: .infinity)
                    }
                    if offer.allowsSkipping {
                        Button(action: onSkip) {
                            Text("Skip This Version").frame(maxWidth: .infinity)
                        }
                    }
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .updatePromptSecondaryButtonStyle()
            }
        }
    }
}

// MARK: - App icon

/// The app's own icon when it can be found, otherwise a gradient placeholder.
struct AppIconView: View {
    var size: CGFloat = 84

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let icon = Self.appIcon {
                icon
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.56, blue: 1.0), Color(red: 0.43, green: 0.30, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @MainActor
    private static var appIcon: Image? {
        #if canImport(UIKit)
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any]
        else { return nil }
        let name = (primary["CFBundleIconFiles"] as? [String])?.last ?? (primary["CFBundleIconName"] as? String)
        guard let name, let image = UIImage(named: name) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSApplication.shared.applicationIconImage else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

// MARK: - Glass styling

extension View {
    @ViewBuilder
    func updatePromptPrimaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func updatePromptSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func versionBadgeBackground() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
        }
    }
}

#Preview("Optional") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UpdatePromptView(
            offer: UpdateOffer(
                update: UpdateInfo(
                    version: "2.4.0",
                    releaseNotes: "• Home Screen widgets\n• Faster sync\n• Bug fixes",
                    releaseDate: Date(),
                    storeURL: URL(string: "https://apps.apple.com")
                ),
                currentVersion: "2.3.1",
                isForced: false
            ),
            onUpdate: {}
        )
        .presentationDetents([.fraction(0.75)])
    }
}

#Preview("Forced") {
    UpdatePromptView(
        offer: UpdateOffer(
            update: UpdateInfo(version: "3.0.0", storeURL: URL(string: "https://apps.apple.com")),
            currentVersion: "2.1.0",
            isForced: true
        ),
        onUpdate: {}
    )
}
