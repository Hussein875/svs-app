//
//  AppState.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions


struct UserProfile: Codable {
    var name: String
    var roleRaw: String
    var colorName: String
    var annualLeaveDays: Int
    var email: String

    init(name: String,
         roleRaw: String,
         colorName: String,
         annualLeaveDays: Int,
         email: String) {
        self.name = name
        self.roleRaw = roleRaw
        self.colorName = colorName
        self.annualLeaveDays = annualLeaveDays
        self.email = email
    }

    init(from user: User) {
        self.name = user.name
        self.roleRaw = user.role.rawValue
        self.colorName = user.colorName
        self.annualLeaveDays = user.annualLeaveDays
        self.email = user.email
    }

    init?(from data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let roleRaw = data["roleRaw"] as? String,
            let colorName = data["colorName"] as? String,
            let annualLeaveDays = data["annualLeaveDays"] as? Int,
            let email = data["email"] as? String
        else { return nil }

        self.name = name
        self.roleRaw = roleRaw
        self.colorName = colorName
        self.annualLeaveDays = annualLeaveDays
        self.email = email
    }

    func toDictionary() -> [String: Any] {
        [
            "name": name,
            "roleRaw": roleRaw,
            "colorName": colorName,
            "annualLeaveDays": annualLeaveDays,
            "email": email
        ]
    }

    func toUser(id: UUID = UUID()) -> User {
        User(
            id: id,
            name: name,
            role: UserRole(rawValue: roleRaw) ?? .employee,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: email
        )
    }
}

class AppState: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    
    @Published var auth = AuthManager()
    
    @Published var users: [User] {
        didSet { saveUsers() }
    }
    @Published var currentUser: User?
    @Published var leaveRequests: [LeaveRequest] {
        didSet { saveLeaveRequests() }
    }
    @Published var tasks: [Task] = [] {
        didSet { saveTasks() }
    }
    @Published var uiErrorMessage: String? = nil
    
    @Published var commissions: [CommissionEntry] {
        didSet { saveCommissions() }
    }
    
    // Session: keep user logged in across app launches
    @Published var sessionUserId: UUID? = nil {
        didSet {
            if let id = sessionUserId {
                UserDefaults.standard.set(id.uuidString, forKey: "sessionUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "sessionUserId")
            }
        }
    }
    
    @Published var lastUserId: UUID? = nil {
        didSet {
            if let id = lastUserId {
                UserDefaults.standard.set(id.uuidString, forKey: "lastUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastUserId")
            }
        }
    }
    
    @Published var toast: AppToast? = nil
    
    func showToast(_ kind: ToastKind, _ message: String) {
        toast = AppToast(kind: kind, message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.toast?.message == message {
                self?.toast = nil
            }
        }
    }

    init() {
        // Users laden / Default Users
        if let data = UserDefaults.standard.data(forKey: "users"),
           let decoded = try? JSONDecoder().decode([User].self, from: data) {
            self.users = decoded
        } else {
            self.users = []
        }
        self.currentUser = nil

        // Leave Requests laden
        if let data = UserDefaults.standard.data(forKey: "leaveRequests"),
           let decoded = try? JSONDecoder().decode([LeaveRequest].self, from: data) {
            // Alte Einträge mit "Sonstiges" auf "Urlaub" mappen
            self.leaveRequests = decoded
        } else {
            self.leaveRequests = []
        }
        
        if let data = UserDefaults.standard.data(forKey: "commissions"),
           let decoded = try? JSONDecoder().decode([CommissionEntry].self, from: data) {
            self.commissions = decoded
        } else {
            self.commissions = []
        }

        // Tasks laden
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           let decoded = try? JSONDecoder().decode([Task].self, from: data) {
            self.tasks = decoded
        } else {
            self.tasks = []
        }

        // Letzten eingeloggten Benutzer laden
        if let idString = UserDefaults.standard.string(forKey: "lastUserId"),
           let id = UUID(uuidString: idString) {
            self.lastUserId = id
        } else {
            self.lastUserId = nil
        }
        
        // Session-Login laden (User bleibt eingeloggt)
        if let sessionIdString = UserDefaults.standard.string(forKey: "sessionUserId"),
           let sessionId = UUID(uuidString: sessionIdString) {
            self.sessionUserId = sessionId
        } else {
            self.sessionUserId = nil
        }

        // Firebase Auth -> Firestore Profil laden/anlegen (Quelle der Wahrheit für Profil-Daten)
        auth.$user
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fbUser in
                guard let self else { return }

                // Wenn ausgeloggt: lokalen User leeren + Session IDs zurücksetzen
                guard let fbUser else {
                    self.currentUser = nil
                    self.sessionUserId = nil
                    return
                }

                _Concurrency.Task { [weak self] in
                    await self?.loadOrCreateProfile(for: fbUser)
                }
            }
            .store(in: &cancellables)
    }
    
    func sendPasswordReset(to email: String) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else {
            self.uiErrorMessage = "Bitte eine gültige E-Mail-Adresse angeben."
            return
        }

        Auth.auth().sendPasswordReset(withEmail: cleanEmail) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.uiErrorMessage = "Passwort-Reset fehlgeschlagen: \(error.localizedDescription)"
                } else {
                    self?.uiErrorMessage = nil
                }
            }
        }
    }

    @MainActor
    func adminCreateUserViaFunction(name: String,
                                    email: String,
                                    role: UserRole,
                                    colorName: String,
                                    annualLeaveDays: Int) async {
        let functions = Functions.functions(region: "us-central1")

        do {
            let result = try await functions.httpsCallable("adminCreateUserInvite").call([
                "name": name,
                "email": email,
                "roleRaw": role.rawValue,
                "colorName": colorName,
                "annualLeaveDays": annualLeaveDays
            ])

            if let data = result.data as? [String: Any], (data["ok"] as? Bool) == true {
                // Jetzt kann der Admin direkt Passwort-Reset senden (Firebase verschickt E-Mail)
                sendPasswordReset(to: email)
            }
            self.uiErrorMessage = nil
        } catch {
            self.uiErrorMessage = "Cloud Function Fehler: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    func adminUpsertUserProfile(name: String,
                               email: String,
                               role: UserRole,
                               colorName: String,
                               annualLeaveDays: Int) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName  = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty else {
            self.uiErrorMessage = "Bitte eine gültige E-Mail-Adresse angeben."
            return
        }
        guard !cleanName.isEmpty else {
            self.uiErrorMessage = "Bitte einen Namen angeben."
            return
        }

        let profile = UserProfile(
            name: cleanName,
            roleRaw: role.rawValue,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: cleanEmail
        )

        do {
            // Admin legt zunächst ein Invite an (Quelle: E-Mail). Beim ersten Login wird es nach users/<uid> übernommen.
            try await db.collection("invites").document(cleanEmail).setData(profile.toDictionary(), merge: true)
            self.uiErrorMessage = nil
        } catch {
            self.uiErrorMessage = "Profil konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    private func saveLeaveRequests() {
        if let data = try? JSONEncoder().encode(leaveRequests) {
            UserDefaults.standard.set(data, forKey: "leaveRequests")
        }
    }

    private func saveUsers() {
        if let data = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(data, forKey: "users")
        }
    }

    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: "tasks")
        }
    }

    func addUser(name: String, role: UserRole, colorName: String, annualLeaveDays: Int, email: String) {
        let newUser = User(
            id: UUID(),
            name: name,
            role: role,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        users.append(newUser)
    }

    func updateUser(_ user: User) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        }
        // Benutzer auch in bestehenden Anträgen aktualisieren
        leaveRequests = leaveRequests.map { request in
            if request.user.id == user.id {
                var updated = request
                updated.user = user
                return updated
            } else {
                return request
            }
        }
    }

    func deleteUser(_ user: User) {
        users.removeAll { $0.id == user.id }
    }

    private func normalizeDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func rangesOverlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        let aS = normalizeDay(aStart)
        let aE = normalizeDay(aEnd)
        let bS = normalizeDay(bStart)
        let bE = normalizeDay(bEnd)
        return aS <= bE && bS <= aE
    }

    /// Prüft, ob für den Benutzer im Zeitraum bereits ein kollidierender Antrag existiert.
    /// Regeln:
    /// - Abgelehnte Einträge blockieren nie.
    /// - Urlaub darf sich nicht mit anderem Urlaub überschneiden (Status != .rejected).
    /// - Krankheit darf Urlaub überlappen, aber nicht mit anderer Krankheit am selben Zeitraum (Status != .rejected).
    /// Optional kann ein `excludingRequestId` gesetzt werden (z. B. beim Bearbeiten).
    private func hasOverlappingLeave(for userId: UUID,
                                    start: Date,
                                    end: Date,
                                    newType: LeaveType,
                                    excludingRequestId: UUID? = nil) -> Bool {
        return leaveRequests.contains { req in
            guard req.user.id == userId else { return false }
            if let ex = excludingRequestId, req.id == ex { return false }

            // Abgelehnte Einträge blockieren nie
            guard req.status != .rejected else { return false }

            // Nur gleiche Typen blockieren (Urlaub blockt Urlaub, Krankheit blockt Krankheit)
            guard req.type == newType else { return false }

            return rangesOverlap(req.startDate, req.endDate, start, end)
        }
    }

    @discardableResult
    func createLeaveRequest(start: Date, end: Date, type: LeaveType) -> Bool {
        guard let user = currentUser else {
            uiErrorMessage = "Kein Benutzer angemeldet."
            return false
        }
        // Standard: Mitarbeiter legt für sich selbst an (Urlaub = Offen, Krankheit = direkt)
        return createLeaveRequest(start: start, end: end, type: type, for: user, approveImmediately: false)
    }

    /// Admin kann Anträge für andere Benutzer anlegen.
    /// - Urlaub: optional sofort genehmigen.
    /// - Krankheit: wird immer sofort eingetragen (Genehmigt), unabhängig vom Toggle.
    @discardableResult
    func createLeaveRequest(start: Date,
                            end: Date,
                            type: LeaveType,
                            for user: User,
                            approveImmediately: Bool) -> Bool {

        if type == .vacation {
            let requestedDays = workingDays(from: start, to: end)
            let available = availableVacationDaysForRequests(for: user)
            if requestedDays > available {
                uiErrorMessage = "Nicht genügend Resturlaub. Verfügbar: \(available) Tag(e), angefragt: \(requestedDays) Tag(e)."
                return false
            }
        }
        
        // Validierung: Überschneidungen prüfen
        if hasOverlappingLeave(for: user.id, start: start, end: end, newType: type) {
            switch type {
            case .sick:
                if Calendar.current.isDate(start, inSameDayAs: end) {
                    uiErrorMessage = "Für diesen Tag haben Sie sich bereits krank gemeldet."
                } else {
                    uiErrorMessage = "In diesem Zeitraum haben Sie sich bereits krank gemeldet."
                }
            case .vacation:
                uiErrorMessage = "Dieser Zeitraum überschneidet sich mit einem bestehenden Urlaubsantrag."
            case .onCallSaturday:
                uiErrorMessage = "Samstag bereits vergeben."
            }
            return false
        }

        // Status:
        // - Krankheit: immer direkt eingetragen
        // - Urlaub: entweder offen oder direkt genehmigt (Admin-Option)
        let initialStatus: LeaveStatus
        if type == .sick {
            initialStatus = .approved
        } else {
            initialStatus = approveImmediately ? .approved : .pending
        }

        let creatorId = currentUser?.id ?? user.id
        let request = LeaveRequest(
            id: UUID(),
            user: user,
            startDate: start,
            endDate: end,
            type: type,
            reason: "",
            status: initialStatus,
            createdAt: Date(),
            createdByUserId: creatorId,
            updatedAt: nil,
            updatedByUserId: nil
        )
        leaveRequests.append(request)
        let successText: String
        if type == .sick {
            successText = "Krankmeldung erfolgreich gespeichert."
        } else if type == .vacation {
            successText = (initialStatus == .approved) ? "Urlaub erfolgreich eingetragen." : "Urlaubsantrag erfolgreich erstellt."
        } else {
            successText = "Samstag erfolgreich vergeben."
        }
        showToast(.success, successText)
        uiErrorMessage = nil
        return true
    }

    func requests(for date: Date) -> [LeaveRequest] {
        leaveRequests.filter { request in
            let cal = Calendar.current
            return cal.startOfDay(for: request.startDate) <= cal.startOfDay(for: date)
            && cal.startOfDay(for: request.endDate) >= cal.startOfDay(for: date)
        }
    }

    func myRequests() -> [LeaveRequest] {
        guard let user = currentUser else { return [] }
        return leaveRequests.filter { $0.user.id == user.id }
    }

    func updateStatus(for requestID: UUID, to newStatus: LeaveStatus) {
        if let index = leaveRequests.firstIndex(where: { $0.id == requestID }) {
            leaveRequests[index].status = newStatus
            leaveRequests[index].updatedAt = Date()
            leaveRequests[index].updatedByUserId = currentUser?.id
        }
    }

    /// Bearbeitungs-/Löschrechte für Abwesenheiten:
    /// - Admin: darf immer bearbeiten/löschen
    /// - Mitarbeiter/Sachverständige: nur eigene *Urlaubs*-Anträge solange sie **Offen** sind
    ///   (genehmigte/abgelehnte Anträge sowie Krankheitseinträge sind für Nicht-Admins nicht mehr änderbar)
    func canEditOrDelete(_ request: LeaveRequest, by user: User?) -> Bool {
        guard let user = user else { return false }
        if user.role == .admin { return true }

        // Nicht-Admins dürfen nur eigene offenen Urlaubsanträge ändern
        guard user.id == request.user.id else { return false }
        return request.type == .vacation && request.status == .pending
    }

    @discardableResult
    func updateLeaveRequest(_ updated: LeaveRequest) -> Bool {
        if updated.type == .vacation {
            let requestedDays = workingDays(from: updated.startDate, to: updated.endDate)
            let available = availableVacationDaysForRequests(for: updated.user, excludingRequestId: updated.id)
            if requestedDays > available {
                uiErrorMessage = "Nicht genügend Resturlaub. Verfügbar: \(available) Tag(e), angefragt: \(requestedDays) Tag(e)."
                return false
            }
        }
        // Validierung: nach Bearbeitung darf es keine Überschneidung mit anderen Einträgen geben
        if hasOverlappingLeave(for: updated.user.id,
                              start: updated.startDate,
                              end: updated.endDate,
                              newType: updated.type,
                              excludingRequestId: updated.id) {
            uiErrorMessage = "Dieser Zeitraum überschneidet sich mit einer bestehenden Abwesenheit. Änderungen wurden nicht gespeichert."
            return false
        }

        if let index = leaveRequests.firstIndex(where: { $0.id == updated.id }) {
            var patched = updated
            patched.updatedAt = Date()
            patched.updatedByUserId = currentUser?.id
            leaveRequests[index] = patched
            uiErrorMessage = nil
            return true
        }

        uiErrorMessage = "Der Antrag konnte nicht gefunden werden."
        return false
    }

    func deleteLeaveRequest(_ request: LeaveRequest) {
        leaveRequests.removeAll { $0.id == request.id }
    }

    // MARK: - Task Management

    func createTask(title: String,
                    details: String,
                    dueDate: Date?,
                    assignedUser: User,
                    creator: User) {
        let newTask = Task(
            id: UUID(),
            title: title,
            details: details,
            dueDate: dueDate,
            status: .open,
            assignedUserId: assignedUser.id,
            creatorUserId: creator.id,
            createdAt: Date()
        )
        tasks.append(newTask)
    }

    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
    }

    func toggleTaskStatus(for task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].status = (tasks[index].status == .open) ? .done : .open
        }
    }

    func deleteTask(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
    }

    func userName(for userId: UUID) -> String {
        users.first(where: { $0.id == userId })?.name ?? "Unbekannt"
    }

    func usedVacationDays(for user: User) -> Int {
        let requestsForUser = leaveRequests.filter {
            $0.user.id == user.id &&
            $0.status == .approved &&
            $0.type == .vacation
        }
        return requestsForUser.reduce(0) { partial, req in
            let days = workingDays(from: req.startDate, to: req.endDate)
            return partial + max(days, 0)
        }
    }

    func remainingLeaveDays(for user: User) -> Int {
        let used = usedVacationDays(for: user)
        return max(user.annualLeaveDays - used, 0)
    }
    
    func reservedVacationDays(for user: User, excludingRequestId: UUID? = nil) -> Int {
        let requestsForUser = leaveRequests.filter {
            $0.user.id == user.id &&
            $0.type == .vacation &&
            $0.status != .rejected &&
            (excludingRequestId == nil || $0.id != excludingRequestId!)
        }

        return requestsForUser.reduce(0) { partial, req in
            partial + max(workingDays(from: req.startDate, to: req.endDate), 0)
        }
    }

    func availableVacationDaysForRequests(for user: User, excludingRequestId: UUID? = nil) -> Int {
        let reserved = reservedVacationDays(for: user, excludingRequestId: excludingRequestId)
        return max(user.annualLeaveDays - reserved, 0)
    }
    
    private func saveCommissions() {
        if let data = try? JSONEncoder().encode(commissions) {
            UserDefaults.standard.set(data, forKey: "commissions")
        }
    }
    
    func currencyString(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "EUR"
        nf.locale = Locale(identifier: "de_DE")
        return nf.string(from: amount as NSDecimalNumber) ?? "€\(amount)"
    }
    
    func createCommission(recipientName: String,
                          recipientAddress: String,
                          amountEUR: Decimal,
                          payoutMethod: PayoutMethod,
                          payoutTarget: String) {
        guard let creator = currentUser else { return }
        guard let admin = users.first(where: { $0.role == .admin }) else { return }

        let normalizedTarget: String = {
            switch payoutMethod {
            case .paypal:
                return payoutTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            case .iban:
                return payoutTarget
                    .replacingOccurrences(of: " ", with: "")
                    .uppercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }()

        let entry = CommissionEntry(
            id: UUID(),
            recipientName: recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
            recipientAddress: recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            amountEUR: amountEUR,
            payoutMethod: payoutMethod,
            payoutTarget: normalizedTarget,
            status: .open,
            createdAt: Date(),
            createdByUserId: creator.id,
            paidAt: nil,
            paidByUserId: nil
        )

        commissions.append(entry)

        // Task beim Admin erzeugen
        let amountString = currencyString(amountEUR)
        var details = "Empfänger: \(entry.recipientName)\n"
        details += "Adresse: \(entry.recipientAddress)\n"
        details += "Betrag: \(amountString)\n"
        details += "Auszahlung: \(entry.payoutMethod.rawValue) – \(entry.payoutTarget)\n"
        details += "Gemeldet von: \(creator.name)\n"

        createTask(
            title: "Provision zahlen – \(entry.recipientName)",
            details: details,
            dueDate: nil,
            assignedUser: admin,
            creator: creator
        )
    }
    
    func commissionHistory(for user: User) -> [CommissionEntry] {
        commissions
            .filter { $0.createdByUserId == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func allCommissionHistory() -> [CommissionEntry] {
        commissions.sorted { $0.createdAt > $1.createdAt }
    }

    func markCommissionPaid(_ entry: CommissionEntry) {
        guard let admin = currentUser, admin.role == .admin else { return }
        guard let idx = commissions.firstIndex(where: { $0.id == entry.id }) else { return }
        commissions[idx].status = .paid
        commissions[idx].paidAt = Date()
        commissions[idx].paidByUserId = admin.id
    }

    // MARK: - Firestore User Profile

    @MainActor
    private func loadOrCreateProfile(for fbUser: FirebaseAuth.User) async {
        let uid = fbUser.uid
        let email = (fbUser.email ?? "").lowercased()
        let docRef = db.collection("users").document(uid)
        

        do {
            let snap = try await docRef.getDocument()

            if snap.exists {
                // Profil existiert -> in App laden
                if let data = snap.data(), let profile = UserProfile(from: data) {
                    // PIN kommt weiterhin aus der lokalen User-Liste (nur für UI/Komfort, nicht Cloud)
                    let localId = users.first(where: { $0.email.lowercased() == profile.email.lowercased() })?.id ?? UUID()

                    let mapped = profile.toUser(id: localId)
                    self.currentUser = mapped
                    self.sessionUserId = mapped.id
                    self.lastUserId = mapped.id
                    self.uiErrorMessage = nil
                    self.upsertLocalUser(mapped)
                    return
                }
            }
            
            let inviteRef = db.collection("invites").document(email)
            let inviteSnap = try await inviteRef.getDocument()

            if inviteSnap.exists, let data = inviteSnap.data(), let invited = UserProfile(from: data) {
                try await docRef.setData(invited.toDictionary(), merge: true)
                try await inviteRef.delete()

                let mapped = invited.toUser(id: UUID())
                self.currentUser = mapped
                self.sessionUserId = mapped.id
                self.lastUserId = mapped.id
                self.uiErrorMessage = nil
                return
            }

            // Profil fehlt oder konnte nicht decodiert werden -> aus lokaler Liste seed-en
            if let seed = users.first(where: { $0.email.lowercased() == email }) {
                let profile = UserProfile(from: seed)
                try await docRef.setData(profile.toDictionary(), merge: true)

                self.currentUser = seed
                self.sessionUserId = seed.id
                self.lastUserId = seed.id
                self.uiErrorMessage = nil
                self.upsertLocalUser(seed)
            } else {
                // Eingeloggt, aber kein lokales Seed-Profil vorhanden
                let isBootstrapAdmin = (email.lowercased() == "hussein@sv-souleiman.de")
                let fallback = UserProfile(
                    name: fbUser.displayName ?? email,
                    roleRaw: isBootstrapAdmin ? UserRole.admin.rawValue : UserRole.employee.rawValue,
                    colorName: "blue",
                    annualLeaveDays: 30,
                    email: email
                )
                try await docRef.setData(fallback.toDictionary(), merge: true)

                let mapped = fallback.toUser(id: UUID())
                self.currentUser = mapped
                self.sessionUserId = mapped.id
                self.lastUserId = mapped.id
                self.uiErrorMessage = isBootstrapAdmin ? nil : "Mitarbeiter-Profil wurde neu angelegt. Bitte im Admin-Bereich prüfen."
                self.upsertLocalUser(mapped)
            }
        } catch {
            self.uiErrorMessage = "Firestore Profil konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    private func upsertLocalUser(_ user: User) {
        if let idx = users.firstIndex(where: { $0.email.lowercased() == user.email.lowercased() }) {
            users[idx] = user
        } else {
            users.append(user)
        }
    }
}
