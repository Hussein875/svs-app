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

    private enum RemoteSigningTab: String, CaseIterable {
        case links = "Links"
        case signed = "Signiert"
    }

    let document: CompanyDocument
    let sourcePDFURL: URL

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: SigningFormField?
    @StateObject private var statusModel = DocumentSigningStatusViewModel()

    @State private var selectedTab: RemoteSigningTab = .links
    @State private var selectedSignedLink: DocumentSigningLinkStatus?
    @State private var accidentDate = Date()
    @State private var customerName = ""
    @State private var notes = ""
    @State private var isGenerating = false
    @State private var generatedLink: DocumentSigningLinkResult?
    @State private var errorMessage: String?
    @State private var showCreateLinkSection = true
    @State private var deleteErrorMessage: String?
    @State private var linksPendingDeletion: [DocumentSigningLinkStatus] = []
    @State private var showDeleteLinkConfirm = false

    private var signedLinks: [DocumentSigningLinkStatus] {
        statusModel.links.filter(\.isSigned)
    }

    private var openLinks: [DocumentSigningLinkStatus] {
        statusModel.links.filter { !$0.isSigned }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Bereich", selection: $selectedTab) {
                    ForEach(RemoteSigningTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Group {
                    switch selectedTab {
                    case .signed:
                        signedDocumentsTab
                    case .links:
                        linksTab
                    }
                }
            }
            .navigationTitle("Kundenunterschrift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { signingToolbar }
            .navigationDestination(item: $selectedSignedLink) { link in
                SignedDocumentDetailView(link: link)
            }
        }
        .onAppear {
            statusModel.start(documentId: document.id)
        }
        .onDisappear { statusModel.stop() }
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
        .alert(deleteLinkAlertTitle, isPresented: $showDeleteLinkConfirm) {
            Button("Abbrechen", role: .cancel) {
                linksPendingDeletion = []
            }
            Button("Löschen", role: .destructive) {
                let links = linksPendingDeletion
                linksPendingDeletion = []
                _Concurrency.Task { await performDeleteLinks(links) }
            }
        } message: {
            Text(deleteLinkAlertMessage)
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

    @ViewBuilder
    private var signedDocumentsTab: some View {
        List {
            if statusModel.isLoading && statusModel.links.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Signierte Dokumente werden geladen …")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let loadError = statusModel.lastError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            if signedLinks.isEmpty && !statusModel.isLoading && statusModel.lastError == nil {
                Section {
                    ContentUnavailableView(
                        "Noch keine Unterschriften",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Sobald ein Kunde online unterschreibt, erscheint das PDF hier.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !signedLinks.isEmpty {
                Section {
                    ForEach(signedLinks) { link in
                        Button {
                            if link.canOpenSignedPDF {
                                selectedSignedLink = link
                            }
                        } label: {
                            SignedDocumentRow(link: link)
                        }
                        .buttonStyle(.plain)
                        .disabled(!link.canOpenSignedPDF)
                    }
                    .onDelete { offsets in
                        requestDeleteLinks(at: offsets, in: signedLinks)
                    }
                } header: {
                    HStack {
                        Text("Signierte Dokumente")
                        Spacer()
                        if statusModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                } footer: {
                    Text("Tippe auf einen Eintrag, um das PDF in voller Ansicht zu öffnen. Nach links wischen zum Löschen.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await statusModel.refresh(documentId: document.id) }
    }

    @ViewBuilder
    private var linksTab: some View {
        List {
            if !openLinks.isEmpty {
                Section {
                    ForEach(openLinks) { link in
                        openLinkRow(link)
                    }
                    .onDelete { offsets in
                        requestDeleteLinks(at: offsets, in: openLinks)
                    }
                } header: {
                    Text("Offene Links")
                } footer: {
                    Text("Noch nicht unterschriebene Links kannst du nach links wischen, um sie zu entfernen.")
                }
            }

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

            if let generatedLink {
                Section("Zuletzt erstellter Link") {
                    generatedLinkRows(generatedLink)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await statusModel.refresh(documentId: document.id) }
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
                selectedTab = .signed
                selectedSignedLink = matching
            } label: {
                Label("Signiertes PDF öffnen", systemImage: "doc.richtext.fill")
            }
        }
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

    private func dismissSigningKeyboard() {
        focusedField = nil
        hideKeyboard()
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

    private var deleteLinkAlertTitle: String {
        linksPendingDeletion.allSatisfy(\.isSigned) ? "Signiertes Dokument löschen?" : "Link löschen?"
    }

    private var deleteLinkAlertMessage: String {
        if linksPendingDeletion.count == 1,
           let link = linksPendingDeletion.first {
            if link.isSigned {
                return "„\(link.displayName)“ wird dauerhaft entfernt."
            }
            return "Der Link für „\(link.displayName)“ wird dauerhaft entfernt."
        }
        return "\(linksPendingDeletion.count) Einträge werden dauerhaft entfernt."
    }

    private func requestDeleteLinks(
        at offsets: IndexSet,
        in source: [DocumentSigningLinkStatus]
    ) {
        let links = offsets.compactMap { index in
            source.indices.contains(index) ? source[index] : nil
        }
        guard !links.isEmpty else { return }
        linksPendingDeletion = links
        showDeleteLinkConfirm = true
    }

    private func performDeleteLinks(_ links: [DocumentSigningLinkStatus]) async {
        for link in links {
            let token = link.id
            do {
                try await statusModel.deleteLink(token: token)
                if generatedLink?.id == token {
                    await MainActor.run { generatedLink = nil }
                }
                if selectedSignedLink?.id == token {
                    await MainActor.run { selectedSignedLink = nil }
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
                selectedTab = .links
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}
