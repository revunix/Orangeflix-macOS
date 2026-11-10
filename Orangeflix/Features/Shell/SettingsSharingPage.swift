import SwiftUI

/// The sharing links of the account: the quota of the month, the links that
/// exist, and a code that can be checked without being signed in.
struct SettingsSharingPage: View {
    @Binding var pendingDelete: SettingsDelete?

    @Environment(AppModel.self) private var app
    @Environment(SharingModel.self) private var sharing

    /// The code of a sharing link that is checked. It lives here so typing
    /// does not rebuild the sidebar.
    @State private var shareCode = ""
    /// The result of the check of a sharing code.
    @State private var shareCheck: String?

    var body: some View {
        Group {
            if app.hasCredentials {
                signedIn
            } else {
                Section {
                    Text("Nicht angemeldet")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Die Anmeldung erfolgt im Hauptfenster. Ein Code lässt sich auch ohne Anmeldung prüfen.")
                }
            }

            Section {
                TextField("Code", text: $shareCode, prompt: Text("Code eines Links"))
                Button("Code prüfen") {
                    Task { shareCheck = await sharing.inspect(code: shareCode) }
                }
                .searchAnchor("sharing.check")
                if let shareCheck {
                    Text(shareCheck)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Code prüfen")
            } footer: {
                Text("Prüft einen Link, ohne angemeldet zu sein.")
            }
        }
        .task(id: app.accountGeneration) {
            if app.hasCredentials, sharing.needsLoad { await sharing.load() }
        }
    }

    /// The quota, the link that was just created and the links of the account.
    @ViewBuilder private var signedIn: some View {
        if let error = sharing.error {
            Section {
                ProfileNotice(symbol: "exclamationmark.triangle.fill", text: error,
                              tint: Palette.danger, background: Palette.dangerSoft)
            }
        }

        Section {
            LabeledContent("Kontingent") { Text(sharing.quotaText) }
                .searchAnchor("sharing.quota")
            Button("Neu laden") { Task { await sharing.load() } }
                .disabled(sharing.isLoading)
                .searchAnchor("sharing.reload")
        } header: {
            Text("Kontingent")
        } footer: {
            Text("Jeder Link erlaubt eine begrenzte Zahl von Aufrufen. Ein Link, der schon benutzt wurde, lässt sich nicht mehr beenden.")
        }

        if let link = sharing.freshLink {
            Section {
                LabeledContent("Link") {
                    Text(link.url.isEmpty ? link.code : link.url)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Button("Link kopieren") {
                        AppFormat.copy(link.url.isEmpty ? link.code : link.url)
                    }
                    Button("Fertig") { sharing.dismissFreshLink() }
                }
            } header: {
                Text("Neuer Link")
            } footer: {
                Text("Der Link ist auf \(link.accessLimit) Aufrufe begrenzt.")
            }
        }

        Section {
            if sharing.links.isEmpty {
                // A failed load is not an empty list; the notice above says
                // what went wrong.
                Text(sharing.isLoading ? "Die Links werden geladen …"
                     : sharing.error != nil ? "Die Links konnten nicht geladen werden."
                     : "Es gibt noch keine Sharing-Links.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sharing.links, id: \.code) { link in
                sharingRow(link)
            }
        } header: {
            Text("Links")
        }
    }

    /// One sharing link with its state and the buttons that act on it.
    private func sharingRow(_ link: SharingLinkEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            LabeledContent(link.clipId) {
                Text(link.unlimited ? "unbegrenzt" : (link.remaining.map { "\($0) übrig" } ?? "—"))
                    .foregroundStyle(.secondary)
            }
            Text(link.createdDate.map { "Angelegt am \(AppFormat.day($0))" } ?? "Unbenutzter Link")
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Button("Code kopieren") { AppFormat.copy(link.code) }
                Button("Beenden") { pendingDelete = .sharingLink(link.code) }
                    .disabled(!link.isRevocable)
            }
        }
    }
}
