import SwiftUI
import UIKit
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Prämien werden nicht mehr in der App erfasst.
/// Stattdessen erzeugt die App einen Einmal-Link, den du dem Kunden schicken kannst.
/// Das Vermittlungsprämien-Formular wird online ausgefüllt (inkl. Unterschrift).

struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState
    var showsAdminTeamInsights: Bool = false
    
    private enum AmountMode {
        case preset50
        case custom
    }
    
    private enum CommissionFilter: String, CaseIterable, Identifiable {
        case open = "Offen"
        case paid = "Bezahlt"
        case all = "Alle"

        var id: String { rawValue }
    }

    @State private var amountMode: AmountMode = .preset50
    @State private var customAmountText: String = ""
    @FocusState private var amountFocused: Bool
    @State private var selectedCommission: CommissionRow? = nil
    
    @State private var commissions: [CommissionRow] = []
    @State private var isLoadingCommissions: Bool = false
    @State private var commissionsError: String? = nil
    @State private var isAdmin: Bool = false
    @State private var commissionsListener: ListenerRegistration? = nil
    @State private var commissionQueryLimit: Int = 100
    @State private var canLoadMoreCommissions: Bool = false
    @State private var teamStats: [CommissionCreatorStats] = []
    @State private var isLoadingTeamStats: Bool = false
    @State private var selectedFilter: CommissionFilter = .open
    @State private var deleteTarget: CommissionRow? = nil
    @State private var amountFieldInvalid: Bool = false
    @State private var gutachtenNumberText: String = ""
    @FocusState private var gutachtenNumberFocused: Bool
    
    // MARK: - Link Generation
    
    /// Basis-URL deines Online-Formulars. (Server muss Token validieren / einmalig machen.)
    private var provisionFormBaseURL: URL? {
        URL(string: "https://sv-souleiman.de/provision")
    }
    
    private var createProvisionLinkEndpoint: URL? {
        URL(string: "https://createprovisionlink-df5lzkocnq-uc.a.run.app")
    }
    
    /// Wie lange der Link gültig sein soll (Tage)
    private let defaultTTLDays: Int = 30
    
    @State private var isGenerating: Bool = false
    @State private var generatedURL: URL? = nil
    @State private var lastGeneratedAt: Date? = nil
    
    // Inline Error (nur sichtbar, wenn es einen Fehler gibt)
    @State private var showInlineError: Bool = false
    @State private var inlineErrorMessage: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                if showInlineError {
                    InlineErrorBanner(message: inlineErrorMessage)
                        .transition(.opacity)
                        .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                SectionCard(title: "Einmal-Link", systemImage: "link") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Erzeuge einen Einmal-Link für das Online-Formular zur Vermittlungsprämie. Den Link kannst du dem Vermittler schicken. Das Formular wird online ausgefüllt und dort unterschrieben.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let lastGeneratedAt {
                            Text("Zuletzt erstellt: \(lastGeneratedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Betrag")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                amountModeButton(title: "50 €", mode: .preset50)
                                amountModeButton(title: "Anderer Betrag", mode: .custom)
                            }

                            if amountMode == .custom {
                                HStack(spacing: 10) {
                                    Image(systemName: "eurosign.circle")
                                        .foregroundColor(.secondary)

                                    TextField("z. B. 75,00", text: $customAmountText)
                                        .keyboardType(.numbersAndPunctuation)
                                        .focused($amountFocused)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .textContentType(.none)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            amountFocused = false
                                        }
                                        .onChange(of: amountFocused) { _, focused in
                                            if !focused {
                                                customAmountText = normalizeAmountText(customAmountText)
                                                amountFieldInvalid = false
                                            }
                                        }
                                        .onChange(of: customAmountText) { _, _ in
                                            amountFieldInvalid = false
                                        }

                                    Text("EUR")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(amountFieldInvalid ? Color.red : Color.clear, lineWidth: 1)
                                )
                            }
                            Text("Der Betrag wird nicht im Webformular angezeigt.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gutachten-Nr.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                Image(systemName: "number")
                                    .foregroundColor(.secondary)

                                TextField("z. B. 42/26", text: $gutachtenNumberText)
                                    .focused($gutachtenNumberFocused)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .textContentType(.none)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        gutachtenNumberFocused = false
                                    }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.tertiarySystemBackground))
                            )

                            Text("Nur intern gespeichert.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Button {
                            if !canGenerateLink {
                                amountFieldInvalid = true
                                showError("Bitte einen gültigen Betrag eingeben, bevor du den Link erstellst.")
                                return
                            }
                            amountFieldInvalid = false
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
                        .tint(Color.accentColor)
                        .foregroundColor(.white)
                        .disabled(isGenerating || !canGenerateLink)
                    }

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
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 0, trailing: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if showsAdminTeamInsights && isAdmin {
                    CommissionTeamInsightsSection(
                        stats: teamStats,
                        isLoading: isLoadingTeamStats
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 0, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section {
                    if let commissionsError {
                        InlineErrorBanner(message: commissionsError)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if isLoadingCommissions {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Lade Prämien …")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if commissions.isEmpty && !isLoadingCommissions {
                        Text("Noch keine Einträge.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if !commissions.isEmpty {
                        provisionSummaryRow
                            .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 4, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(CommissionFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(filteredCommissions) { row in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.recommenderName)
                                        .font(.headline)
                                        .lineLimit(1)

                                    Spacer()

                                    if let a = row.amount {
                                        Text(formatEUR(a))
                                            .font(.headline)
                                    }

                                    if row.status == "paid" {
                                        Text("AUSGEZAHLT")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color(.secondarySystemBackground))
                                            )
                                    }
                                }

                                HStack(spacing: 10) {
                                    Label(
                                        row.payoutMethod.uppercased(),
                                        systemImage: row.payoutMethod == "paypal"
                                            ? "p.circle"
                                            : "building.columns"
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                    Spacer()

                                    if let d = row.createdAt {
                                        Text(d.formatted(date: .abbreviated, time: .shortened))
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .opacity(row.status == "paid" ? 0.55 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissKeyboard()
                            selectedCommission = row
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if isAdmin && row.status != "paid" {
                                Button {
                                    dismissKeyboard()
                                    _Concurrency.Task {
                                        await markCommissionAsPaid(row)
                                    }
                                } label: {
                                    Label("Ausgezahlt", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isAdmin {
                                Button(role: .destructive) {
                                    dismissKeyboard()
                                    deleteTarget = row
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if canLoadMoreCommissions {
                        Button {
                            loadMoreCommissions()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.down.circle")
                                Text("Weitere Einträge laden")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("+\(commissionPageSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 10, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Übersicht")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 0)
                    .textCase(nil)
                }
            }
            .modifier(SectionSpacingFixer())
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            startCommissionsListenerIfNeeded()
            if showsAdminTeamInsights {
                _Concurrency.Task {
                    await loadAdminTeamStatsIfNeeded()
                }
            }
        }
        .onDisappear {
            stopCommissionsListener()
        }
        .onChange(of: isAdmin) { _, admin in
            guard admin, showsAdminTeamInsights else { return }
            _Concurrency.Task {
                await loadAdminTeamStatsIfNeeded()
            }
        }
        .sheet(item: $selectedCommission) { row in
            CommissionDetailSheet(row: row)
                .onDisappear {
                    selectedCommission = nil
                }
        }
        .alert("Prämie löschen?", isPresented: deleteAlertBinding) {
            Button("Abbrechen", role: .cancel) {
                deleteTarget = nil
            }
            Button("Löschen", role: .destructive) {
                guard let row = deleteTarget else { return }
                deleteTarget = nil
                _Concurrency.Task {
                    await deleteCommission(row)
                }
            }
        } message: {
            if let row = deleteTarget {
                Text("Möchtest du den Eintrag von \(row.recommenderName) wirklich löschen?")
            } else {
                Text("Dieser Eintrag wird dauerhaft gelöscht.")
            }
        }
        .navigationTitle("Prämien")
        .navigationBarTitleDisplayMode(.inline)
    }

    
    private struct SectionSpacingFixer: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content.listSectionSpacing(.custom(0))
            } else {
                content
            }
        }
    }
    
    private var selectedAmount: Double? {
        switch amountMode {
        case .preset50:
            return 50.0
        case .custom:
            return parseAmountToDouble(customAmountText)
        }
    }

    @ViewBuilder
    private func amountModeButton(title: String, mode: AmountMode) -> some View {
        let isSelected = amountMode == mode

        Button {
            amountMode = mode
            amountFieldInvalid = false
            if mode == .preset50 {
                amountFocused = false
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func dismissKeyboard() {
        amountFocused = false
        gutachtenNumberFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private var canGenerateLink: Bool {
        if let a = selectedAmount { return a > 0 }
        return false
    }
    
    private let commissionPageSize = 100

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { isPresented in
                if !isPresented { deleteTarget = nil }
            }
        )
    }

    private var filteredCommissions: [CommissionRow] {
        switch selectedFilter {
        case .open:
            return commissions.filter { $0.status != "paid" }
        case .paid:
            return commissions.filter { $0.status == "paid" }
        case .all:
            return commissions
        }
    }

    private var openCount: Int {
        commissions.reduce(into: 0) { partialResult, row in
            if row.status != "paid" {
                partialResult += 1
            }
        }
    }

    private var paidCount: Int {
        commissions.count - openCount
    }

    private var provisionSummaryRow: some View {
        HStack(spacing: 10) {
            summaryPill(
                title: "Offen",
                count: openCount,
                color: .orange
            )
            summaryPill(
                title: "Bezahlt",
                count: paidCount,
                color: .green
            )
            Spacer()
            Text("\(commissions.count) geladen")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func summaryPill(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title): \(count)")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // header removed

    // MARK: - Actions

    private func generateOneTimeLink() async {
        await MainActor.run {
            clearInlineError()
            isGenerating = true
        }
        defer {
            _Concurrency.Task { @MainActor in
                isGenerating = false
            }
        }
        do {
            guard let user = Auth.auth().currentUser else {
                await MainActor.run {
                    showError("Nicht angemeldet. Bitte erneut einloggen.")
                }
                return
            }

            guard let createProvisionLinkEndpoint else {
                await MainActor.run {
                    showError("Prämien-Link-URL ist ungültig.")
                }
                return
            }
            
            let idToken = try await user.getIDToken()
            
            var request = URLRequest(url: createProvisionLinkEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            
            guard let amount = selectedAmount, amount > 0 else {
                await MainActor.run {
                    showError("Bitte einen gültigen Betrag eingeben, bevor du den Link erstellst.")
                }
                return
            }

            var payload: [String: Any] = [
                "ttlDays": defaultTTLDays,
                "amount": amount
            ]
            let gutachtenNumber = gutachtenNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !gutachtenNumber.isEmpty {
                payload["gutachtenNumber"] = gutachtenNumber
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run {
                    showError("Serverantwort ungültig.")
                }
                return
            }
            
            guard (200...299).contains(http.statusCode) else {
                let serverText = String(data: data, encoding: .utf8) ?? ""
                await MainActor.run {
                    showError("Link konnte nicht erstellt werden (\(http.statusCode)). \(serverText)".trimmed)
                }
                return
            }
            
            struct CreateLinkResponse: Decodable {
                let ok: Bool?
                let token: String?
                let url: String?
                let expiresAt: String?
            }
            
            let decoded = try JSONDecoder().decode(CreateLinkResponse.self, from: data)
            
            let finalURL: URL?
            if let urlString = decoded.url, let u = URL(string: urlString) {
                finalURL = u
            } else if let token = decoded.token, let provisionFormBaseURL {
                var comps = URLComponents(url: provisionFormBaseURL, resolvingAgainstBaseURL: false)
                let existing = comps?.queryItems ?? []
                comps?.queryItems = existing + [URLQueryItem(name: "token", value: token)]
                finalURL = comps?.url
            } else {
                finalURL = nil
            }
            
            guard let url = finalURL else {
                await MainActor.run {
                    showError("Server hat keinen gültigen Link zurückgegeben.")
                }
                return
            }
            
            await MainActor.run {
                generatedURL = url
                lastGeneratedAt = Date()

                UIPasteboard.general.string = url.absoluteString
                appState.showToast(.success, "Einmal-Link erstellt und kopiert")
            }
        } catch {
            await MainActor.run {
                showError("Link konnte nicht erstellt werden: \(error.localizedDescription)")
            }
        }
    }

    private func markCommissionAsPaid(_ row: CommissionRow) async {
        do {
            let db = Firestore.firestore()
            let uid = Auth.auth().currentUser?.uid ?? ""
            try await db.collection("commissions").document(row.id).updateData([
                "status": "paid",
                "paidAt": FieldValue.serverTimestamp(),
                "paidByUid": uid
            ])

            await MainActor.run {
                appState.showToast(.success, "Als ausgezahlt markiert")
            }
        } catch {
            await MainActor.run {
                showError("Konnte nicht als ausgezahlt markieren: \(error.localizedDescription)")
            }
        }
    }

    private func deleteCommission(_ row: CommissionRow) async {
        do {
            let db = Firestore.firestore()
            try await db.collection("commissions").document(row.id).delete()
            await MainActor.run {
                appState.showToast(.success, "Eintrag gelöscht")
            }
        } catch {
            await MainActor.run {
                showError("Konnte nicht löschen: \(error.localizedDescription)")
            }
        }
    }
        
    @MainActor
    private func stopCommissionsListener() {
        commissionsListener?.remove()
        commissionsListener = nil
    }

    @MainActor
    private func restartCommissionsListener() {
        stopCommissionsListener()
        startCommissionsListenerIfNeeded()
    }

    @MainActor
    private func loadMoreCommissions() {
        commissionQueryLimit += commissionPageSize
        restartCommissionsListener()
    }

    @MainActor
    private func loadAdminTeamStatsIfNeeded() async {
        guard showsAdminTeamInsights, isAdmin else { return }
        guard !isLoadingTeamStats else { return }

        isLoadingTeamStats = true
        defer { isLoadingTeamStats = false }

        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("commissions")
                .order(by: "acceptedAtServer", descending: true)
                .limit(to: 1000)
                .getDocuments()

            teamStats = CommissionCreatorStatsBuilder.build(
                from: snapshot.documents,
                users: appState.users
            )
        } catch {
            showError("Mitarbeiter-Übersicht konnte nicht geladen werden: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func startCommissionsListenerIfNeeded() {
        guard commissionsListener == nil else { return }
        guard let user = Auth.auth().currentUser else { return }

        isLoadingCommissions = true
        commissionsError = nil

        let db = Firestore.firestore()

        db.collection("users").document(user.uid).getDocument { snap, err in
            if let err {
                _Concurrency.Task { @MainActor in
                    self.isLoadingCommissions = false
                    self.commissionsError = "Rolle konnte nicht geladen werden: \(err.localizedDescription)"
                }
                return
            }

            let roleRaw = (snap?.data()?["roleRaw"] as? String) ?? ""
            let admin = roleRaw == "admin"

            _Concurrency.Task { @MainActor in
                self.isAdmin = admin
            }

            var q: Query = db.collection("commissions")
                .order(by: "acceptedAtServer", descending: true)
                .limit(to: commissionQueryLimit)

            if !admin {
                q = q.whereField("createdByUid", isEqualTo: user.uid)
            }

            let listener = q.addSnapshotListener { snap, err in
                if let err {
                    _Concurrency.Task { @MainActor in
                        self.isLoadingCommissions = false
                        self.commissionsError = "Prämien konnten nicht geladen werden: \(err.localizedDescription)"
                    }
                    return
                }

                let docs = snap?.documents ?? []
                let mapped: [CommissionRow] = docs.map { d in
                    let data = d.data()

                    func clean(_ s: String?) -> String? {
                        guard let s else { return nil }
                        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        return v.isEmpty ? nil : v
                    }

                    let name = (data["recommenderName"] as? String) ?? "—"

                    let street = clean(data["recommenderStreet"] as? String)
                    let zip = clean(data["recommenderZip"] as? String)
                    let city = clean(data["recommenderCity"] as? String)

                    let payout = (data["payoutMethod"] as? String) ?? "—"
                    let payoutIban = clean(data["payoutIban"] as? String)
                    let payoutPaypal = clean(data["payoutPaypal"] as? String)

                    let amount = data["amount"] as? Double
                    let notes = clean(data["notes"] as? String)
                    let gutachtenNumber = clean(data["gutachtenNumber"] as? String)
                    let status = (data["status"] as? String) ?? "submitted"
                    let ts = data["acceptedAtServer"] as? Timestamp
                    let createdByUid = clean(data["createdByUid"] as? String)

                    return CommissionRow(
                        id: d.documentID,
                        recommenderName: name,
                        recommenderStreet: street,
                        recommenderZip: zip,
                        recommenderCity: city,
                        payoutMethod: payout,
                        payoutIban: payoutIban,
                        payoutPaypal: payoutPaypal,
                        amount: amount,
                        notes: notes,
                        gutachtenNumber: gutachtenNumber,
                        status: status,
                        createdAt: ts?.dateValue(),
                        createdByUid: createdByUid
                    )
                }

                _Concurrency.Task { @MainActor in
                    self.isLoadingCommissions = false
                    self.commissions = mapped
                    self.canLoadMoreCommissions = mapped.count >= self.commissionQueryLimit
                }
            }

            _Concurrency.Task { @MainActor in
                self.commissionsListener = listener
            }
        }
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


#Preview {
    ProvisionenView()
        .environmentObject(AppState())
}
