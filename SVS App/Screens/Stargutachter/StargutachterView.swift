//
//  StargutachterView.swift
//  SVS App
//

import SafariServices
import SwiftUI

enum StargutachterLink {
    static let url = URL(string: "https://stargutachter.de/dsjhl238jd230")!

    static var customerShareMessage: String {
        """
        Hallo,

        Wir melden uns bezüglich Ihres Schadenfalls und der Erstellung eines Schadengutachtens.

        Für die Schadenaufnahme bitten wir Sie, den folgenden Link zu öffnen:

        \(url.absoluteString)/

        Dort finden Sie ein einfaches Formular, über das Sie uns die Bilder Ihres Fahrzeugs sowie die erforderlichen Informationen bequem übermitteln können.

        Sobald uns die Unterlagen vorliegen, werden wir die Schadenaufnahme prüfen und das Gutachten für Sie erstellen.

        Bei Fragen stehen wir Ihnen selbstverständlich jederzeit gerne zur Verfügung.

        Mit freundlichen Grüßen
        """
    }
}

struct StargutachterView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSafari = false

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Schadenaufnahme vorbereiten", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.tint)

                    Text(
                        "Mit diesem Link bereitet der Kunde die Schadenaufnahme vor – er stellt Bilder "
                            + "und Informationen zum Unfall bereit. Schicke den Link an den Kunden; "
                            + "er landet bei Stargutachter."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Link")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(StargutachterLink.url.absoluteString)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

                Button {
                    showSafari = true
                } label: {
                    Label("Link öffnen", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = StargutachterLink.customerShareMessage
                        appState.showToast(.success, "Nachricht kopiert")
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: StargutachterLink.customerShareMessage) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .tint(userAccentColor)
        .navigationTitle("Stargutachter")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            InAppSafariView(url: StargutachterLink.url)
                .ignoresSafeArea()
        }
    }
}

private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
