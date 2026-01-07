//
//  MenuView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine

    struct MenuView: View {
        @EnvironmentObject var appState: AppState
        @Environment(\.openURL) private var openURL
        @State private var showSignOutConfirm: Bool = false
        @State private var isSigningOut: Bool = false
        @State private var systemStatus: SystemStatusSnapshot = .empty
        @State private var isCheckingSystemStatus: Bool = false
        
        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    
                    List {
                        Section(header: Text("Profil")) {
                            if appState.currentUser != nil {
                                NavigationLink {
                                    EditMyProfileView()
                                        .environmentObject(appState)
                                } label: {
                                    Label("Profil bearbeiten", systemImage: "person.crop.circle")
                                }
                            } else {
                                Label("Profil bearbeiten", systemImage: "person.crop.circle")
                                    .foregroundColor(.secondary)
                            }
                        }
/**
                         Section(header: Text("Support")) {
                            Button {
                                if let url = URL(string: "https://wa.me/4915141211189") {
                                    openURL(url)
                                }
                            } label: {
                                Label("Support kontaktieren (WhatsApp)", systemImage: "message")
                            }
                        }

                        if appState.currentUser?.role == .admin {
                            Section(header: Text("Admin")) {
                                SystemStatusTile(
                                    snapshot: systemStatus,
                                    isLoading: isCheckingSystemStatus,
                                    onRefresh: {
                                        _Concurrency.Task { await runSystemStatusCheck() }
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                                Button {
                                    appState.reloadDataNow()
                                } label: {
                                    Label("Daten neu laden", systemImage: "arrow.clockwise")
                                }
                            }
                        }
 */

                        Section(header: Text("Benutzer")) {
                            if let user = appState.currentUser {
                                LabeledContent("Eingeloggt als") {
                                    Text(user.name)
                                        .foregroundColor(.accentColor)
                                }

                                LabeledContent("Rolle") {
                                    Text(user.role.rawValue)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Nicht eingeloggt")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Section(header: Text("App-Info")) {
                            LabeledContent("Version") {
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                                    .foregroundColor(.secondary)
                            }
                            LabeledContent("Build") {
                                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–")
                                    .foregroundColor(.secondary)
                            }
                            LabeledContent("Entwickelt für") {
                                Text("SV Souleiman")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Section {
                            VStack(spacing: 10) {
                                if appState.currentUser != nil {
                                    Button {
                                        showSignOutConfirm = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                            Text("Ausloggen")
                                        }
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)
                                }

                                VStack(spacing: 6) {
                                    Text("SVS App")
                                        .font(.footnote.weight(.semibold))
                                    Text("© \(Calendar.current.component(.year, from: Date())) Sachverständigenbüro Souleiman")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                    .alert("Wirklich ausloggen?", isPresented: $showSignOutConfirm) {
                        Button("Ausloggen", role: .destructive) {
                            guard !isSigningOut else { return }
                            isSigningOut = true

                            // 1) Firebase Auth abmelden
                            do {
                                try appState.auth.signOut()
                            } catch {
                                appState.uiErrorMessage = "Abmeldung fehlgeschlagen: \(error.localizedDescription)"
                                isSigningOut = false
                                return
                            }

                            // 2) Lokale Session/State bereinigen
                            appState.signOut()
                            isSigningOut = false
                        }
                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text("Sie werden in der App abgemeldet.")
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Menü")
                .navigationBarTitleDisplayMode(.inline)
                // Removed logout toolbar button from navigation bar
                .task {
                    if appState.currentUser?.role == .admin {
                        await runSystemStatusCheck()
                    }
                }
            }
        }

        private func runSystemStatusCheck() async {
            guard !isCheckingSystemStatus else { return }
            isCheckingSystemStatus = true

            let started = Date()

            async let firestore = SystemHealthChecks.checkFirestore()
            async let functions = SystemHealthChecks.checkFunctions()
            async let dashboard = SystemHealthChecks.checkDashboard(urlString: "https://dashboard.sv-souleiman.de")

            let (fs, fn, db) = await (firestore, functions, dashboard)

            systemStatus = SystemStatusSnapshot(
                checkedAt: Date(),
                durationMs: Int(Date().timeIntervalSince(started) * 1000),
                firestore: fs,
                functions: fn,
                dashboard: db
            )

            isCheckingSystemStatus = false
        }
    }

// MARK: - Admin helpers (Menu)
extension AppState {
    /// Best-effort refresh. If you already use snapshot listeners, this will force a UI refresh
    /// and can be extended later to re-register listeners.
    func reloadDataNow() {
        // If your AppState already has explicit reload methods, call them here.
        // We keep this safe and non-breaking.
        self.objectWillChange.send()
    }
}

private func germanColorName(_ key: String) -> String {
    switch key {
    case "blue": return "Blau"
    case "indigo": return "Indigo"
    case "purple": return "Lila"
    case "pink": return "Pink"
    case "red": return "Rot"
    case "orange": return "Orange"
    case "yellow": return "Gelb"
    case "green": return "Grün"
    case "teal": return "Türkis"
    case "cyan": return "Cyan"
    case "gray": return "Grau"
    default: return key.capitalized
    }
}

private struct EditMyProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var colorName: String = "blue"

    private let availableColors: [(name: String, color: Color)] = [
        ("blue", .blue),
        ("indigo", .indigo),
        ("purple", .purple),
        ("pink", .pink),
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green", .green),
        ("teal", .teal),
        ("cyan", .cyan),
        ("gray", .gray)
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appState.currentUser != nil
    }

    var body: some View {
        Form {
            Section(header: Text("Name")) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: $colorName) {
                    ForEach(availableColors, id: \.name) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 12, height: 12)
                            Text(germanColorName(item.name))
                        }
                        .tag(item.name)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vorschau")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Circle()
                            .fill(availableColors.first(where: { $0.name == colorName })?.color ?? .blue)
                            .frame(width: 12, height: 12)

                        Text(name.isEmpty ? "Ihr Name" : name)
                            .font(.headline)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Speichern") {
                    guard var u = appState.currentUser else { return }
                    u.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    u.colorName = colorName

                    // Persist back into app state.
                    appState.currentUser = u

                    // Also update the user in the users list (if present)
                    if let idx = appState.users.firstIndex(where: { $0.id == u.id }) {
                        appState.users[idx] = u
                    }

                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            if let u = appState.currentUser {
                name = u.name
                colorName = u.colorName
            }
        }
    }
}

// MARK: - Systemstatus

private enum SystemHealthState: String {
    case ok
    case degraded
    case down
    case unknown

    var label: String {
        switch self {
        case .ok: return "OK"
        case .degraded: return "Langsam"
        case .down: return "Fehler"
        case .unknown: return "—"
        }
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .degraded: return .orange
        case .down: return .red
        case .unknown: return .gray
        }
    }
}

private struct SystemHealthResult: Equatable {
    var state: SystemHealthState
    var latencyMs: Int?
    var detail: String?

    static let unknown = SystemHealthResult(state: .unknown, latencyMs: nil, detail: nil)
}

private struct SystemStatusSnapshot: Equatable {
    var checkedAt: Date
    var durationMs: Int
    var firestore: SystemHealthResult
    var functions: SystemHealthResult
    var dashboard: SystemHealthResult

    static let empty = SystemStatusSnapshot(
        checkedAt: Date.distantPast,
        durationMs: 0,
        firestore: .unknown,
        functions: .unknown,
        dashboard: .unknown
    )
}

private enum SystemHealthChecks {

    /// Firestore online-ish check: read a tiny document.
    /// Note: Firestore can serve cached reads; this is still a good signal for permissions + connectivity.
    static func checkFirestore() async -> SystemHealthResult {
        let start = Date()
        do {
            let db = Firestore.firestore()
            _ = try await db.collection("system").document("health").getDocument()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return SystemHealthResult(state: ms > 1200 ? .degraded : .ok, latencyMs: ms, detail: nil)
        } catch {
            return SystemHealthResult(state: .down, latencyMs: nil, detail: error.localizedDescription)
        }
    }

    /// Functions check: calls a callable named "health".
    /// If you haven't deployed it yet, this will show as error.
    static func checkFunctions() async -> SystemHealthResult {
        let start = Date()
        do {
            let fn = Functions.functions()
            _ = try await fn.httpsCallable("health").call([:])
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return SystemHealthResult(state: ms > 1200 ? .degraded : .ok, latencyMs: ms, detail: nil)
        } catch {
            return SystemHealthResult(state: .down, latencyMs: nil, detail: error.localizedDescription)
        }
    }

    static func checkDashboard(urlString: String) async -> SystemHealthResult {
        guard let url = URL(string: urlString) else {
            return SystemHealthResult(state: .down, latencyMs: nil, detail: "Ungültige URL")
        }

        let start = Date()
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 6

            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)

            if let http = resp as? HTTPURLResponse {
                if (200...399).contains(http.statusCode) {
                    return SystemHealthResult(state: ms > 1500 ? .degraded : .ok, latencyMs: ms, detail: "HTTP \(http.statusCode)")
                } else {
                    return SystemHealthResult(state: .down, latencyMs: ms, detail: "HTTP \(http.statusCode)")
                }
            }
            return SystemHealthResult(state: .ok, latencyMs: ms, detail: nil)
        } catch {
            return SystemHealthResult(state: .down, latencyMs: nil, detail: error.localizedDescription)
        }
    }
}

private struct SystemStatusTile: View {
    let snapshot: SystemStatusSnapshot
    let isLoading: Bool
    let onRefresh: () -> Void

    private var lastCheckedText: String {
        if snapshot.checkedAt == Date.distantPast { return "Noch nicht geprüft" }
        return snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Systemstatus")
                    .font(.headline)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jetzt prüfen")
            }

            HStack(spacing: 14) {
                StatusChip(title: "Firestore", result: snapshot.firestore)
                StatusChip(title: "Functions", result: snapshot.functions)
                StatusChip(title: "Dashboard", result: snapshot.dashboard)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("Letzter Check: \(lastCheckedText)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if snapshot.checkedAt != Date.distantPast {
                    Text("(\(snapshot.durationMs) ms)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct StatusChip: View {
    let title: String
    let result: SystemHealthResult

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(result.state.color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.semibold))

            if let ms = result.latencyMs {
                Text("\(ms) ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(result.state.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(.systemBackground).opacity(0.65))
        )
    }
}
