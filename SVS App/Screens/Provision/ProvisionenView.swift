import SwiftUI
import UIKit
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Provisionen werden nicht mehr in der App erfasst.
/// Stattdessen erzeugt die App einen Einmal-Link, den du dem Kunden schicken kannst.
/// Das Provisionsformular wird online ausgefüllt (inkl. Unterschrift).

fileprivate enum PendingAdminAction {
    case markPaid(CommissionRow)
    case delete(CommissionRow)
}
struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var amountText: String = ""
    @FocusState private var amountFocused: Bool
    @State private var selectedCommission: CommissionRow? = nil

    @State private var commissions: [CommissionRow] = []
    @State private var isLoadingCommissions: Bool = false
    @State private var commissionsError: String? = nil
    @State private var isAdmin: Bool = false
    @State private var commissionsListener: ListenerRegistration? = nil
    

    @State private var pendingAdminAction: PendingAdminAction? = nil
    @State private var amountFieldInvalid: Bool = false

    // MARK: - Link Generation

    /// Basis-URL deines Online-Formulars. (Server muss Token validieren / einmalig machen.)
    private let provisionFormBaseURL = URL(string: "https://sv-souleiman.de/provision")!

    private let createProvisionLinkEndpoint = URL(
        string: "https://createprovisionlink-df5lzkocnq-uc.a.run.app"
    )!

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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    
                    if showInlineError {
                        InlineErrorBanner(message: inlineErrorMessage)
                            .padding(.horizontal, 18)
                            .transition(.opacity)
                    }
                    
                    SectionCard(title: "Einmal-Link", systemImage: "link") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Erzeuge einen Einmal-Link für das Online-Provisionsformular. Den Link kannst du dem Vermittler schicken. Das Formular wird online ausgefüllt und dort unterschrieben.")
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
                                
                                HStack(spacing: 10) {
                                    Image(systemName: "eurosign.circle")
                                        .foregroundColor(.secondary)
                                    
                                    TextField("z. B. 50,00", text: $amountText)
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
                                                amountText = normalizeAmountText(amountText)
                                                amountFieldInvalid = false
                                            }
                                        }
                                        .onChange(of: amountText) { _, _ in
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

                                Text("Hinweis: Der Betrag wird nicht im Webformular angezeigt, sondern nur im Hintergrund gespeichert.")
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
                    }
                    .padding(.horizontal, 18)
                    
                    SectionCard(title: "Übersicht", systemImage: "list.bullet.rectangle") {
                        VStack(alignment: .leading, spacing: 10) {
                            
                            if let commissionsError {
                                InlineErrorBanner(message: commissionsError)
                            }
                            
                            if isLoadingCommissions {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Lade Provisionen …")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if commissions.isEmpty && !isLoadingCommissions {
                                Text("Noch keine Einträge.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            ForEach(commissions) { row in
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

                                    if isAdmin {
                                        VStack(spacing: 10) {
                                            Button {
                                                pendingAdminAction = .markPaid(row)
                                            } label: {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.green)

                                            Button(role: .destructive) {
                                                pendingAdminAction = .delete(row)
                                            } label: {
                                                Image(systemName: "trash.fill")
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.red)
                                        }
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCommission = row
                                }
                            }
                            
                            Text(isAdmin ? "Admin-Ansicht: alle Einträge." : "Nur deine Einträge (nach Ersteller des Einmal-Links).")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 0)
                }
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                startCommissionsListenerIfNeeded()
            }
            .onDisappear {
                commissionsListener?.remove()
                commissionsListener = nil
            }
            .sheet(item: $selectedCommission) { row in
                CommissionDetailSheet(row: row)
                // When closing the sheet, also clear pendingAdminAction if set
                .onDisappear {
                    selectedCommission = nil
                    pendingAdminAction = nil
                }
            }
            .overlay(alignment: .bottom) {
                if let action = pendingAdminAction {
                    AdminConfirmBar(
                        action: action,
                        onCancel: {
                            withAnimation(.easeInOut) {
                                pendingAdminAction = nil
                            }
                        },
                        onConfirm: {
                            let current = pendingAdminAction
                            withAnimation(.easeInOut) {
                                pendingAdminAction = nil
                            }
                            guard let current else { return }
                            _Concurrency.Task {
                                switch current {
                                case let .markPaid(r):
                                    await markCommissionAsPaid(r)
                                case let .delete(r):
                                    await deleteCommission(r)
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: pendingAdminAction != nil)
            .navigationTitle("Provision")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var parsedAmount: Double? { parseAmountToDouble(amountText) }

    private var canGenerateLink: Bool {
        if let a = parsedAmount { return a > 0 }
        return false
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
            
            let idToken = try await user.getIDToken()
            
            var request = URLRequest(url: createProvisionLinkEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            
            guard let amount = parseAmountToDouble(amountText), amount > 0 else {
                await MainActor.run {
                    showError("Bitte einen gültigen Betrag eingeben, bevor du den Link erstellst.")
                }
                return
            }

            var payload: [String: Any] = [
                "ttlDays": defaultTTLDays,
                "amount": amount
            ]
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
            } else if let token = decoded.token {
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
                .limit(to: 50)

            if !admin {
                q = q.whereField("createdByUid", isEqualTo: user.uid)
            }

            let listener = q.addSnapshotListener { snap, err in
                if let err {
                    _Concurrency.Task { @MainActor in
                        self.isLoadingCommissions = false
                        self.commissionsError = "Provisionen konnten nicht geladen werden: \(err.localizedDescription)"
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
                        status: status,
                        createdAt: ts?.dateValue(),
                        createdByUid: createdByUid
                    )
                }

                _Concurrency.Task { @MainActor in
                    self.isLoadingCommissions = false
                    self.commissions = mapped.filter { $0.status != "paid" }
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

private struct AdminConfirmBar: View {
    let action: PendingAdminAction
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var title: String {
        switch action {
        case .markPaid:
            return "Als ausgezahlt markieren?"
        case .delete:
            return "Eintrag löschen?"
        }
    }

    private var message: String {
        switch action {
        case .markPaid:
            return "Der Eintrag wird als erledigt markiert und verschwindet aus der Übersicht."
        case .delete:
            return "Der Eintrag wird endgültig gelöscht."
        }
    }

    private var confirmTitle: String {
        switch action {
        case .markPaid:
            return "Ausgezahlt"
        case .delete:
            return "Löschen"
        }
    }

    private var confirmRoleDestructive: Bool {
        switch action {
        case .markPaid:
            return false
        case .delete:
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .background(
                    Circle().fill(Color(.tertiarySystemBackground))
                )
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    onCancel()
                } label: {
                    Text("Abbrechen")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                if confirmRoleDestructive {
                    Button(role: .destructive) {
                        onConfirm()
                    } label: {
                        Text(confirmTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onConfirm()
                    } label: {
                        Text(confirmTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

private struct CopyableValueRow: View {
    let title: String
    let value: String
    let copyValue: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)

            Spacer()

            Text(value)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)

            if let copyValue, !copyValue.isEmpty {
                Button {
                    UIPasteboard.general.string = copyValue
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kopieren")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct CommissionDetailSheet: View {
    let row: CommissionRow
    @Environment(\.dismiss) private var dismiss
    @State private var createdByLabel: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Empfehlender") {
                    LabeledContent("Name", value: row.recommenderName)
                    
                    let street = row.recommenderStreet
                    let zipCity: String = {
                        switch (row.recommenderZip, row.recommenderCity) {
                        case let (z?, c?): return "\(z) \(c)"
                        case let (z?, nil): return z
                        case let (nil, c?): return c
                        default: return ""
                        }
                    }()
                    
                    if street == nil && zipCity.isEmpty {
                        LabeledContent("Adresse", value: "—")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adresse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let street { Text(street) }
                            if !zipCity.isEmpty {
                                Text(zipCity)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section("Provision") {
                    if let a = row.amount {
                        LabeledContent("Betrag", value: formatEUR(a))
                    } else {
                        LabeledContent("Betrag", value: "—")
                    }
                    
                    if row.status == "paid" {
                        Text("AUSGEZAHLT")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                    
                    LabeledContent("Auszahlungsart", value: row.payoutMethod.uppercased())
                    
                    if row.payoutMethod == "iban" {
                        CopyableValueRow(
                            title: "IBAN",
                            value: row.payoutIban ?? "—",
                            copyValue: row.payoutIban
                        )
                    } else if row.payoutMethod == "paypal" {
                        CopyableValueRow(
                            title: "PayPal",
                            value: row.payoutPaypal ?? "—",
                            copyValue: row.payoutPaypal
                        )
                    }
                    
                    if let notes = row.notes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Referenz / Notiz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notes)
                        }
                    } else {
                        LabeledContent("Referenz / Notiz", value: "—")
                    }
                }
                
                Section("Zeit") {
                    if let d = row.createdAt {
                        LabeledContent(
                            "Übermittelt",
                            value: d.formatted(date: .complete, time: .shortened)
                        )
                    } else {
                        LabeledContent("Übermittelt", value: "—")
                    }
                }
                
                Section("Dokument") {
                    LabeledContent("Status", value: row.status.uppercased())
                    LabeledContent("ID", value: row.id)
                    LabeledContent(
                        "Veranlasst durch",
                        value: createdByLabel ?? (row.createdByUid ?? "—")
                    )
                }
            }
            .onAppear {
                resolveCreatedByLabelIfNeeded()
            }
            .navigationTitle("Provision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
    
    private func resolveCreatedByLabelIfNeeded() {
        guard createdByLabel == nil else { return }
        guard let uid = row.createdByUid, !uid.isEmpty else {
            createdByLabel = "—"
            return
        }

        if let current = Auth.auth().currentUser?.uid, current == uid {
            createdByLabel = "Du"
            return
        }

        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { snap, _ in
            let data = snap?.data() ?? [:]
            let candidates: [String] = [
                (data["displayName"] as? String) ?? "",
                (data["name"] as? String) ?? "",
                (data["fullName"] as? String) ?? "",
                (data["email"] as? String) ?? ""
            ]
            let best = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            DispatchQueue.main.async {
                self.createdByLabel = best ?? uid
            }
        }
    }
}

private struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct CommissionRow: Identifiable {
    let id: String
    let recommenderName: String

    let recommenderStreet: String?
    let recommenderZip: String?
    let recommenderCity: String?

    let payoutMethod: String
    let payoutIban: String?
    let payoutPaypal: String?

    let amount: Double?
    let notes: String?
    let status: String

    let createdAt: Date?
    let createdByUid: String?
}


private enum ProvisionFormatters {
    static let eur: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 2
        return f
    }()

    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.decimalSeparator = ","
        f.groupingSeparator = "."
        f.usesGroupingSeparator = true
        return f
    }()
}

private func formatEUR(_ v: Double) -> String {
    ProvisionFormatters.eur.string(from: NSNumber(value: v)) ??
        String(format: "%.2f EUR", v)
}

private func normalizeAmountText(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }

    // Accept comma or dot
    let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized) else { return raw }

    return ProvisionFormatters.decimal.string(from: NSNumber(value: value)) ?? raw
}

private func parseAmountToDouble(_ raw: String) -> Double? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Remove spaces and common grouping separators, then convert decimal comma to dot.
    let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
    let noGrouping = noSpaces.replacingOccurrences(of: ".", with: "")
    let normalized = noGrouping.replacingOccurrences(of: ",", with: ".")

    return Double(normalized)
}

#Preview {
    ProvisionenView()
        .environmentObject(AppState())
}
