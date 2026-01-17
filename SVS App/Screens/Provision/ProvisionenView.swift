import SwiftUI
import UIKit

/// Provisionen werden nicht mehr in der App erfasst.
/// Stattdessen erzeugt die App einen Einmal-Link, den du dem Kunden schicken kannst.
/// Das Provisionsformular wird online ausgefüllt (inkl. Unterschrift).
struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Link Generation

    /// Basis-URL deines Online-Formulars. (Server muss Token validieren / einmalig machen.)
    private let provisionFormBaseURL = URL(string: "https://sv-souleiman.de/provision")!

    @State private var isGenerating: Bool = false
    @State private var generatedURL: URL? = nil
    @State private var lastGeneratedAt: Date? = nil

    // Inline Error (nur sichtbar, wenn es einen Fehler gibt)
    @State private var showInlineError: Bool = false
    @State private var inlineErrorMessage: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    header

                    if showInlineError {
                        InlineErrorBanner(message: inlineErrorMessage)
                            .padding(.horizontal, 18)
                            .transition(.opacity)
                    }

                    SectionCard(title: "Einmal-Link", systemImage: "link") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Erzeuge einen Einmal-Link für das Online-Provisionsformular. Den Link kannst du dem Kunden schicken. Das Formular wird online ausgefüllt und dort unterschrieben.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if let lastGeneratedAt {
                                Text("Zuletzt erstellt: \(lastGeneratedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                _Concurrency.Task {
                                    await generateOneTimeLink()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(isGenerating ? "Erstelle Link …" : "Einmal-Link erstellen")
                                        .font(.headline)
                                    Spacer()
                                    if isGenerating {
                                        ProgressView()
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(.secondaryLabel))
                            .foregroundColor(.white)
                            .disabled(isGenerating)

                            if let generatedURL {
                                Divider().opacity(0.18)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Link")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(generatedURL.absoluteString)
                                        .font(.footnote)
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                        .lineLimit(3)

                                    HStack(spacing: 10) {
                                        Button {
                                            UIPasteboard.general.string = generatedURL.absoluteString
                                            appState.showToast(.success, "Link kopiert")
                                        } label: {
                                            Label("Kopieren", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.bordered)

                                        ShareLink(item: generatedURL) {
                                            Label("Teilen", systemImage: "square.and.arrow.up")
                                        }
                                        .buttonStyle(.bordered)

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)

                    SectionCard(title: "Übersicht", systemImage: "list.bullet.rectangle") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Die eingereichten Provisionen werden hier automatisch angezeigt, sobald das Online-Formular in Firestore schreibt (z. B. Collection \"commissions\").")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("Hinweis: Dieses Fenster dient nur der Übersicht und dem Erzeugen des Einmal-Links.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)

                }
                .padding(.top, 0)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Provision")
                    .font(.largeTitle.weight(.bold))
                Spacer()
            }
            Text("Einmal-Link erzeugen und Überblick behalten")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Actions

    @MainActor
    private func generateOneTimeLink() async {
        clearInlineError()
        isGenerating = true
        defer { isGenerating = false }

        // Token lokal erzeugen. Der Server muss diesen Token validieren (einmalig + Ablaufzeit).
        // Sobald deine Cloud Function / Web-App steht, ersetzt du diese Stelle durch einen Call
        // an die Function, die den Token in Firestore persistiert und den finalen Link zurückgibt.
        let token = UUID().uuidString

        var comps = URLComponents(url: provisionFormBaseURL, resolvingAgainstBaseURL: false)
        let existing = comps?.queryItems ?? []
        comps?.queryItems = existing + [
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = comps?.url else {
            showError("Link konnte nicht erstellt werden.")
            return
        }

        generatedURL = url
        lastGeneratedAt = Date()

        // Optional: direkt kopieren
        UIPasteboard.general.string = url.absoluteString
        appState.showToast(.success, "Einmal-Link erstellt und kopiert")
    }

    private func showError(_ msg: String) {
        inlineErrorMessage = msg
        showInlineError = true
    }

    private func clearInlineError() {
        if showInlineError {
            showInlineError = false
            inlineErrorMessage = ""
        }
    }
}

// MARK: - Mini Components

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

private struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    ProvisionenView()
        .environmentObject(AppState())
}
