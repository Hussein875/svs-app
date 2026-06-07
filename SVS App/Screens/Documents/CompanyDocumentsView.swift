//
//  CompanyDocumentsView.swift
//  SVS App
//

import SwiftUI

struct CompanyDocumentsView: View {
    @EnvironmentObject private var appState: AppState

    private var accent: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var availableDocuments: [CompanyDocument] {
        CompanyDocumentsCatalog.availableItems
    }

    var body: some View {
        Group {
            if availableDocuments.isEmpty {
                emptyState
            } else {
                documentsList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dokumente")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var documentsList: some View {
        List {
            ForEach(CompanyDocumentSection.allCases) { section in
                let sectionItems = CompanyDocumentsCatalog.availableItems(in: section)
                if !sectionItems.isEmpty {
                    Section {
                        if section == .internalDocuments {
                            ForEach(sectionItems) { document in
                                internalDocumentLink(document)
                            }
                        } else {
                            ForEach(sectionItems) { document in
                                lawyerDocumentLink(document)
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    } footer: {
                        if let footer = section.footer {
                            Text(footer)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sectionHeader(_ section: CompanyDocumentSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section == .internalDocuments ? "star.fill" : "briefcase.fill")
                .font(.caption.weight(.semibold))
            Text(section.title)
        }
    }

    @ViewBuilder
    private func internalDocumentLink(_ document: CompanyDocument) -> some View {
        if let url = CompanyDocumentsCatalog.bundleURL(for: document) {
            NavigationLink {
                CompanyDocumentDetailView(document: document, fileURL: url)
            } label: {
                internalDocumentRow(document)
            }
        }
    }

    @ViewBuilder
    private func lawyerDocumentLink(_ document: CompanyDocument) -> some View {
        if let url = CompanyDocumentsCatalog.bundleURL(for: document) {
            NavigationLink {
                CompanyDocumentDetailView(document: document, fileURL: url)
            } label: {
                lawyerDocumentRow(document)
            }
        }
    }

    private func internalDocumentRow(_ document: CompanyDocument) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.14))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: document.accentSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                if let code = document.subtitle?.split(separator: "·").first?
                    .trimmingCharacters(in: .whitespaces) {
                    Text(String(code))
                        .font(.caption.weight(.bold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }

                Text(document.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let subtitle = document.subtitle,
                   subtitle.contains("·") {
                    Text(
                        subtitle.split(separator: "·", maxSplits: 1).dropFirst()
                            .first.map(String.init) ?? subtitle
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func lawyerDocumentRow(_ document: CompanyDocument) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: document.accentSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.body.weight(.semibold))
                if let subtitle = document.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.down.doc")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Noch keine Dokumente")
                .font(.headline)

            Text("Die PDF-Dateien wurden im App-Bundle nicht gefunden. Bitte die App neu bauen und installieren (Xcode oder TestFlight).")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CompanyDocumentDetailView: View {
    let document: CompanyDocument
    let fileURL: URL

    var body: some View {
        PDFPreview(url: fileURL)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: fileURL) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
    }
}

#Preview {
    NavigationStack {
        CompanyDocumentsView()
            .environmentObject(AppState())
    }
}
