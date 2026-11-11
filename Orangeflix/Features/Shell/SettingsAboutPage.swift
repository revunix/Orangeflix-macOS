import AppKit
import SwiftUI

/// Clean studio About page: hero app identity + developer card, open-source
/// components & licence, and independence disclaimer.
struct SettingsAboutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            heroIdentityCard

            HStack(alignment: .top, spacing: Space.l) {
                developerCard
                componentsCard
            }
            .searchAnchor("about.license")

            SettingsSection("Unabhängigkeit & Hinweise") {
                EmptyView()
            } content: {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Orangeflix for Mac ist ein unabhängiges, privat entwickeltes Projekt und steht in keiner Verbindung zu Orangeflix.de oder deren Betreibern. Es ist weder beauftragt noch offiziell freigegeben oder unterstützt.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    Hairline()

                    Text("Für den Zugriff wird ein bestehendes Konto auf Orangeflix.de benötigt. Für sämtliche Inhalte, Zugänge und Nutzungsbedingungen ist ausschließlich der Plattformbetreiber verantwortlich. Alle genannten Marken und Namen gehören ihren jeweiligen Inhabern.")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .searchAnchor("about.independence")
            }
        }
    }

    private var heroIdentityCard: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return HStack(spacing: Space.l) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Text("Orangeflix for Mac")
                        .font(AppFont.display)
                        .foregroundStyle(Palette.textPrimary)
                    BrandPill(
                        text: "v\(AccountModel.appVersion)",
                        color: Palette.accentText,
                        background: Palette.accentSoft
                    )
                }
                Text("Nativer macOS-Client für die Mediathek, Livestreams und Downloads deines Orangeflix.de-Kontos.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .background {
            shape.fill(
                LinearGradient(
                    colors: [Palette.accentSoft.opacity(0.6), Palette.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            shape.strokeBorder(Palette.accent.opacity(0.28), lineWidth: 1)
        }
    }

    private var developerCard: some View {
        SettingsSection("Entwickler") {
            EmptyView()
        } content: {
            HStack(spacing: Space.m) {
                DeveloperPortrait()

                VStack(alignment: .leading, spacing: 3) {
                    Link(destination: URL(string: "https://github.com/revunix")!) {
                        HStack(spacing: 5) {
                            Text("Alexander")
                                .font(AppFont.heading)
                                .foregroundStyle(Palette.textPrimary)
                            Text("@revunix")
                                .font(AppFont.bodySmall)
                                .foregroundStyle(Palette.accentText)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.accentText)
                        }
                    }
                    .buttonStyle(.plain)

                    Text("„it should work“ · Deutschland")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var componentsCard: some View {
        SettingsSection("Bestandteile & Lizenz") {
            BrandPill(text: "MIT-Lizenz", color: Palette.textSecondary, background: Palette.surfaceMuted)
        } content: {
            VStack(spacing: Space.s) {
                HStack {
                    Text("Video-Engine")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("libmpv")
                        .font(AppFont.bodySmall.monospaced())
                        .foregroundStyle(Palette.textPrimary)
                }
                Hairline()
                HStack {
                    Text("Softwareupdates")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("Sparkle 2")
                        .font(AppFont.bodySmall.monospaced())
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct DeveloperPortrait: View {
    private static let url = URL(string: "https://www.gravatar.com/avatar/f163b408cf74e04d857c250fb31a67a81ba22f4706ba5a7fca4eaee9b4ad8ced?s=192&d=identicon")!

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Palette.divider, lineWidth: 1) }
        .accessibilityLabel("GitHub-Profilbild von Alexander")
        .task { image = await ImageCache.shared.image(for: Self.url) }
    }
}
