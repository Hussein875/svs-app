//
//  SignedDocumentViews.swift
//  SVS App
//

import SwiftUI

struct SignedDocumentRow: View {
    let link: DocumentSigningLinkStatus
    var showsDocumentTitle = false

    var body: some View {
        SignedArchiveEntryRow(
            entry: SignedArchiveEntry.fromRemote(link),
            showsDocumentTitle: showsDocumentTitle
        )
    }
}

struct SignedArchiveEntryRow: View {
    let entry: SignedArchiveEntry
    var showsDocumentTitle = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "doc.richtext.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if showsDocumentTitle {
                    Text(entry.documentTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(entry.sourceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.sourceLabel == "In App" ? .blue : .green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        (entry.sourceLabel == "In App" ? Color.blue : Color.green).opacity(0.12)
                    )
                    .clipShape(Capsule())

                if let signedAt = entry.signedAt {
                    Text(signedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let accidentDateIso = entry.accidentDateIso,
                   let date = ISO8601DateFormatter().date(from: accidentDateIso) {
                    Text("Unfall: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !entry.canOpenPDF, case .remote = entry.selection {
                    Text("PDF wird noch verarbeitet …")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            if entry.canOpenPDF {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SignedDocumentDetailView: View {
    let link: DocumentSigningLinkStatus

    @State private var pdfURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let pdfURL {
                PDFPreview(url: pdfURL)
            } else if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("PDF wird geladen …")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "PDF nicht verfügbar",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage ?? "Das signierte PDF konnte nicht geladen werden.")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(link.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pdfURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: pdfURL) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: link.id) {
            await loadPDF()
        }
    }

    private func loadPDF() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            pdfURL = nil
        }

        if let cached = DocumentSigningLinkService.cachedSignedPDFURL(linkToken: link.id) {
            await MainActor.run {
                pdfURL = cached
                isLoading = false
            }
            return
        }

        do {
            let localURL = try await DocumentSigningLinkService.downloadSignedPDF(
                linkToken: link.id,
                fileName: link.localPDFFileName
            )
            await MainActor.run {
                pdfURL = localURL
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct LocalSignedPDFDetailView: View {
    let record: LocalSignedDocumentRecord

    var body: some View {
        Group {
            if let pdfURL = LocalSignedDocumentArchive.pdfURL(for: record) {
                PDFPreview(url: pdfURL)
            } else {
                ContentUnavailableView(
                    "PDF nicht verfügbar",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Die gespeicherte Datei wurde nicht gefunden.")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(record.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pdfURL = LocalSignedDocumentArchive.pdfURL(for: record) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: pdfURL) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

struct SignedArchiveDetailView: View {
    let selection: SignedArchiveSelection

    var body: some View {
        Group {
            switch selection {
            case .remote(let link):
                SignedDocumentDetailView(link: link)
            case .local(let record):
                LocalSignedPDFDetailView(record: record)
            }
        }
    }
}
