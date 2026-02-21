import SwiftUI
import UIKit
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Provisionen werden nicht mehr in der App erfasst.
/// Stattdessen erzeugt die App einen Einmal-Link, den du dem Kunden schicken kannst.
/// Das Provisionsformular wird online ausgefüllt (inkl. Unterschrift).

struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState
    
    private enum AmountMode {
        case preset50
        case custom
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
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

                Section {
                    if let commissionsError {
                        InlineErrorBanner(message: commissionsError)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if isLoadingCommissions {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Lade Provisionen …")
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
                        }                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isAdmin {
                                Button(role: .destructive) {
                                    dismissKeyboard()
                                    pendingAdminAction = .delete(row)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
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
            if case .delete = pendingAdminAction {
                let action = pendingAdminAction!   // safe, weil oben geprüft
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
                            case let .delete(r):
                                await deleteCommission(r)
                            default:
                                break
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private var canGenerateLink: Bool {
        if let a = selectedAmount { return a > 0 }
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
            
            guard let amount = selectedAmount, amount > 0 else {
                await MainActor.run {
                    showError("Bitte einen gültigen Betrag eingeben, bevor du den Link erstellst.")
                }
                return
            }

            let payload: [String: Any] = [
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
                    self.commissions = mapped
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
