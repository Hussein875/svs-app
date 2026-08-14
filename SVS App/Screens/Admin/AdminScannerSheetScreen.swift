//
//  AdminScannerSheetScreen.swift
//  SVS App
//

import SwiftUI
import UIKit

struct ScannerSheetEntry: Identifiable, Hashable {
    let rowNumber: Int
    let entry: String
    let worker: String
    let status: String
    let caseNumber: Int?
    let year2: String?

    var id: Int { rowNumber }

    init?(dictionary: [String: Any]) {
        guard let rowNumber = dictionary["rowNumber"] as? Int else { return nil }

        let entry = String(dictionary["entry"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let worker = String(dictionary["worker"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = String(dictionary["status"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !entry.isEmpty else { return nil }

        self.rowNumber = rowNumber
        self.entry = entry
        self.worker = worker
        self.status = status
        self.caseNumber = dictionary["caseNumber"] as? Int
        self.year2 = (dictionary["year2"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AdminScannerSheetScreen: View {
    @EnvironmentObject var appState: AppState

    @State private var entries: [ScannerSheetEntry] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var pendingDelete: ScannerSheetEntry?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    private let sheetURL = URL(
        string: "https://docs.google.com/spreadsheets/d/10mfm9SVVDiWcxnfK2QuUCj3msaVFBQIQx34NnPlUEo4/edit"
    )!

    private let sheetsApiEnableURL = URL(
        string: "https://console.cloud.google.com/apis/library/sheets.googleapis.com?project=svs-app-864ed"
    )!

    private let serviceAccountEmail = "svs-app-864ed@appspot.gserviceaccount.com"

    private var filteredEntries: [ScannerSheetEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.entry.localizedCaseInsensitiveContains(query)
                || entry.worker.localizedCaseInsensitiveContains(query)
                || entry.status.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView("Dashboard wird geladen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        setupCard
                            .padding(.horizontal, 18)

                        Image(systemName: "tablecells")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(entries.isEmpty ? "Keine Einträge" : "Keine Treffer")
                            .font(.title3.weight(.semibold))
                        Text(entries.isEmpty
                             ? "Die Dashboard-Tabelle ist leer."
                             : "Für die Suche wurden keine Einträge gefunden.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
                .refreshable {
                    await loadEntries()
                }
            } else {
                List {
                    Section {
                        setupCard
                            .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    Section(header: Text("Einträge (\(filteredEntries.count))").textCase(nil)) {
                        ForEach(filteredEntries) { entry in
                            entryRow(entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = entry
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadEntries()
                }
            }
        }
        .navigationTitle("Dashboard-Verwaltung")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Fall, Sachbearbeiter oder Status")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: sheetURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .accessibilityLabel("In Google Sheets öffnen")
            }
        }
        .alert("Eintrag löschen?", isPresented: $showDeleteConfirmation, presenting: pendingDelete) { entry in
            Button("Löschen", role: .destructive) {
                _Concurrency.Task {
                    await deleteEntry(entry)
                }
            }
            Button("Abbrechen", role: .cancel) {
                pendingDelete = nil
            }
        } message: { entry in
            Text(deleteMessage(for: entry))
        }
        .alert("Löschen fehlgeschlagen", isPresented: deleteErrorBinding) {
            if let sheetsApiEnableURL {
                Button("Google Sheets API aktivieren") {
                    UIApplication.shared.open(sheetsApiEnableURL)
                }
            }
            Button("Service-Account kopieren") {
                UIPasteboard.general.string = serviceAccountEmail
                appState.showToast(.success, "E-Mail kopiert")
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .task {
            await loadEntries()
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dashboard-Verwaltung")
                .font(.headline)

            Text("Dieselbe Tabelle wie im Dashboard. Nach dem Löschen wird die nächste Gutachten-Nummer neu berechnet. Drive-Ordner bleiben erhalten.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Löschen einrichten (einmalig)")
                    .font(.subheadline.weight(.semibold))

                if let sheetsApiEnableURL {
                    Link(destination: sheetsApiEnableURL) {
                        Label("1. Google Sheets API aktivieren", systemImage: "link")
                            .font(.subheadline)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Text("2. Sheet teilen mit:")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Button {
                        UIPasteboard.general.string = serviceAccountEmail
                        appState.showToast(.success, "Service-Account kopiert")
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(serviceAccountEmail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func entryRow(_ entry: ScannerSheetEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.entry)
                    .font(.headline)
                if !entry.worker.isEmpty {
                    Text(entry.worker)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(statusLabel(for: entry.status))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(statusColor(for: entry.status).opacity(0.16))
                )
                .foregroundColor(statusColor(for: entry.status))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = entry
                showDeleteConfirmation = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func deleteMessage(for entry: ScannerSheetEntry) -> String {
        "«\(entry.entry)» aus der Dashboard-Tabelle entfernen? Drive-Ordner bleiben erhalten."
    }

    private func statusLabel(for rawStatus: String) -> String {
        let status = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.isEmpty { return "Offen" }
        if status.range(
            of: #"^geprüft\s*(o|1|2|hj|hk)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return "Geprüft"
        }
        if status.localizedCaseInsensitiveContains("unvollständig") {
            return "Unvollständig"
        }
        if status.localizedCaseInsensitiveContains("vollständig") {
            return "Zu prüfen"
        }
        if status.localizedCaseInsensitiveContains("versendet") {
            return "Versendet"
        }
        return status
    }

    private func statusColor(for rawStatus: String) -> Color {
        let status = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status.hasPrefix("versendet") { return .secondary }
        if status.contains("unvollständig") { return .orange }
        if status.contains("vollständig") { return .blue }
        if status.range(
            of: #"^geprüft\s*(o|1|2|hj|hk)$"#,
            options: .regularExpression
        ) != nil {
            return .green
        }
        return .primary
    }

    @MainActor
    private func loadEntries() async {
        isLoading = true
        defer { isLoading = false }

        entries = await appState.adminFetchScannerSheetEntries()
    }

    @MainActor
    private func deleteEntry(_ entry: ScannerSheetEntry) async {
        let errorMessage = await appState.adminDeleteScannerSheetEntry(entry)
        pendingDelete = nil
        showDeleteConfirmation = false

        if let errorMessage {
            deleteErrorMessage = errorMessage
            return
        }

        entries.removeAll { $0.rowNumber == entry.rowNumber }
        await loadEntries()
    }
}

#Preview {
    NavigationStack {
        AdminScannerSheetScreen()
            .environmentObject(AppState())
    }
}
