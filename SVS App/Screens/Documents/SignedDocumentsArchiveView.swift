//
//  SignedDocumentsArchiveView.swift
//  SVS App
//

import SwiftUI

struct SignedDocumentsArchiveView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var statusModel = DocumentSigningStatusViewModel()
    @State private var localRecords: [LocalSignedDocumentRecord] = []
    @State private var selectedEntry: SignedArchiveSelection?
    @State private var entriesPendingDeletion: [SignedArchiveEntry] = []
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?

    private var visibleSignedLinks: [DocumentSigningLinkStatus] {
        guard let user = appState.currentUser else { return [] }
        return statusModel.links
            .filter(\.isSigned)
            .filter { user.canViewLawyerPower(id: $0.documentId) }
    }

    private var visibleLocalRecords: [LocalSignedDocumentRecord] {
        guard let user = appState.currentUser else { return [] }
        return localRecords.filter { record in
            guard let document = CompanyDocumentsCatalog.items.first(where: { $0.id == record.documentId }) else {
                return true
            }
            if document.section == .internalDocuments {
                return true
            }
            return user.canViewLawyerPower(id: record.documentId)
        }
    }

    private var archiveEntries: [SignedArchiveEntry] {
        let remote = visibleSignedLinks.map(SignedArchiveEntry.fromRemote)
        let local = visibleLocalRecords.map(SignedArchiveEntry.fromLocal)
        return (remote + local).sorted {
            ($0.signedAt ?? .distantPast) > ($1.signedAt ?? .distantPast)
        }
    }

    private var isLoadingInitial: Bool {
        statusModel.isLoading && statusModel.links.isEmpty && localRecords.isEmpty
    }

    var body: some View {
        List {
            if isLoadingInitial {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Wird geladen …")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let loadError = statusModel.lastError, archiveEntries.isEmpty, !isLoadingInitial {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            if archiveEntries.isEmpty && !isLoadingInitial && statusModel.lastError == nil {
                Section {
                    ContentUnavailableView(
                        "Noch keine Unterschriften",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Online oder in der App unterschriebene Dokumente erscheinen hier.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !archiveEntries.isEmpty {
                Section {
                    ForEach(archiveEntries) { entry in
                        archiveRow(entry)
                    }
                    .onDelete(perform: deleteEntries)
                } footer: {
                    Text("Nach links wischen, Bearbeiten antippen oder gedrückt halten zum Löschen.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Signierte Dokumente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !archiveEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .navigationDestination(item: $selectedEntry) { selection in
            SignedArchiveDetailView(selection: selection)
        }
        .onAppear {
            reloadLocalRecords()
            statusModel.startAll()
        }
        .onDisappear {
            statusModel.stop()
        }
        .refreshable {
            reloadLocalRecords()
            await statusModel.refreshAll()
        }
        .alert("Dokument löschen?", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {
                entriesPendingDeletion = []
            }
            Button("Löschen", role: .destructive) {
                let entries = entriesPendingDeletion
                entriesPendingDeletion = []
                if entries.contains(where: { $0.selection == selectedEntry }) {
                    selectedEntry = nil
                }
                deleteEntries(entries)
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert("Löschen fehlgeschlagen", isPresented: deleteErrorPresented) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func archiveRow(_ entry: SignedArchiveEntry) -> some View {
        SignedArchiveEntryRow(entry: entry)
            .contentShape(Rectangle())
            .onTapGesture {
                guard entry.canOpenPDF else { return }
                selectedEntry = entry.selection
            }
            .contextMenu {
                if entry.canOpenPDF {
                    Button {
                        selectedEntry = entry.selection
                    } label: {
                        Label("Öffnen", systemImage: "doc.richtext")
                    }
                }

                Button(role: .destructive) {
                    requestDelete([entry])
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
    }

    private var deleteConfirmationMessage: String {
        if entriesPendingDeletion.count == 1,
           let entry = entriesPendingDeletion.first {
            return "„\(entry.title)“ wird dauerhaft entfernt."
        }
        return "\(entriesPendingDeletion.count) Dokumente werden dauerhaft entfernt."
    }

    private func requestDelete(_ entries: [SignedArchiveEntry]) {
        guard !entries.isEmpty else { return }
        entriesPendingDeletion = entries
        showDeleteConfirm = true
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )
    }

    private func reloadLocalRecords() {
        localRecords = LocalSignedDocumentArchive.allRecords()
    }

    private func deleteEntries(at offsets: IndexSet) {
        let entries = offsets.compactMap { index in
            archiveEntries.indices.contains(index) ? archiveEntries[index] : nil
        }
        requestDelete(entries)
    }

    private func deleteEntries(_ entries: [SignedArchiveEntry]) {
        guard !entries.isEmpty else { return }

        _Concurrency.Task {
            for entry in entries {
                do {
                    switch entry.selection {
                    case .local(let record):
                        try LocalSignedDocumentArchive.delete(record: record)
                    case .remote(let link):
                        try await statusModel.deleteLink(token: link.id)
                    }

                    await MainActor.run {
                        if selectedEntry == entry.selection {
                            selectedEntry = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        deleteErrorMessage = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                reloadLocalRecords()
            }
        }
    }
}
