//
//  AdminAutomationsView.swift
//  SVS App
//
//  Extracted from AdminConsoleView.swift for readability.
//

import Foundation
import SwiftUI
import FirebaseFirestore

private struct AutomationEvent: Identifiable {
    let id: String
    let status: String
    let message: String
    let runAt: Date?
}

private struct AutomationStatusDoc {
    var status: String
    var lastRunAt: Date?
    var lastMessage: String
    var events: [AutomationEvent]
}

struct AdminAutomationsScreen: View {
    @EnvironmentObject var appState: AppState

    let automationId: String

    @State private var doc: AutomationStatusDoc?
    @State private var isLoading: Bool = true
    @State private var listener: ListenerRegistration?
    @State private var eventsListener: ListenerRegistration?
    @State private var showRuns: Bool = false
    @State private var isResettingScannerSequence: Bool = false

    private var accent: Color { appState.currentUser?.color ?? .secondary }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Übersicht (Quick Stats)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Make – Übersicht")
                            .font(.headline)
                            .padding(.horizontal, 18)

                        Text("Quelle: Make (Gutachtenablage)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, -6)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            AutomationMiniCard(
                                title: "Status",
                                value: statusLabel(doc?.status ?? (isLoading ? "warn" : "warn")),
                                systemImage: "bolt.circle",
                                accent: accent
                            )

                            AutomationMiniCard(
                                title: "Letzter Lauf",
                                value: lastRunValue(doc?.lastRunAt),
                                systemImage: "clock",
                                accent: accent
                            )

                            AutomationMiniCard(
                                title: "Letzte Meldung",
                                value: lastMessageValue(doc?.lastMessage),
                                systemImage: "text.bubble",
                                accent: accent
                            )

                            Button {
                                withAnimation {
                                    showRuns = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation {
                                        proxy.scrollTo("runs_history", anchor: .top)
                                    }
                                }
                            } label: {
                                AutomationMiniCard(
                                    title: "Läufe",
                                    value: "\(doc?.events.count ?? 0)",
                                    systemImage: "list.number",
                                    accent: accent
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    HStack(spacing: 6) {
                                        Text("Öffnen")
                                            .font(.caption2.weight(.semibold))
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color(.systemGroupedBackground).opacity(0.85))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                                    )
                                    .padding(10)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)

                        AutomationInfoCard(
                            title: "Hinweis",
                            text: "Diese Werte stammen aus Make (Gutachtenablage) und zeigen Status sowie die letzten Ausführungen. Bei Problemen wird der Status automatisch auf „Fehler“ gesetzt und die Meldung angezeigt.",
                            systemImage: "info.circle",
                            accent: accent
                        )
                        .padding(.horizontal, 18)
                    }
                    .padding(.top, 2)

                    // Aktionen
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aktionen")
                            .font(.headline)
                            .padding(.horizontal, 18)

                        Button {
                            _Concurrency.Task { await resetScannerSequenceFromSheet() }
                        } label: {
                            AutomationActionCard(accent: accent) {
                                HStack(spacing: 10) {
                                    if isResettingScannerSequence {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise.circle")
                                            .font(.system(size: 16, weight: .semibold))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Scanner-Nummer reset")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)
                                    }

                                    Spacer()

                                    if !isResettingScannerSequence {
                                        Image(systemName: "arrow.right")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isResettingScannerSequence)
                        .opacity(isResettingScannerSequence ? 0.6 : 1.0)
                        .padding(.horizontal, 18)
                        
                        Text("Notfall-Reset der aktuellen Scanner-Nummer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 18)
                    }
                    .padding(.top, 2)

                    if showRuns {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Historie")
                                    .font(.headline)
                                Spacer()
                                Button("Schließen") { withAnimation { showRuns = false } }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 18)

                            eventsList
                                .padding(.horizontal, 18)
                        }
                        .id("runs_history")
                        .padding(.top, 4)
                    }


                    Spacer(minLength: 18)
                }
                .padding(.bottom, 18)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Automatisierungen")
        .onAppear { startListening() }
        .onDisappear {
            listener?.remove()
            listener = nil
            eventsListener?.remove()
            eventsListener = nil
        }
        .refreshable {
            await refreshNow()
        }
    }
    
    private struct AutomationActionCard<Content: View>: View {
        let accent: Color
        let content: Content

        init(accent: Color, @ViewBuilder content: () -> Content) {
            self.accent = accent
            self.content = content()
        }

        var body: some View {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
        }
    }
    
    private func shortStatusTitle(_ s: String) -> String {
        switch s {
        case "ok": return "OK"
        case "error": return "Fehler"
        default: return "Hinweis"
        }
    }

    private func fetchOnce(completion: @escaping () -> Void = {}) {
        isLoading = true

        let ref = Firestore.firestore().collection("automations").document(automationId)
        let eventsRef = ref.collection("events")
            .order(by: "runAt", descending: true)
            .limit(to: 10)

        let group = DispatchGroup()

        var status: String = "warn"
        var lastMessage: String = ""
        var lastRunAt: Date? = nil
        var events: [AutomationEvent] = []

        group.enter()
        ref.getDocument { snap, err in
            defer { group.leave() }

            if let err {
                print("[automations] fetch doc error:", err)
                return
            }

            guard let data = snap?.data() else { return }
            status = (data["status"] as? String) ?? "warn"
            lastMessage = (data["lastMessage"] as? String) ?? ""
            lastRunAt = (data["lastRunAt"] as? Timestamp)?.dateValue()
        }

        group.enter()
        eventsRef.getDocuments { snap, err in
            defer { group.leave() }

            if let err {
                print("[automations] fetch events error:", err)
                return
            }

            events = (snap?.documents ?? []).map { d in
                let data = d.data()
                let s = (data["status"] as? String) ?? "warn"
                let m = (data["message"] as? String) ?? ""
                let r = (data["runAt"] as? Timestamp)?.dateValue()
                return AutomationEvent(id: d.documentID, status: s, message: m, runAt: r)
            }
        }

        group.notify(queue: .main) {
            self.doc = AutomationStatusDoc(
                status: status,
                lastRunAt: lastRunAt,
                lastMessage: lastMessage,
                events: events
            )
            self.isLoading = false
            completion()
        }
    }

    private func refreshNow() async {
        await withCheckedContinuation { cont in
            fetchOnce {
                cont.resume()
            }
        }
    }

    @MainActor
    private func resetScannerSequenceFromSheet() async {
        guard !isResettingScannerSequence else { return }
        isResettingScannerSequence = true
        defer { isResettingScannerSequence = false }
        _ = await appState.adminResetScannerSequenceFromSheet()
    }

    private var automationCard: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Status wird geladen…")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            } else if let doc {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        statusDot(doc.status)
                        Text(statusLabel(doc.status))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Label(lastRunText(doc.lastRunAt), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    if !doc.lastMessage.isEmpty {
                        Text(doc.lastMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch kein Status vorhanden")
                        .font(.subheadline.weight(.semibold))
                    Text("Sobald Make den ersten Lauf meldet, erscheint hier der Status.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            }
        }
    }
    
    private var eventsList: some View {
        Group {
            let items = doc?.events ?? []
            if items.isEmpty {
                HStack(spacing: 10) {
                    Text("Noch keine Läufe vorhanden")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { e in
                        HStack(alignment: .top, spacing: 10) {
                            statusDot(e.status)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {

                                HStack(spacing: 8) {
                                    Text(shortStatusTitle(e.status))
                                        .font(.footnote.weight(.semibold))

                                    Text(e.runAt?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                                        .font(.footnote.weight(.semibold))

                                    Spacer(minLength: 0)
                                }

                                if !e.message.isEmpty {
                                    Text(e.message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }


    private func startListening() {
        isLoading = true
        listener?.remove()
        eventsListener?.remove()

        let ref = Firestore.firestore().collection("automations").document(automationId)
        listener = ref.addSnapshotListener { snap, err in
            if let err {
                print("[automations] snapshot error:", err)
                self.doc = nil
                self.isLoading = false
                return
            }

            guard let data = snap?.data() else {
                self.doc = nil
                self.isLoading = false
                return
            }

            let status = (data["status"] as? String) ?? "warn"
            let lastMessage = (data["lastMessage"] as? String) ?? ""
            let lastRunAt = (data["lastRunAt"] as? Timestamp)?.dateValue()

            self.doc = AutomationStatusDoc(
                status: status,
                lastRunAt: lastRunAt,
                lastMessage: lastMessage,
                events: self.doc?.events ?? []
            )
            self.isLoading = false
        }
        
        let eventsRef = ref.collection("events")
            .order(by: "runAt", descending: true)
            .limit(to: 10)

        eventsListener = eventsRef.addSnapshotListener { snap, err in
            if let err {
                print("[automations] events snapshot error:", err)
                return
            }

            let items: [AutomationEvent] = (snap?.documents ?? []).map { d in
                let data = d.data()
                let status = (data["status"] as? String) ?? "warn"
                let message = (data["message"] as? String) ?? ""
                let runAt = (data["runAt"] as? Timestamp)?.dateValue()
                return AutomationEvent(id: d.documentID, status: status, message: message, runAt: runAt)
            }

            if var existing = self.doc {
                existing.events = items
                self.doc = existing
            } else {
                self.doc = AutomationStatusDoc(status: "warn", lastRunAt: nil, lastMessage: "", events: items)
            }
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "ok": return "Läuft"
        case "error": return "Fehler"
        default: return "Hinweis"
        }
    }

    private func lastRunValue(_ d: Date?) -> String {
        guard let d else { return isLoading ? "Lädt…" : "–" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func lastMessageValue(_ s: String?) -> String {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return isLoading ? "Lädt…" : "–" }
        // Keep it compact for the mini card
        return String(t.prefix(42)) + (t.count > 42 ? "…" : "")
    }

    private struct AutomationMiniCard: View {
        let title: String
        let value: String
        let systemImage: String
        let accent: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundColor(accent)
                    Spacer()
                }
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private struct AutomationInfoCard: View {
        let title: String
        let text: String
        let systemImage: String
        let accent: Color

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func statusDot(_ s: String) -> some View {
        let c: Color = {
            switch s {
            case "ok": return .green
            case "error": return .red
            default: return .orange
            }
        }()
        Circle().fill(c).frame(width: 10, height: 10)
    }

    private func lastRunText(_ d: Date?) -> String {
        guard let d else { return "Letzter Lauf: –" }
        return "Letzter Lauf: \(d.formatted(date: .abbreviated, time: .shortened))"
    }
}
