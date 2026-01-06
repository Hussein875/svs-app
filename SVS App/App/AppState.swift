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

    func toUser(id: String) -> User {
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
    
    // Firestore listeners
    private var usersListener: ListenerRegistration?
    private var invitesListener: ListenerRegistration?
    private var leaveRequestsListener: ListenerRegistration?
    private var tasksListener: ListenerRegistration?
    
    // Run snapshot processing off the main thread
    private let firestoreListenerQueue = DispatchQueue(label: "svs.firestore.listeners", qos: .userInitiated)
    
    // Snapshot caches (so we can merge sources)
    private var usersSnapshotCache: [User] = []
    private var invitesSnapshotCache: [User] = []
    
    @Published var auth = AuthManager()
    
    @Published var users: [User] = []
    
    @Published var currentUser: User?
    @Published var leaveRequests: [LeaveRequest]
    @Published var tasks: [Task] = []
    @Published var uiErrorMessage: String? = nil
    
    @Published var commissions: [CommissionEntry]
    
    @Published var toast: AppToast? = nil

    // Listener lifecycle
    @Published var isProfileReady: Bool = false
    private var didStartRealtimeListeners: Bool = false
    
    func showToast(_ kind: ToastKind, _ message: String) {
        toast = AppToast(kind: kind, message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.toast?.message == message {
                self?.toast = nil
            }
        }
    }
    
    init() {
        
        self.users = []
        
        // NOTE: Local persistence via UserDefaults removed.
        // These collections will be sourced from Firestore.
        self.leaveRequests = []
        self.commissions = []
        self.tasks = []
        
        // Firebase Auth -> Firestore Profil laden/anlegen (Quelle der Wahrheit für Profil-Daten)
        auth.$user
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fbUser in
                guard let self else { return }
                
                // Wenn ausgeloggt: lokalen User leeren + Session IDs zurücksetzen
                guard let fbUser else {
                    self.currentUser = nil
                    self.stopUsersListeners()
                    self.users = []
                    self.isProfileReady = false
                    self.didStartRealtimeListeners = false
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

    func stopRealtimeListeners() {
        stopUsersListeners()
        // später: stopTasksListener(), stopCommissionsListener()
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            uiErrorMessage = "Logout fehlgeschlagen: \(error.localizedDescription)"
        }
        currentUser = nil
        stopUsersListeners()
        users = []
        isProfileReady = false
        didStartRealtimeListeners = false
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
    
    // UI helper: Re-fetch the current user's profile from Firestore.
    // Used by the loading screen retry button.
    @MainActor
    func refreshCurrentUserProfile() async {
        guard let fbUser = auth.user else { return }
        await loadOrCreateProfile(for: fbUser)
    }
    
    func addUser(name: String, role: UserRole, colorName: String, annualLeaveDays: Int, email: String) {
        let newUser = User(
            id: "invite:\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())",
            name: name,
            role: role,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        users.append(newUser)
    }
    
    func updateUser(_ user: User) {
        // 1) Local UI state
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        } else {
            // If the user isn't in the list yet, append (keeps UI resilient)
            users.append(user)
        }
        
        // Keep embedded user copies in existing requests consistent
        leaveRequests = leaveRequests.map { request in
            if request.user.id == user.id {
                var updated = request
                updated.user = user
                return updated
            } else {
                return request
            }
        }
        
        // 2) Cloud sync (Admin only)
        guard currentUser?.role == .admin else { return }
        
        let cleanEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else { return }
        
        let profile = UserProfile(from: user)
        
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                // Keep invite record in sync (for users who haven't logged in yet)
                try await self.db.collection("invites").document(cleanEmail)
                    .setData(profile.toDictionary(), merge: true)
                
                // Update existing profile(s) in users collection (source of truth after first login)
                let qs = try await self.db.collection("users")
                    .whereField("email", isEqualTo: cleanEmail)
                    .getDocuments()
                
                for doc in qs.documents {
                    try await self.db.collection("users").document(doc.documentID)
                        .setData(profile.toDictionary(), merge: true)
                }
                
                await MainActor.run { self.uiErrorMessage = nil }
            } catch {
                await MainActor.run {
                    self.uiErrorMessage = "Profil konnte nicht gespeichert werden: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func deleteUser(_ user: User) {
        // 1) Local UI state
        users.removeAll { $0.id == user.id }
        
        // Also remove embedded user copies in leave requests (optional: keep historical; here we remove requests)
        // If you want to keep history, comment this out.
        leaveRequests.removeAll { $0.user.id == user.id }
        
        // 2) Cloud delete (Admin only)
        guard currentUser?.role == .admin else { return }
        
        let cleanEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else { return }
        
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                // Remove invite record
                try await self.db.collection("invites").document(cleanEmail).delete()
                
                // Remove profile(s) from users collection
                let qs = try await self.db.collection("users")
                    .whereField("email", isEqualTo: cleanEmail)
                    .getDocuments()
                
                for doc in qs.documents {
                    try await self.db.collection("users").document(doc.documentID).delete()
                }
                
                await MainActor.run { self.uiErrorMessage = nil }
            } catch {
                await MainActor.run {
                    self.uiErrorMessage = "Profil konnte nicht gelöscht werden: \(error.localizedDescription)"
                }
            }
        }
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
    private func hasOverlappingLeave(for userId: String,
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
        upsertLeaveRequestToFirestore(request)
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
            upsertLeaveRequestToFirestore(leaveRequests[index])
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

    /// Task-Rechte:
    /// - Admin: darf immer bearbeiten/löschen
    /// - Nicht-Admins: dürfen bearbeiten/löschen, wenn Task ihnen zugewiesen ist
    func canEditTask(_ task: Task, by user: User?) -> Bool {
        guard let user else { return false }
        if user.role == .admin { return true }
        return task.assignedUserId == user.id
    }

    func canDeleteTask(_ task: Task, by user: User?) -> Bool {
        // Aktuell identisch zu canEditTask – separiert für spätere Regeln
        canEditTask(task, by: user)
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
            upsertLeaveRequestToFirestore(patched)
            uiErrorMessage = nil
            return true
        }
        
        uiErrorMessage = "Der Antrag konnte nicht gefunden werden."
        return false
    }
    
    func deleteLeaveRequest(_ request: LeaveRequest) {
        deleteLeaveRequestFromFirestore(request)
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
            createdAt: Date(),
            updatedAt: nil
        )

        // Optimistic UI
        tasks.insert(newTask, at: 0)
        upsertTaskToFirestore(newTask)
    }

    func updateTask(_ task: Task) {
        guard canEditTask(task, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht bearbeiten.")
            return
        }

        var patched = task
        patched.updatedAt = Date()

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = patched
        } else {
            tasks.insert(patched, at: 0)
        }

        upsertTaskToFirestore(patched)
    }

    func toggleTaskStatus(for task: Task) {
        guard canEditTask(task, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht ändern.")
            return
        }

        var updated = task
        updated.status = (task.status == .open) ? .done : .open
        updateTask(updated)
    }

    func deleteTask(_ task: Task) {
        guard canDeleteTask(task, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht löschen.")
            return
        }

        deleteTaskFromFirestore(task)
        tasks.removeAll { $0.id == task.id }
    }
    
    func userName(for userId: String) -> String {
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
    
    // MARK: - Firestore Tasks DTO

    private struct TaskDTO {
        var id: String
        var title: String
        var details: String
        var dueDate: Timestamp?
        var statusRaw: String
        var assignedUserId: String
        var creatorUserId: String
        var createdAt: Timestamp
        var updatedAt: Timestamp?

        init?(id: String, data: [String: Any]) {
            guard
                let title = data["title"] as? String,
                let details = data["details"] as? String,
                let statusRaw = data["statusRaw"] as? String,
                let assignedUserId = data["assignedUserId"] as? String,
                let creatorUserId = data["creatorUserId"] as? String,
                let createdAt = data["createdAt"] as? Timestamp
            else { return nil }

            self.id = id
            self.title = title
            self.details = details
            self.statusRaw = statusRaw
            self.assignedUserId = assignedUserId
            self.creatorUserId = creatorUserId
            self.createdAt = createdAt
            self.dueDate = data["dueDate"] as? Timestamp
            self.updatedAt = data["updatedAt"] as? Timestamp
        }

        init(from task: Task) {
            self.id = task.id.uuidString
            self.title = task.title
            self.details = task.details
            self.statusRaw = task.status.rawValue
            self.assignedUserId = task.assignedUserId
            self.creatorUserId = task.creatorUserId
            self.createdAt = Timestamp(date: task.createdAt)
            self.dueDate = task.dueDate.map { Timestamp(date: $0) }
            self.updatedAt = task.updatedAt.map { Timestamp(date: $0) }
        }

        func toDictionary() -> [String: Any] {
            var d: [String: Any] = [
                "title": title,
                "details": details,
                "statusRaw": statusRaw,
                "assignedUserId": assignedUserId,
                "creatorUserId": creatorUserId,
                "createdAt": createdAt
            ]
            if let dueDate { d["dueDate"] = dueDate }
            if let updatedAt { d["updatedAt"] = updatedAt }
            return d
        }
    }

    // MARK: - Firestore Tasks Listener

    private func startTasksListenerIfNeeded() {
        guard tasksListener == nil else { return }
        guard let me = currentUser else { return }

        var query: Query = db.collection("tasks")

        // Admin: sieht alles, andere: nur zugewiesene Tasks
        if me.role != .admin {
            query = query.whereField("assignedUserId", isEqualTo: me.id)
        }

        query = query.order(by: "createdAt", descending: true)

        tasksListener = query.addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Tasks konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }

                let mapped: [Task] = docs.compactMap { doc in
                    guard let dto = TaskDTO(id: doc.documentID, data: doc.data()) else { return nil }
                    guard let uuid = UUID(uuidString: dto.id) else { return nil }

                    let status = TaskStatus(rawValue: dto.statusRaw) ?? .open

                    return Task(
                        id: uuid,
                        title: dto.title,
                        details: dto.details,
                        dueDate: dto.dueDate?.dateValue(),
                        status: status,
                        assignedUserId: dto.assignedUserId,
                        creatorUserId: dto.creatorUserId,
                        createdAt: dto.createdAt.dateValue(),
                        updatedAt: dto.updatedAt?.dateValue()
                    )
                }

                DispatchQueue.main.async { [weak self] in
                    self?.tasks = mapped
                }
            }
        }
    }

    private func upsertTaskToFirestore(_ task: Task) {
        let dto = TaskDTO(from: task)

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("tasks").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
                print("[Firestore][tasks][upsert] OK for \(dto.id)")
            } catch {
                let msg = "Task konnte nicht gespeichert werden: \(error.localizedDescription)"
                print("[Firestore][tasks][upsert] FAILED for \(dto.id): \(msg)")
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func deleteTaskFromFirestore(_ task: Task) {
        let docId = task.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("tasks").document(docId).delete()
            } catch {
                let msg = "Task konnte nicht gelöscht werden: \(error.localizedDescription)"
                print("[Firestore][tasks][delete] FAILED for \(docId): \(msg)")
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }
    
    // MARK: - Firestore LeaveRequests DTO
    
    private struct LeaveRequestDTO {
        var id: String
        var userEmail: String
        var startDate: Timestamp
        var endDate: Timestamp
        var typeRaw: String
        var reason: String
        var statusRaw: String
        var createdAt: Timestamp
        var createdByEmail: String
        var updatedAt: Timestamp?
        var updatedByEmail: String?
        var userId: String?
        var createdByUid: String?
        var updatedByUid: String?
        
        init?(id: String, data: [String: Any]) {
            guard
                let userEmail = data["userEmail"] as? String,
                let startDate = data["startDate"] as? Timestamp,
                let endDate = data["endDate"] as? Timestamp,
                let typeRaw = data["typeRaw"] as? String,
                let reason = data["reason"] as? String,
                let statusRaw = data["statusRaw"] as? String,
                let createdAt = data["createdAt"] as? Timestamp,
                let createdByEmail = data["createdByEmail"] as? String
            else { return nil }
            
            self.id = id
            self.userEmail = userEmail
            self.startDate = startDate
            self.endDate = endDate
            self.typeRaw = typeRaw
            self.reason = reason
            self.statusRaw = statusRaw
            self.createdAt = createdAt
            self.createdByEmail = createdByEmail
            self.updatedAt = data["updatedAt"] as? Timestamp
            self.updatedByEmail = data["updatedByEmail"] as? String
            self.userId = data["userId"] as? String
            self.createdByUid = data["createdByUid"] as? String
            self.updatedByUid = data["updatedByUid"] as? String
        }
        
        init(from request: LeaveRequest, currentActorEmail: String) {
            self.id = request.id.uuidString
            self.userEmail = request.user.email.lowercased()
            self.startDate = Timestamp(date: request.startDate)
            self.endDate = Timestamp(date: request.endDate)
            self.typeRaw = request.type.rawValue
            self.reason = request.reason
            self.statusRaw = request.status.rawValue
            self.createdAt = Timestamp(date: request.createdAt)
            self.createdByEmail = currentActorEmail

            // Firebase UID references (preferred)
            self.userId = request.user.id
            self.createdByUid = request.createdByUserId

            if let u = request.updatedAt {
                self.updatedAt = Timestamp(date: u)
            } else {
                self.updatedAt = nil
            }
            self.updatedByEmail = nil
            self.updatedByUid = request.updatedByUserId
        }
        
        func toDictionary() -> [String: Any] {
            var d: [String: Any] = [
                // Keep email fields for compatibility/debugging
                "userEmail": userEmail,
                "startDate": startDate,
                "endDate": endDate,
                "typeRaw": typeRaw,
                "reason": reason,
                "statusRaw": statusRaw,
                "createdAt": createdAt,
                "createdByEmail": createdByEmail
            ]

            // Preferred UID fields
            if let userId { d["userId"] = userId }
            if let createdByUid { d["createdByUid"] = createdByUid }
            if let updatedByUid { d["updatedByUid"] = updatedByUid }

            if let updatedAt { d["updatedAt"] = updatedAt }
            if let updatedByEmail { d["updatedByEmail"] = updatedByEmail }

            return d
        }
    }
    
    // MARK: - Firestore User Profile
    
    private func loadOrCreateProfile(for fbUser: FirebaseAuth.User) async {
        let uid = fbUser.uid
        let email = (fbUser.email ?? "").lowercased()
        let docRef = db.collection("users").document(uid)

        do {
            // 1) Try users/<uid>
            let snap = try await docRef.getDocument()
            if snap.exists, let data = snap.data(), let profile = UserProfile(from: data) {
                let mapped = profile.toUser(id: uid)
                await MainActor.run {
                    self.currentUser = mapped
                    self.uiErrorMessage = nil
                    self.isProfileReady = true
                    self.didStartRealtimeListeners = false

                    // Start listeners shortly after login/profile load.
                    // This fixes the situation where the main view does not trigger `startRealtimeListenersIfNeeded()`.
                    // Use a small delay to avoid blocking initial UI/keyboard setup.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        guard let self else { return }
                        // Ensure we are still logged in with the same user
                        guard self.currentUser?.id == uid, self.auth.user != nil else { return }
                        self.startRealtimeListenersIfNeeded()
                    }
                }
                return
            }

            // 2) Try invites/<email> (pre-created by admin)
            let inviteRef = db.collection("invites").document(email)
            let inviteSnap = try await inviteRef.getDocument()
            if inviteSnap.exists, let data = inviteSnap.data(), let invited = UserProfile(from: data) {
                try await docRef.setData(invited.toDictionary(), merge: true)
                try await inviteRef.delete()

                let mapped = invited.toUser(id: uid)
                await MainActor.run {
                    self.currentUser = mapped
                    self.uiErrorMessage = nil
                    self.isProfileReady = true
                    self.didStartRealtimeListeners = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        guard let self else { return }
                        guard self.currentUser?.id == uid, self.auth.user != nil else { return }
                        self.startRealtimeListenersIfNeeded()
                    }
                }
                return
            }

            // 3) No profile yet -> create fallback
            let isBootstrapAdmin = (email == "hussein@sv-souleiman.de")
            let fallback = UserProfile(
                name: fbUser.displayName ?? email,
                roleRaw: isBootstrapAdmin ? UserRole.admin.rawValue : UserRole.employee.rawValue,
                colorName: "blue",
                annualLeaveDays: 30,
                email: email
            )
            try await docRef.setData(fallback.toDictionary(), merge: true)

            let mapped = fallback.toUser(id: uid)
            await MainActor.run {
                self.currentUser = mapped
                self.isProfileReady = true
                self.didStartRealtimeListeners = false
                self.uiErrorMessage = isBootstrapAdmin ? nil : "Mitarbeiter-Profil wurde neu angelegt. Bitte im Admin-Bereich prüfen."

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self else { return }
                    guard self.currentUser?.id == uid, self.auth.user != nil else { return }
                    self.startRealtimeListenersIfNeeded()
                }
            }
        } catch {
            await MainActor.run {
                self.isProfileReady = false
                self.uiErrorMessage = "Firestore Profil konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }
    
    private func mergeUserSnapshotsAndPublish() {
        // Merge by email (users wins over invites)
        var byEmail: [String: User] = [:]
        
        for u in invitesSnapshotCache {
            byEmail[u.email.lowercased()] = u
        }
        for u in usersSnapshotCache {
            byEmail[u.email.lowercased()] = u
        }
        
        let merged = Array(byEmail.values)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // Only publish when the content actually changed (prevents SwiftUI churn)
        let current = self.users
        if current.count == merged.count {
            var same = true
            for (a, b) in zip(current, merged) {
                if a.email.lowercased() != b.email.lowercased() ||
                    a.name != b.name ||
                    a.role != b.role ||
                    a.colorName != b.colorName ||
                    a.annualLeaveDays != b.annualLeaveDays {
                    same = false
                    break
                }
            }
            if same { return }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.users = merged
        }
    }
    
    private func stopUsersListeners() {
        usersListener?.remove(); usersListener = nil
        invitesListener?.remove(); invitesListener = nil
        leaveRequestsListener?.remove(); leaveRequestsListener = nil
        tasksListener?.remove(); tasksListener = nil
        usersSnapshotCache = []
        invitesSnapshotCache = []
        leaveRequests = []
        tasks = []
        didStartRealtimeListeners = false
        isProfileReady = false
    }

    /// Startet Firestore-Listener bewusst erst dann, wenn die Hauptansicht sichtbar ist.
    /// Das verhindert UI-Lags beim Login/Keyboard-Aufbau.
    func startRealtimeListenersIfNeeded() {
        guard currentUser != nil else { return }
        guard isProfileReady else { return }
        guard didStartRealtimeListeners == false else { return }

        didStartRealtimeListeners = true
        startUsersListenersIfNeeded()
        startLeaveRequestsListenerIfNeeded()
        startTasksListenerIfNeeded()
    }
    
    private func startUsersListenersIfNeeded() {
        // Avoid duplicate listeners
        if usersListener != nil { return }
        
        // Always listen to actual profiles in users/<uid>
        usersListener = db.collection("users").addSnapshotListener(includeMetadataChanges: false) { [weak self] (snapshot: QuerySnapshot?, error: Error?) in
            guard let self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Users konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }
            
            // Process snapshots off the main thread to keep the UI responsive
            let docs = snapshot?.documents ?? []
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.usersSnapshotCache = docs.compactMap { (doc: QueryDocumentSnapshot) in
                    guard let profile = UserProfile(from: doc.data()) else { return nil }
                    return profile.toUser(id: doc.documentID)
                }
                self.mergeUserSnapshotsAndPublish()
            }
        }
        
        // Admins also see pre-created invites (accounts that have not logged in yet)
        if currentUser?.role == .admin {
            invitesListener = db.collection("invites").addSnapshotListener(includeMetadataChanges: false) { [weak self] (snapshot: QuerySnapshot?, error: Error?) in
                guard let self else { return }
                if let error = error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "Invites konnten nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }
                
                let docs = snapshot?.documents ?? []
                self.firestoreListenerQueue.async { [weak self] in
                    guard let self else { return }
                    self.invitesSnapshotCache = docs.compactMap { doc in
                        guard let profile = UserProfile(from: doc.data()) else { return nil }
                        return profile.toUser(id: "invite:\(profile.email.lowercased())")
                    }
                    self.mergeUserSnapshotsAndPublish()
                }
            }
        }
    }
    
    // MARK: - Firestore LeaveRequests Listener
    
    private func startLeaveRequestsListenerIfNeeded() {
        guard leaveRequestsListener == nil else { return }
        guard let me = currentUser else { return }

        var query: Query = db.collection("leaveRequests")

        // Admin: see all.
        // Employee/Expert: prefer filtering by Firebase UID. If older records don't have `userId` yet,
        // fall back to filtering by `userEmail` until the data is fully migrated.
        if me.role != .admin {
            // If the current user is an invite (no real UID yet), we must filter by email.
            // Otherwise prefer UID filtering.
            if me.id.hasPrefix("invite:") {
                query = query.whereField("userEmail", isEqualTo: me.email.lowercased())
            } else {
                query = query.whereField("userId", isEqualTo: me.id)
            }
        }

        // Sort for stable UI
        query = query.order(by: "startDate", descending: false)

        leaveRequestsListener = query.addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Abwesenheiten konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }

                // Build lookup maps once per snapshot for performance.
                let usersById: [String: User] = Dictionary(uniqueKeysWithValues: self.users.map { ($0.id, $0) })
                let usersByEmail: [String: User] = Dictionary(uniqueKeysWithValues: self.users.map { ($0.email.lowercased(), $0) })

                let mapped: [LeaveRequest] = docs.compactMap { (doc: QueryDocumentSnapshot) -> LeaveRequest? in
                    guard let dto = LeaveRequestDTO(id: doc.documentID, data: doc.data()) else { return nil }
                    guard let id = UUID(uuidString: dto.id) else { return nil }

                    // Prefer resolving by UID; fall back to email for older records.
                    let email = dto.userEmail.lowercased()
                    let resolvedUser: User = {
                        if let uid = dto.userId, let u = usersById[uid] {
                            return u
                        }
                        if let u = usersByEmail[email] {
                            return u
                        }
                        // Minimal fallback (keeps list consistent even if users list loads later)
                        return User(
                            id: dto.userId ?? "invite:\(email)",
                            name: email,
                            role: .employee,
                            colorName: "blue",
                            annualLeaveDays: 30,
                            email: email
                        )
                    }()

                    let type = LeaveType(rawValue: dto.typeRaw) ?? .vacation
                    let status = LeaveStatus(rawValue: dto.statusRaw) ?? .pending

                    return LeaveRequest(
                        id: id,
                        user: resolvedUser,
                        startDate: dto.startDate.dateValue(),
                        endDate: dto.endDate.dateValue(),
                        type: type,
                        reason: dto.reason,
                        status: status,
                        createdAt: dto.createdAt.dateValue(),
                        createdByUserId: dto.createdByUid ?? "invite:\(dto.createdByEmail.lowercased())",
                        updatedAt: dto.updatedAt?.dateValue(),
                        updatedByUserId: dto.updatedByUid ?? dto.updatedByEmail.map { "invite:\($0.lowercased())" }
                    )
                }

                DispatchQueue.main.async { [weak self] in
                    self?.leaveRequests = mapped
                }
            }
        }
    }
    
    private func upsertLeaveRequestToFirestore(_ request: LeaveRequest) {
        guard let actorEmail = currentUser?.email.lowercased() else { return }
        guard let actorUid = Auth.auth().currentUser?.uid else { return }

        var patched = request
        // Ensure audit UIDs are set
        if patched.createdByUserId.isEmpty { patched.createdByUserId = actorUid }
        if patched.updatedByUserId == nil, patched.updatedAt != nil { patched.updatedByUserId = actorUid }

        let dto = LeaveRequestDTO(from: patched, currentActorEmail: actorEmail)

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("leaveRequests").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
            } catch {
                await MainActor.run {
                    self.uiErrorMessage = "Abwesenheit konnte nicht gespeichert werden: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteLeaveRequestFromFirestore(_ request: LeaveRequest) {
        let docId = request.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("leaveRequests").document(docId).delete()
            } catch {
                await MainActor.run {
                    self.uiErrorMessage = "Abwesenheit konnte nicht gelöscht werden: \(error.localizedDescription)"
                }
            }
        }
    }
}
