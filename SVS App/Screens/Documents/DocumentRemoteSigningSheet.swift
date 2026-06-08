//
//  DocumentRemoteSigningSheet.swift
//  SVS App
//

import SwiftUI
import UIKit

struct DocumentRemoteSigningSheet: View {
    private enum SigningFormField: Hashable {
        case customerName
        case notes
    }

    let document: CompanyDocument
    let sourcePDFURL: URL

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: SigningFormField?
    @StateObject private var statusModel = DocumentSigningStatusViewModel()

    @State private var accidentDate = Date()
    @State private var customerName = ""
    @State private var notes = ""
    @State private var isGenerating = false
    @State private var generatedLink: DocumentSigningLinkResult?
    @State private var errorMessage: String?
    @State private var pdfErrorMessage: String?
    @State private var openingPDFToken: String?
    @State private var previewPDFURL: URL?
    @State private var previewPDFTitle = "Signiertes PDF"
    @State private var showCreateLinkSection = false
    @State private var deleteErrorMessage: String?

    private var signedLinks: [DocumentSigningLinkStatus] {
        statusModel.links.filter(\.isSigned)
    }

    private var openLinks: [DocumentSigningLinkStatus] {
        statusModel.links.filter { !$0.isSigned }
    }

    var body: some View {
        NavigationStack {
            signingList
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Kundenunterschrift")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { signingToolbar }
        }
        .onAppear(perform: handleAppear)
        .onDisappear { statusModel.stop() }
        .refreshable { await statusModel.refresh(documentId: document.id) }
        .fullScreenCover(isPresented: pdfPreviewPresented, content: pdfPreviewCover)
        .alert("Link fehlgeschlagen", isPresented: linkErrorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Löschen fehlgeschlagen", isPresented: deleteErrorPresented) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert("PDF konnte nicht geladen werden", isPresented: pdfErrorPresented) {
            Button("OK", role: .cancel) { pdfErrorMessage = nil }
        } message: {
            Text(pdfErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var signingList: some View {
        List {
            loadingSection
            errorSection
            signedDocumentsSection
            emptySignedDocumentsSection
            openLinksSection
            createLinkSection
            latestGeneratedLinkSection
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if statusModel.isLoading && statusModel.links.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Signierte Dokumente werden geladen …")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let loadError = statusModel.lastError {
            Section {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } footer: {
                Text("Prüfe die Internetverbindung und ziehe die Liste nach unten zum Aktualisieren.")
            }
        }
    }

    @ViewBuilder
    private var signedDocumentsSection: some View {
        if !signedLinks.isEmpty {
            Section {
                ForEach(signedLinks) { link in
                    signedDocumentCard(link)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    _Concurrency.Task { await deleteLinks(at: offsets, in: signedLinks) }
                }
            } header: {
                signedDocumentsHeader
            } footer: {
                Text(signedDocumentsFooter)
            }
        }
    }

    @ViewBuilder
    private var emptySignedDocumentsSection: some View {
        if signedLinks.isEmpty && !statusModel.isLoading && statusModel.lastError == nil {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Noch keine Unterschriften")
                        .font(.headline)
                    Text("Sobald ein Kunde online unterschreibt, erscheint das PDF hier.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var openLinksSection: some View {
        if !openLinks.isEmpty {
            Section {
                ForEach(openLinks) { link in
                    openLinkRow(link)
                }
                .onDelete { offsets in
                    _Concurrency.Task { await deleteLinks(at: offsets, in: openLinks) }
                }
            } header: {
                Text("Offene Links")
            } footer: {
                Text("Noch nicht unterschriebene Links kannst du ebenfalls nach links wischen, um sie zu entfernen.")
            }
        }
    }

    @ViewBuilder
    private var createLinkSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showCreateLinkSection) {
                createLinkForm
            } label: {
                Label("Neuen Kundenlink erstellen", systemImage: "link.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
        } footer: {
            if !showCreateLinkSection {
                Text("Unfalldatum wird ins PDF eingetragen. Unterschrift und Datum trägt der Kunde online ein.")
            }
        }
    }

    @ViewBuilder
    private var latestGeneratedLinkSection: some View {
        if let generatedLink {
            Section("Zuletzt erstellter Link") {
                generatedLinkRows(generatedLink)
            }
        }
    }

    @ToolbarContentBuilder
    private var signingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Schließen") {
                dismissSigningKeyboard()
                dismiss()
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Fertig") {
                dismissSigningKeyboard()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !signedLinks.isEmpty {
                Text("\(signedLinks.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .accessibilityLabel("\(signedLinks.count) signierte Dokumente")
            }
        }
    }

    private var signedDocumentsFooter: String {
        let count = signedLinks.count
        let suffix = count == 1 ? "s" : ""
        let docSuffix = count == 1 ? "" : "e"
        return "Nach links wischen zum Löschen. \(count) unterschriebene\(suffix) Dokument\(docSuffix)."
    }

    private var pdfPreviewPresented: Binding<Bool> {
        Binding(
            get: { previewPDFURL != nil },
            set: { isPresented in
                if !isPresented {
                    previewPDFURL = nil
                }
            }
        )
    }

    private var linkErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )
    }

    private var pdfErrorPresented: Binding<Bool> {
        Binding(
            get: { pdfErrorMessage != nil },
            set: { if !$0 { pdfErrorMessage = nil } }
        )
    }

    @ViewBuilder
    private func pdfPreviewCover() -> some View {
        if let fileURL = previewPDFURL {
            SignedPDFViewerSheet(
                fileURL: fileURL,
                title: previewPDFTitle,
                onClose: { self.previewPDFURL = nil }
            )
        }
    }

    private func handleAppear() {
        statusModel.start(documentId: document.id)
        showCreateLinkSection = signedLinks.isEmpty
    }

    private func dismissSigningKeyboard() {
        focusedField = nil
        hideKeyboard()
    }

    private var signedDocumentsHeader: some View {
        HStack {
            Label("Signierte Dokumente", systemImage: "checkmark.seal.fill")
            Spacer()
            if statusModel.isLoading && !signedLinks.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func signedDocumentCard(_ link: DocumentSigningLinkStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.richtext.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.displayName)
                        .font(.headline)

                    if !link.documentTitle.isEmpty {
                        Text(link.documentTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let signedAt = link.signedAt {
                        Text("Unterschrieben \(signedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let accidentDateIso = link.accidentDateIso,
                       let date = ISO8601DateFormatter().date(from: accidentDateIso) {
                        Label(
                            "Unfall: \(date.formatted(date: .abbreviated, time: .omitted))",
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            if link.isSigned && !link.canOpenSignedPDF {
                Label(
                    "PDF wird noch verarbeitet …",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button {
                    _Concurrency.Task { await openSignedPDF(for: link) }
                } label: {
                    HStack(spacing: 8) {
                        if openingPDFToken == link.id {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("PDF anzeigen")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(openingPDFToken == link.id || (link.isSigned && !link.canOpenSignedPDF))

                if let cached = DocumentSigningLinkService.cachedSignedPDFURL(linkToken: link.id) {
                    ShareLink(item: cached) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.green.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func openLinkRow(_ link: DocumentSigningLinkStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(link.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge(
                    label: link.statusLabel,
                    color: link.isSigned ? .green : (link.isExpired ? .orange : .blue)
                )
            }

            if let expiresAt = link.expiresAt {
                Text("Gültig bis: \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let shareURL = DocumentSigningLinkService.publicSigningURL(forToken: link.id) {
                HStack(spacing: 12) {
                    ShareLink(item: shareURL) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }

                    Button {
                        UIPasteboard.general.url = shareURL
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var createLinkForm: some View {
        DatePicker(
            "Unfalldatum",
            selection: $accidentDate,
            displayedComponents: .date
        )

        TextField("Kundenname (optional)", text: $customerName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(false)
            .focused($focusedField, equals: .customerName)
            .submitLabel(.next)
            .onSubmit { focusedField = .notes }

        TextField("Notiz intern (optional)", text: $notes, axis: .vertical)
            .lineLimit(2...4)
            .focused($focusedField, equals: .notes)
            .submitLabel(.done)
            .onSubmit { dismissSigningKeyboard() }

        Button {
            dismissSigningKeyboard()
            _Concurrency.Task { await generateLink() }
        } label: {
            HStack {
                Spacer()
                if isGenerating {
                    ProgressView()
                } else {
                    Label("Einmal-Link erstellen", systemImage: "link")
                }
                Spacer()
            }
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating)
    }

    @ViewBuilder
    private func generatedLinkRows(_ generatedLink: DocumentSigningLinkResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(generatedLink.url.absoluteString)
                .font(.footnote)
                .textSelection(.enabled)

            if let expiresAt = generatedLink.expiresAt {
                Text("Gültig bis: \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        ShareLink(item: generatedLink.url) {
            Label("Link teilen", systemImage: "square.and.arrow.up")
        }

        Button {
            UIPasteboard.general.url = generatedLink.url
        } label: {
            Label("Link kopieren", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderless)

        if let matching = signedLinks.first(where: { $0.id == generatedLink.id }),
           matching.canOpenSignedPDF {
            Button {
                _Concurrency.Task { await openSignedPDF(for: matching) }
            } label: {
                Label("Signiertes PDF öffnen", systemImage: "doc.richtext.fill")
            }
            .disabled(openingPDFToken == generatedLink.id)
        }
    }

    private func statusBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func openSignedPDF(for link: DocumentSigningLinkStatus) async {
        await openSignedPDF(for: link.id, title: link.displayName, fileName: link.localPDFFileName)
    }

    private func openSignedPDF(for token: String, title: String, fileName: String) async {
        await MainActor.run {
            openingPDFToken = token
            pdfErrorMessage = nil
        }

        defer {
            _Concurrency.Task { @MainActor in
                openingPDFToken = nil
            }
        }

        do {
            let localURL = try await DocumentSigningLinkService.downloadSignedPDF(
                linkToken: token,
                fileName: fileName
            )

            await MainActor.run {
                previewPDFTitle = title
                previewPDFURL = localURL
            }
        } catch {
            await MainActor.run {
                pdfErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteLinks(
        at offsets: IndexSet,
        in source: [DocumentSigningLinkStatus]
    ) async {
        let tokens = offsets.compactMap { index in
            source.indices.contains(index) ? source[index].id : nil
        }

        for token in tokens {
            do {
                try await statusModel.deleteLink(token: token)
                if generatedLink?.id == token {
                    await MainActor.run { generatedLink = nil }
                }
            } catch {
                await MainActor.run {
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func generateLink() async {
        await MainActor.run {
            isGenerating = true
            errorMessage = nil
        }

        defer {
            _Concurrency.Task { @MainActor in
                isGenerating = false
            }
        }

        do {
            let result = try await DocumentSigningLinkService.createRemoteSigningLink(
                document: document,
                sourcePDFURL: sourcePDFURL,
                accidentDate: accidentDate,
                customerName: customerName,
                notes: notes
            )

            await MainActor.run {
                generatedLink = result
                showCreateLinkSection = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SignedPDFViewerSheet: View {
    let fileURL: URL
    let title: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            PDFPreview(url: fileURL)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schließen", action: onClose)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: fileURL) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}
