import AppKit
import SwiftUI

/// What the app is, which version runs, under which licence it stands and
/// that it is an independent project.
struct SettingsAboutPage: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            Section {
                HStack(spacing: Space.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orangeflix for Mac")
                            .font(AppFont.heading)
                        Text("Version \(AccountModel.appVersion)")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("App")
            } footer: {
                Text("Ein inoffizielles Zusatzprogramm für macOS, um die Mediathek eines Orangeflix.de-Kontos am Schreibtisch zu nutzen.")
            }

            Section {
                HStack(spacing: Space.m) {
                    DeveloperPortrait()

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Entwickelt von")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                        Link(destination: URL(string: "https://github.com/revunix")!) {
                            HStack(spacing: Space.xs) {
                                Text("Alexander")
                                    .font(AppFont.heading)
                                Text("@revunix")
                                    .font(AppFont.bodySmall)
                                    .foregroundStyle(themeColor(.textSecondary))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        Text("„it should work“ · Deutschland")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("Entwickler")
            }

            Section {
                Text("Orangeflix for Mac ist ein unabhängiges, privat entwickeltes Projekt. Es steht in keiner Verbindung zu Orangeflix.de, zu deren Betreibern oder zu einem anderen Programm gleichen Namens. Es ist weder von dort beauftragt noch freigegeben, unterstützt oder mitgetragen.")
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .searchAnchor("about.independence")
            } header: {
                Text("Keine Verbindung zur Plattform")
            } footer: {
                Text("Der Name beschreibt nur, wofür die App gedacht ist. Marken und Namen gehören ihren jeweiligen Inhabern.")
            }

            Section {
                LabeledContent("Lizenz") {
                    Text("MIT")
                        .textSelection(.enabled)
                }
                .searchAnchor("about.license")
                Text("Der Quelltext steht unter der MIT-Lizenz. Er darf benutzt, verändert und weitergegeben werden, solange der Lizenztext und der Urheberrechtshinweis erhalten bleiben. Für die Nutzung gilt keine Gewährleistung.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(themeColor(.textSecondary))
            } header: {
                Text("Lizenz")
            }

            Section {
                LabeledContent("Updates") {
                    Text("Sparkle")
                        .textSelection(.enabled)
                }
                .searchAnchor("about.sparkle")
                LabeledContent("Wiedergabe") {
                    Text("libmpv")
                        .textSelection(.enabled)
                }
                .searchAnchor("about.libmpv")
            } header: {
                Text("Bestandteile")
            } footer: {
                Text("Neue Versionen sucht und installiert Sparkle; vor der Installation wird die Signatur geprüft. Folgen und Livestreams spielt die mitgelieferte Bibliothek libmpv.")
            }

            Section {
                Text("Die App greift auf die Schnittstellen von Orangeflix.de zu und braucht dafür ein Konto dort. Für Inhalte, Zugänge und Bedingungen ist der Anbieter verantwortlich, nicht dieses Programm.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(themeColor(.textSecondary))
            } header: {
                Text("Inhalte und Zugang")
            }
        }
    }

    private func themeColor(_ token: ThemeToken) -> Color {
        Color(hex: ThemeRuntime.shared.hex(token, dark: colorScheme == .dark))
    }
}

/// The picture on the Über page. `ImageCache` keeps it, so opening the
/// page again does not fetch it from the network.
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
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .accessibilityLabel("GitHub-Profilbild von Alexander")
        .task { image = await ImageCache.shared.image(for: Self.url) }
    }
}
