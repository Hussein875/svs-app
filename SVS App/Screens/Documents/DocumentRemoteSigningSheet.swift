//
//  DocumentRemoteSigningSheet.swift
//  SVS App
//

import SwiftUI
import UIKit

struct DocumentRemoteSigningSheet: View {
    let document: CompanyDocument
    let sourcePDFURL: URL

    @Environment(\.dismiss) private var dismiss
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
    @State private var previewLink: DocumentSigningLinkStatus?
    @State private var labelAdjustmentLink: DocumentSigningLinkStatus?
    @State private var labelAdjustmentPDFURL: URL?
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
                .navigationTitle("Kundenunterschrift")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { signingToolbar }
        }
        .onAppear(perform: handleAppear)
        .onDisappear { statusModel.stop() }
        .refreshable { await statusModel.refresh(documentId: document.id) }
        .fullScreenCover(isPresented: labelAdjustmentPresented, content: labelAdjustmentCover)
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
            Button("Schließen") { dismiss() }
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

    private var labelAdjustmentPresented: Binding<Bool> {
        Binding(
            get: { labelAdjustmentPDFURL != nil && labelAdjustmentLink != nil },
            set: { isPresented in
                if !isPresented {
                    labelAdjustmentPDFURL = nil
                    labelAdjustmentLink = nil
                }
            }
        )
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
    private func labelAdjustmentCover() -> some View {
        if let labelAdjustmentPDFURL, let labelAdjustmentLink {
            SignedDocumentLabelAdjustmentView(
                fileURL: labelAdjustmentPDFURL,
                link: labelAdjustmentLink,
                document: document,
                onCancel: {
                    self.labelAdjustmentPDFURL = nil
                    self.labelAdjustmentLink = nil
                },
                onSaved: { updatedURL in
                    try? DocumentSigningLinkService.replaceCachedSignedPDF(
                        linkToken: labelAdjustmentLink.id,
                        sourceURL: updatedURL
                    )
                    self.labelAdjustmentPDFURL = nil
                    self.labelAdjustmentLink = nil
                    _Concurrency.Task {
                        await statusModel.refresh(documentId: document.id)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func pdfPreviewCover() -> some View {
        if let fileURL = previewPDFURL {
            SignedPDFViewerSheet(
                fileURL: fileURL,
                title: previewPDFTitle,
                link: previewLink,
                document: document,
                onUpdated: { updatedURL in
                    self.previewPDFURL = updatedURL
                },
                onClose: {
                    self.previewPDFURL = nil
                    self.previewLink = nil
                }
            )
        }
    }

    private func handleAppear() {
        statusModel.start(documentId: document.id)
        showCreateLinkSection = signedLinks.isEmpty
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

                Button {
                    _Concurrency.Task { await openLabelAdjustment(for: link) }
                } label: {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(openingPDFToken == link.id || (link.isSigned && !link.canOpenSignedPDF))
                .accessibilityLabel("Textpositionen anpassen")

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

        TextField("Notiz intern (optional)", text: $notes, axis: .vertical)
            .lineLimit(2...4)

        Button {
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
                previewLink = statusModel.links.first { $0.id == token }
            }
        } catch {
            await MainActor.run {
                pdfErrorMessage = error.localizedDescription
            }
        }
    }

    private func openLabelAdjustment(for link: DocumentSigningLinkStatus) async {
        await MainActor.run {
            openingPDFToken = link.id
            pdfErrorMessage = nil
        }

        defer {
            _Concurrency.Task { @MainActor in
                openingPDFToken = nil
            }
        }

        do {
            let localURL = try await DocumentSigningLinkService.downloadSignedPDF(
                linkToken: link.id,
                fileName: link.localPDFFileName
            )

            await MainActor.run {
                labelAdjustmentLink = link
                labelAdjustmentPDFURL = localURL
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

private struct RemoteSignedLabelFieldState: Identifiable {
    let id: String
    let label: String
    let text: String
    let erasePlacement: PDFSignaturePlacement
    var placement: NormalizedTextPlacement

    var drawPlacement: PDFSignaturePlacement {
        placement.pdfPlacement(pageIndex: erasePlacement.pageIndex)
    }
}

private struct SignedPDFViewerSheet: View {
    let fileURL: URL
    let title: String
    let link: DocumentSigningLinkStatus?
    let document: CompanyDocument
    let onUpdated: (URL) -> Void
    let onClose: () -> Void

    @State private var activeFileURL: URL
    @State private var showLabelAdjustment = false
    @State private var saveErrorMessage: String?

    init(
        fileURL: URL,
        title: String,
        link: DocumentSigningLinkStatus?,
        document: CompanyDocument,
        onUpdated: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.title = title
        self.link = link
        self.document = document
        self.onUpdated = onUpdated
        self.onClose = onClose
        _activeFileURL = State(initialValue: fileURL)
    }

    var body: some View {
        NavigationStack {
            PDFPreview(url: activeFileURL)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schließen", action: onClose)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if link != nil {
                            Button {
                                showLabelAdjustment = true
                            } label: {
                                Label("Positionen", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            }
                        }
                        ShareLink(item: activeFileURL) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .fullScreenCover(isPresented: $showLabelAdjustment) {
                    if let link {
                        SignedDocumentLabelAdjustmentView(
                            fileURL: activeFileURL,
                            link: link,
                            document: document,
                            onCancel: { showLabelAdjustment = false },
                            onSaved: { updatedURL in
                                activeFileURL = updatedURL
                                onUpdated(updatedURL)
                                showLabelAdjustment = false
                            }
                        )
                    }
                }
                .alert(
                    "Speichern fehlgeschlagen",
                    isPresented: Binding(
                        get: { saveErrorMessage != nil },
                        set: { if !$0 { saveErrorMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { saveErrorMessage = nil }
                } message: {
                    Text(saveErrorMessage ?? "")
                }
        }
    }
}

private struct SignedDocumentLabelAdjustmentView: View {
    let fileURL: URL
    let link: DocumentSigningLinkStatus
    let document: CompanyDocument
    let onCancel: () -> Void
    let onSaved: (URL) -> Void

    @State private var fieldStates: [RemoteSignedLabelFieldState] = []
    @State private var signaturePlacement = NormalizedSignaturePlacement(
        from: PDFSignaturePlacement(pageIndex: 0, x: 0, y: 0, width: 0.1, height: 0.1)
    )
    @State private var signatureErasePlacement = PDFSignaturePlacement(
        pageIndex: 0, x: 0, y: 0, width: 0.1, height: 0.1
    )
    @State private var signaturePreviewImage: UIImage?
    @State private var pageImage: UIImage?
    @State private var textDragOffsets: [String: CGSize] = [:]
    @State private var signatureDragOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var pageIndex: Int {
        document.signaturePlacement.pageIndex
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ziehe Unfalldatum, Datum und Unterschrift auf die richtige Stelle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                GeometryReader { geometry in
                    ZStack {
                        Color(.secondarySystemBackground)

                        if let pageImage,
                           let layout = labelPageLayout(in: geometry.size, imageSize: pageImage.size) {
                            Image(uiImage: pageImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: layout.size.width, height: layout.size.height)
                                .position(x: layout.midX, y: layout.midY)

                            ForEach($fieldStates) { $state in
                                labelTextOverlay(state: $state, layout: layout)
                            }

                            signatureOverlay(layout: layout)
                        } else {
                            ProgressView("PDF wird geladen …")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 18)
                }

                Text("Orange = Texte, Blau = Unterschrift. Nach dem Speichern wird das PDF aktualisiert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Positionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        _Concurrency.Task { await saveAdjustments() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .onAppear {
                loadAdjustmentState()
            }
            .alert(
                "Anpassung fehlgeschlagen",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func labelTextOverlay(
        state: Binding<RemoteSignedLabelFieldState>,
        layout: LabelPageLayout
    ) -> some View {
        let fieldID = state.wrappedValue.id
        let dragOffset = textDragOffsets[fieldID] ?? .zero
        let box = labelOverlayBox(
            placement: state.wrappedValue.placement.clamped(),
            in: layout,
            extraOffset: dragOffset
        )

        VStack(spacing: 2) {
            Text(state.wrappedValue.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(state.wrappedValue.text)
                .font(.system(size: max(5, min(box.height * 0.42, 10)), weight: .medium))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(width: box.width, height: box.height, alignment: .leading)
        .position(x: box.midX, y: box.midY)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
        }
        .gesture(
            DragGesture()
                .onChanged { textDragOffsets[fieldID] = $0.translation }
                .onEnded { value in
                    state.wrappedValue.placement.x += value.translation.width / layout.size.width
                    state.wrappedValue.placement.y += value.translation.height / layout.size.height
                    state.wrappedValue.placement = state.wrappedValue.placement.clamped()
                    textDragOffsets[fieldID] = .zero
                }
        )
    }

    @ViewBuilder
    private func signatureOverlay(layout: LabelPageLayout) -> some View {
        let box = labelSignatureBox(
            placement: signaturePlacement.clamped(),
            in: layout,
            extraOffset: signatureDragOffset
        )

        Group {
            if let signaturePreviewImage {
                Image(uiImage: signaturePreviewImage)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 4) {
                    Text("Unterschrift")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Image(systemName: "signature")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
        }
        .frame(width: box.width, height: box.height)
        .position(x: box.midX, y: box.midY)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
        }
        .gesture(
            DragGesture()
                .onChanged { signatureDragOffset = $0.translation }
                .onEnded { value in
                    signaturePlacement.x += value.translation.width / layout.size.width
                    signaturePlacement.y += value.translation.height / layout.size.height
                    signaturePlacement = signaturePlacement.clamped()
                    signatureDragOffset = .zero
                }
        )
    }

    private func loadAdjustmentState() {
        fieldStates = buildFieldStates()

        let storedSignature = link.placement(
            for: "signature",
            defaultPlacement: document.signaturePlacement
        )
        signatureErasePlacement = storedSignature
        signaturePlacement = NormalizedSignaturePlacement(from: storedSignature)

        pageImage = PDFSignatureService.renderPageImage(
            sourceURL: fileURL,
            pageIndex: pageIndex
        )
        signaturePreviewImage = PDFSignatureService.cropPageRegion(
            sourceURL: fileURL,
            pageIndex: pageIndex,
            placement: storedSignature
        )
    }

    private func buildFieldStates() -> [RemoteSignedLabelFieldState] {
        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ raw: String?) -> Date? {
            guard let raw, !raw.isEmpty else { return nil }
            if let date = isoParser.date(from: raw) { return date }
            isoParser.formatOptions = [.withInternetDateTime]
            return isoParser.date(from: raw)
        }

        let signingDate = parseDate(link.signingDateIso) ?? link.signedAt ?? Date()
        let accidentDate = parseDate(link.accidentDateIso) ?? Date()

        return document.textFields.compactMap { field in
            let storedPlacement = link.placement(
                for: field.id,
                defaultPlacement: field.defaultPlacement
            )
            let text: String
            switch field.kind {
            case .signingDate:
                text = field.renderedText(date: signingDate, customText: "", secondaryText: "")
            case .accidentDate:
                text = field.renderedText(date: accidentDate, customText: "", secondaryText: "")
            case .freeText, .partyPair:
                return nil
            }
            guard !text.isEmpty else { return nil }

            return RemoteSignedLabelFieldState(
                id: field.id,
                label: field.label,
                text: text,
                erasePlacement: storedPlacement,
                placement: NormalizedTextPlacement(from: storedPlacement)
            )
        }
    }

    private func saveAdjustments() async {
        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }

        defer {
            _Concurrency.Task { @MainActor in
                isSaving = false
            }
        }

        do {
            let relocations = fieldStates.map {
                PDFTextRelocation(
                    text: $0.text,
                    erasePlacement: $0.erasePlacement,
                    drawPlacement: $0.drawPlacement
                )
            }

            let signatureDrawPlacement = signaturePlacement.pdfPlacement(
                pageIndex: signatureErasePlacement.pageIndex
            )
            let signatureRelocation = PDFSignatureRelocation(
                erasePlacement: signatureErasePlacement,
                drawPlacement: signatureDrawPlacement
            )

            let adjustedURL = try PDFSignatureService.relocateTextOverlaysOnSignedPDF(
                signedPDFURL: fileURL,
                relocations: relocations,
                signatureRelocation: signatureRelocation,
                outputBaseName: document.resourceName
            )

            var placements: [String: PDFSignaturePlacement] = [:]
            for state in fieldStates {
                placements[state.id] = state.drawPlacement
            }
            placements["signature"] = signatureDrawPlacement

            try await DocumentSigningLinkService.uploadAdjustedSignedPDF(
                linkToken: link.id,
                pdfURL: adjustedURL,
                labelPlacements: placements
            )

            await MainActor.run {
                onSaved(adjustedURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func labelOverlayBox(
        placement: NormalizedTextPlacement,
        in layout: LabelPageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        labelBox(
            x: placement.x,
            y: placement.y,
            width: placement.width,
            height: placement.height,
            in: layout,
            extraOffset: extraOffset
        )
    }

    private func labelSignatureBox(
        placement: NormalizedSignaturePlacement,
        in layout: LabelPageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        labelBox(
            x: placement.x,
            y: placement.y,
            width: placement.width,
            height: placement.height,
            in: layout,
            extraOffset: extraOffset
        )
    }

    private func labelBox(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        in layout: LabelPageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        let boxWidth = layout.size.width * width
        let boxHeight = layout.size.height * height
        let originX = layout.origin.x + layout.size.width * x + extraOffset.width
        let originY = layout.origin.y + layout.size.height * y + extraOffset.height
        return CGRect(x: originX, y: originY, width: boxWidth, height: boxHeight)
    }

    private func labelPageLayout(in containerSize: CGSize, imageSize: CGSize) -> LabelPageLayout? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2
        )

        return LabelPageLayout(origin: origin, size: size)
    }
}

private struct LabelPageLayout {
    let origin: CGPoint
    let size: CGSize

    var midX: CGFloat { origin.x + size.width / 2 }
    var midY: CGFloat { origin.y + size.height / 2 }
}
