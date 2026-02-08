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
    var birthday: Date?

    init(name: String,
         roleRaw: String,
         colorName: String,
         annualLeaveDays: Int,
         email: String,
         birthday: Date? = nil) {
        self.name = name
        self.roleRaw = roleRaw
        self.colorName = colorName
        self.annualLeaveDays = annualLeaveDays
        self.email = email
        self.birthday = birthday
    }

    init(from user: User) {
        self.name = user.name
        self.roleRaw = user.role.rawValue
        self.colorName = user.colorName
        self.annualLeaveDays = user.annualLeaveDays
        self.email = user.email
        self.birthday = user.birthday
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
        if let ts = data["birthday"] as? Timestamp {
            self.birthday = ts.dateValue()
        } else if let d = data["birthday"] as? Date {
            self.birthday = d
        } else if let s = data["birthday"] as? String {
            let iso = ISO8601DateFormatter()
            self.birthday = iso.date(from: s)
        } else {
            self.birthday = nil
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "roleRaw": roleRaw,
            "colorName": colorName,
            "annualLeaveDays": annualLeaveDays,
            "email": email
        ]
        if let birthday {
            dict["birthday"] = Timestamp(date: birthday)
        }
        return dict
    }

    func toUser(id: String) -> User {
        User(
            id: id,
            name: name,
            role: UserRole(rawValue: roleRaw) ?? .employee,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: email,
            birthday: birthday
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
    private var approvedLeaveRequestsListener: ListenerRegistration?
    private var tasksListener: ListenerRegistration?
    private var tasksCreatedByMeListener: ListenerRegistration?
    private var commissionsListener: ListenerRegistration?
    
    // Run snapshot processing off the main thread
    private let firestoreListenerQueue = DispatchQueue(label: "svs.firestore.listeners", qos: .userInitiated)
    
    // Snapshot caches (so we can merge sources)
    private var usersSnapshotCache: [User] = []
    private var invitesSnapshotCache: [User] = []
    private var leaveRequestsOwnSnapshotCache: [LeaveRequest] = []
    private var leaveRequestsApprovedSnapshotCache: [LeaveRequest] = []
    private var tasksAssignedSnapshotCache: [Task] = []
    private var tasksCreatedByMeSnapshotCache: [Task] = []
    private var pendingTaskWritesById: [UUID: Task] = [:]
    private var pendingTaskDeletionIds: Set<UUID> = []
    
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
                
                // Logged in: reset readiness and trigger bootstrap
                self.isProfileReady = false
                self.uiErrorMessage = nil

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
                                    annualLeaveDays: Int,
                                    birthday: Date? = nil) async {
        let functions = Functions.functions(region: "us-central1")
        let iso = ISO8601DateFormatter()
        let birthdayISO = birthday.map { iso.string(from: $0) }
        
        do {
            var payload: [String: Any] = [
                "name": name,
                "email": email,
                "roleRaw": role.rawValue,
                "colorName": colorName,
                "annualLeaveDays": annualLeaveDays
            ]
            if let birthdayISO {
                payload["birthdayISO"] = birthdayISO
            }

            let result = try await functions.httpsCallable("adminCreateUserInvite").call(payload)
            
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
                                annualLeaveDays: Int,
                                birthday: Date? = nil) async {
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
            email: cleanEmail,
            birthday: birthday
        )
        var profileData = profile.toDictionary()
        if birthday == nil {
            profileData["birthday"] = FieldValue.delete()
        }
        
        do {
            // Admin legt zunächst ein Invite an (Quelle: E-Mail). Beim ersten Login wird es nach users/<uid> übernommen.
            try await db.collection("invites").document(cleanEmail).setData(profileData, merge: true)
            self.uiErrorMessage = nil
        } catch {
            self.uiErrorMessage = "Profil konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
    
    // Public entry point to (re)load or create the Firestore user profile
    @MainActor
    func bootstrapCurrentUserIfNeeded() {
        guard let fbUser = auth.user else { return }
        isProfileReady = false
        uiErrorMessage = nil

        _Concurrency.Task { [weak self] in
            await self?.loadOrCreateProfile(for: fbUser)
        }
    }

    // UI helper: Re-fetch the current user's profile from Firestore.
    // Used by the loading screen retry button.
    @MainActor
    func refreshCurrentUserProfile() async {
        guard let fbUser = auth.user else { return }
        await loadOrCreateProfile(for: fbUser)
    }
    
    func addUser(name: String,
                 role: UserRole,
                 colorName: String,
                 annualLeaveDays: Int,
                 email: String,
                 birthday: Date? = nil) {
        let newUser = User(
            id: "invite:\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())",
            name: name,
            role: role,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            birthday: birthday
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
        guard currentUser?.role == .admin else {
            uiErrorMessage = "Nur Admins dürfen Benutzer bearbeiten."
            return
        }
        
        let cleanEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else { return }
        let isInviteOnly = user.id.hasPrefix("invite:")
        
        let profile = UserProfile(from: user)
        var profileData = profile.toDictionary()
        if user.birthday == nil {
            profileData["birthday"] = FieldValue.delete()
        }
        
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                // Primary update path: write the concrete users/<uid> doc directly.
                // This is the source of truth for existing accounts.
                if !isInviteOnly {
                    try await self.db.collection("users").document(user.id)
                        .setData(profileData, merge: true)
                }
                
                // Legacy safety net: also update matching docs by email.
                let qs = try await self.db.collection("users")
                    .whereField("email", isEqualTo: cleanEmail)
                    .getDocuments()
                
                for doc in qs.documents {
                    try await self.db.collection("users").document(doc.documentID)
                        .setData(profileData, merge: true)
                }

                // Keep invite record in sync for not-yet-activated users.
                // Best effort: invite write should not block editing existing users.
                do {
                    try await self.db.collection("invites").document(cleanEmail)
                        .setData(profileData, merge: true)
                } catch {
                    #if DEBUG
                    print("[updateUser] invite sync skipped:", error.localizedDescription)
                    #endif
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
        // Cloud delete (Admin only)
        guard currentUser?.role == .admin else {
            uiErrorMessage = "Nur Admins dürfen Benutzer löschen."
            return
        }

        let cleanEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let isInviteOnly = user.id.hasPrefix("invite:")

                // Delete Firebase Auth account for real users to prevent re-login.
                if !isInviteOnly {
                    let functions = Functions.functions(region: "us-central1")
                    _ = try await functions.httpsCallable("adminDeleteUser").call([
                        "uid": user.id
                    ])
                }

                // Remove invite record (if known)
                if !cleanEmail.isEmpty {
                    try await self.db.collection("invites").document(cleanEmail).delete()
                }

                // Remove profile doc by uid when this is a real account.
                if !isInviteOnly {
                    try await self.db.collection("users").document(user.id).delete()
                }

                // Remove possible duplicates by email (legacy safety net).
                if !cleanEmail.isEmpty {
                    let qs = try await self.db.collection("users")
                        .whereField("email", isEqualTo: cleanEmail)
                        .getDocuments()

                    for doc in qs.documents {
                        try await self.db.collection("users").document(doc.documentID).delete()
                    }
                }
                
                await MainActor.run {
                    self.users.removeAll { $0.id == user.id }
                    self.leaveRequests.removeAll { $0.user.id == user.id }
                    self.uiErrorMessage = nil
                }
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
        return createLeaveRequest(start: start, end: end, type: type, for: user)
    }
    
    /// Admin kann Anträge für andere Benutzer anlegen.
    /// - Urlaub: optional sofort genehmigen.
    /// - Krankheit: wird immer sofort eingetragen (Genehmigt), unabhängig vom Toggle.
    @discardableResult
    func createLeaveRequest(start: Date,
                            end: Date,
                            type: LeaveType,
                            for user: User) -> Bool {
        
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
        // - Krankheit: immer direkt eingetragen (genehmigt)
        // - Bereitschaft: sofort wirksam (genehmigt), damit sie im Kalender für alle sichtbar ist
        // - Urlaub: offen
        let initialStatus: LeaveStatus
        if type == .sick || type == .onCallSaturday {
            initialStatus = .approved
        } else {
            initialStatus = .pending
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

    private func normalizedIdentity(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canonicalCurrentUid(fallback user: User?) -> String? {
        let authUid = normalizedIdentity(Auth.auth().currentUser?.uid)
        if !authUid.isEmpty { return authUid }

        let userId = normalizedIdentity(user?.id)
        if !userId.isEmpty { return userId }
        return nil
    }

    private func currentIdentitySet(for user: User?) -> Set<String> {
        var ids = Set<String>()

        let authUid = normalizedIdentity(Auth.auth().currentUser?.uid)
        if !authUid.isEmpty { ids.insert(authUid) }

        let userId = normalizedIdentity(user?.id)
        if !userId.isEmpty { ids.insert(userId) }

        return ids
    }

    private func legacyIdentitySet(for user: User?) -> Set<String> {
        var ids = Set<String>()
        let email = normalizedIdentity(user?.email).lowercased()
        if email.isEmpty { return ids }
        ids.insert(email)
        ids.insert("invite:\(email)")
        return ids
    }

    private func taskCreatorMatchesCurrentUser(_ task: Task, by user: User?) -> Bool {
        let creator = normalizedIdentity(task.creatorUserId)
        if creator.isEmpty { return false }

        if currentIdentitySet(for: user).contains(creator) {
            return true
        }

        return legacyIdentitySet(for: user).contains(creator.lowercased())
    }

    private func taskAssigneeMatchesCurrentUser(_ task: Task, by user: User?) -> Bool {
        let assigned = normalizedIdentity(task.assignedUserId)
        if assigned.isEmpty { return false }
        return currentIdentitySet(for: user).contains(assigned)
    }

    /// Task-Rechte:
    /// - Admin: darf immer bearbeiten/löschen
    /// - Nicht-Admins: dürfen bearbeiten, wenn sie Ersteller ODER Zuständiger sind
    func canEditTask(_ task: Task, by user: User?) -> Bool {
        guard let user else { return false }
        if user.role == .admin { return true }
        return taskAssigneeMatchesCurrentUser(task, by: user) ||
               taskCreatorMatchesCurrentUser(task, by: user)
    }

    func canDeleteTask(_ task: Task, by user: User?) -> Bool {
        // Keep client behavior aligned with Firestore rules.
        guard let user else { return false }
        if user.role == .admin { return true }
        return taskCreatorMatchesCurrentUser(task, by: user)
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
        let creatorUid = canonicalCurrentUid(fallback: creator) ?? creator.id
        let assignedUid = normalizedIdentity(assignedUser.id)

        let newTask = Task(
            id: UUID(),
            title: title,
            details: details,
            dueDate: dueDate,
            status: .open,
            assignedUserId: assignedUid.isEmpty ? assignedUser.id : assignedUid,
            creatorUserId: normalizedIdentity(creatorUid),
            createdAt: Date(),
            updatedAt: nil
        )

        // Optimistic UI
        pendingTaskDeletionIds.remove(newTask.id)
        pendingTaskWritesById[newTask.id] = newTask
        mergeTaskSnapshotsAndPublish()
        upsertTaskToFirestore(newTask)
    }

    func updateTask(_ task: Task) {
        guard canEditTask(task, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht bearbeiten.")
            return
        }

        var patched = task
        patched.updatedAt = Date()

        pendingTaskDeletionIds.remove(patched.id)
        pendingTaskWritesById[patched.id] = patched
        mergeTaskSnapshotsAndPublish()

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

        pendingTaskWritesById.removeValue(forKey: task.id)
        pendingTaskDeletionIds.insert(task.id)
        mergeTaskSnapshotsAndPublish()
        deleteTaskFromFirestore(task)
    }

    @MainActor
    func refreshTasksFromServer() async {
        guard let me = currentUser else { return }
        guard let meUid = canonicalCurrentUid(fallback: me), !meUid.isEmpty else { return }

        do {
            if me.role == .admin {
                let snap = try await db.collection("tasks")
                    .order(by: "createdAt", descending: true)
                    .getDocuments(source: .server)

                tasksAssignedSnapshotCache = mapTasksFromDocs(snap.documents)
                tasksCreatedByMeSnapshotCache = []
                mergeTaskSnapshotsAndPublish()
            } else {
                async let assignedSnap = db.collection("tasks")
                    .whereField("assignedUserId", isEqualTo: meUid)
                    .getDocuments(source: .server)

                async let createdSnap = db.collection("tasks")
                    .whereField("creatorUserId", isEqualTo: meUid)
                    .getDocuments(source: .server)

                let (assigned, created) = try await (assignedSnap, createdSnap)
                tasksAssignedSnapshotCache = mapTasksFromDocs(assigned.documents)
                tasksCreatedByMeSnapshotCache = mapTasksFromDocs(created.documents)
                mergeTaskSnapshotsAndPublish()
            }

            uiErrorMessage = nil
        } catch {
            let msg = "Tasks konnten nicht aktualisiert werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
        }
    }
    
    // MARK: - Firestore Commissions DTO

    private struct CommissionDTO {
        var id: String
        var recipientName: String
        var recipientAddress: String
        var amount: Double
        var payoutMethodRaw: String
        var payoutTarget: String
        var statusRaw: String
        var createdAt: Timestamp
        var createdByUid: String
        var paidAt: Timestamp?
        var paidByUid: String?

        init?(id: String, data: [String: Any]) {
            // Support both the legacy schema (recipientName/recipientAddress/...) and
            // the newer "provision" schema (recommenderName, recommenderStreet, payoutIban, etc.).

            // --- id
            // Prefer token if it is a UUID string (used by the new provision flow);
            // otherwise fall back to the document id.
            let token = data["token"] as? String
            self.id = token?.isEmpty == false ? token! : id

            // --- createdAt / createdByUid (required)
            guard
                let createdAt = data["createdAt"] as? Timestamp,
                let createdByUid = data["createdByUid"] as? String
            else { return nil }
            self.createdAt = createdAt
            self.createdByUid = createdByUid

            // --- status
            let statusRaw = (data["statusRaw"] as? String) ?? (data["status"] as? String) ?? "submitted"
            self.statusRaw = statusRaw

            // --- payout method
            let payoutMethodRaw = (data["payoutMethodRaw"] as? String) ?? (data["payoutMethod"] as? String) ?? "paypal"
            self.payoutMethodRaw = payoutMethodRaw

            // --- amount
            if let amount = data["amount"] as? Double {
                self.amount = amount
            } else if let amount = data["amount"] as? Int {
                self.amount = Double(amount)
            } else if let amount = data["amount"] as? NSNumber {
                self.amount = amount.doubleValue
            } else {
                self.amount = 0
            }

            // --- recipient name (legacy: recipientName; new: recommenderName or customerName)
            let recipientName =
                (data["recipientName"] as? String)
                ?? (data["recommenderName"] as? String)
                ?? (data["customerName"] as? String)
                ?? "Unbekannt"
            self.recipientName = recipientName

            // --- recipient address
            if let legacyAddress = data["recipientAddress"] as? String, !legacyAddress.isEmpty {
                self.recipientAddress = legacyAddress
            } else {
                let street = (data["recommenderStreet"] as? String) ?? ""
                let zip = (data["recommenderZip"] as? String) ?? ""
                let city = (data["recommenderCity"] as? String) ?? ""
                let line1 = [street].filter { !$0.isEmpty }.joined(separator: " ")
                let line2 = [zip, city].filter { !$0.isEmpty }.joined(separator: " ")
                let address = [line1, line2].filter { !$0.isEmpty }.joined(separator: "\n")
                self.recipientAddress = address.isEmpty ? "-" : address
            }

            // --- payout target
            // Legacy: payoutTarget; New: payoutIban / payoutPaypal depending on payoutMethod.
            if let legacyTarget = data["payoutTarget"] as? String, !legacyTarget.isEmpty {
                self.payoutTarget = legacyTarget
            } else {
                if payoutMethodRaw.lowercased() == "iban" {
                    self.payoutTarget = (data["payoutIban"] as? String) ?? ""
                } else {
                    self.payoutTarget = (data["payoutPaypal"] as? String) ?? ""
                }
            }

            // --- paidAt / paidByUid (optional)
            self.paidAt = data["paidAt"] as? Timestamp
            self.paidByUid = data["paidByUid"] as? String
        }

        init(from entry: CommissionEntry, actorUid: String) {
            self.id = entry.id.uuidString
            self.recipientName = entry.recipientName
            self.recipientAddress = entry.recipientAddress
            self.amount = (entry.amountEUR as NSDecimalNumber).doubleValue
            self.payoutMethodRaw = entry.payoutMethod.rawValue
            self.payoutTarget = entry.payoutTarget
            self.statusRaw = entry.status.rawValue
            self.createdAt = Timestamp(date: entry.createdAt)
            self.createdByUid = entry.createdByUserId.isEmpty ? actorUid : entry.createdByUserId
            self.paidAt = entry.paidAt.map { Timestamp(date: $0) }
            self.paidByUid = entry.paidByUserId
        }

        func toDictionary() -> [String: Any] {
            var d: [String: Any] = [
                "recipientName": recipientName,
                "recipientAddress": recipientAddress,
                "amount": amount,
                "payoutMethodRaw": payoutMethodRaw,
                "payoutTarget": payoutTarget,
                "statusRaw": statusRaw,
                "createdAt": createdAt,
                "createdByUid": createdByUid
            ]
            if let paidAt { d["paidAt"] = paidAt }
            if let paidByUid { d["paidByUid"] = paidByUid }
            return d
        }
    }

    // MARK: - Firestore Commissions Listener

    private func startCommissionsListenerIfNeeded() {
        guard commissionsListener == nil else { return }
        guard let me = currentUser else { return }

        var query: Query = db.collection("commissions")

        // Admin: alles; Nicht-Admin: nur eigene erstellte Provisionen
        if me.role != .admin {
            query = query.whereField("createdByUid", isEqualTo: me.id)
        }

        query = query.order(by: "createdAt", descending: true)

        commissionsListener = query.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage =
                    "Provisionen konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }

                let mapped: [CommissionEntry] = docs.compactMap { doc in
                    guard let dto = CommissionDTO(id: doc.documentID, data: doc.data()) else {
                        return nil
                    }
                    let uuid = UUID(uuidString: dto.id) ?? UUID(uuidString: doc.documentID)
                    guard let uuid else { return nil }

                    let status = CommissionStatus(rawValue: dto.statusRaw) ?? .submitted
                    let method = PayoutMethod(rawValue: dto.payoutMethodRaw) ?? .paypal

                    return CommissionEntry(
                        id: uuid,
                        recipientName: dto.recipientName,
                        recipientAddress: dto.recipientAddress,
                        amountEUR: Decimal(dto.amount),
                        payoutMethod: method,
                        payoutTarget: dto.payoutTarget,
                        status: status,
                        createdAt: dto.createdAt.dateValue(),
                        createdByUserId: dto.createdByUid,
                        paidAt: dto.paidAt?.dateValue(),
                        paidByUserId: dto.paidByUid
                    )
                }

                DispatchQueue.main.async { [weak self] in
                    self?.commissions = mapped
                }
            }
        }
    }

    private func upsertCommissionToFirestore(_ entry: CommissionEntry) {
        guard let actorUid = Auth.auth().currentUser?.uid else { return }
        let dto = CommissionDTO(from: entry, actorUid: actorUid)

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("commissions").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
            } catch {
                let msg = "Provision konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func deleteCommissionFromFirestore(_ entry: CommissionEntry) {
        let docId = entry.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("commissions").document(docId).delete()
            } catch {
                let msg = "Provision konnte nicht gelöscht werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
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
        upsertCommissionToFirestore(entry)
        
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
        upsertCommissionToFirestore(commissions[idx])
    }
    
    func deleteCommission(_ entry: CommissionEntry) {
        guard let admin = currentUser, admin.role == .admin else { return }
        deleteCommissionFromFirestore(entry)
        commissions.removeAll { $0.id == entry.id }
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
            self.assignedUserId = assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            self.creatorUserId = creatorUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            self.createdAt = createdAt
            self.dueDate = data["dueDate"] as? Timestamp
            self.updatedAt = data["updatedAt"] as? Timestamp
        }

        init(from task: Task) {
            self.id = task.id.uuidString
            self.title = task.title
            self.details = task.details
            self.statusRaw = task.status.rawValue
            self.assignedUserId = task.assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            self.creatorUserId = task.creatorUserId.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func mapTasksFromDocs(_ docs: [QueryDocumentSnapshot]) -> [Task] {
        docs.compactMap { doc in
            guard let dto = TaskDTO(id: doc.documentID, data: doc.data()) else { return nil }
            guard let uuid = UUID(uuidString: dto.id) else { return nil }

            let status = TaskStatus(rawValue: dto.statusRaw) ?? .open

            return Task(
                id: uuid,
                title: dto.title,
                details: dto.details,
                dueDate: dto.dueDate?.dateValue(),
                status: status,
                assignedUserId: normalizedIdentity(dto.assignedUserId),
                creatorUserId: normalizedIdentity(dto.creatorUserId),
                createdAt: dto.createdAt.dateValue(),
                updatedAt: dto.updatedAt?.dateValue()
            )
        }
    }

    private func mergeTaskSnapshotsAndPublish() {
        var byId: [UUID: Task] = [:]
        for task in tasksAssignedSnapshotCache { byId[task.id] = task }
        for task in tasksCreatedByMeSnapshotCache { byId[task.id] = task }

        // Snapshot has this task now -> no longer pending.
        for id in byId.keys {
            pendingTaskWritesById.removeValue(forKey: id)
            pendingTaskDeletionIds.remove(id)
        }

        // Keep local deletes hidden until server/listener catches up.
        for id in pendingTaskDeletionIds {
            byId.removeValue(forKey: id)
        }

        // Keep local creates/updates visible immediately.
        for (id, task) in pendingTaskWritesById where !pendingTaskDeletionIds.contains(id) {
            byId[id] = task
        }

        let merged = Array(byId.values).sorted { $0.createdAt > $1.createdAt }
        DispatchQueue.main.async { [weak self] in
            self?.tasks = merged
        }
    }

    private func startTasksListenerIfNeeded() {
        guard tasksListener == nil else { return }
        guard tasksCreatedByMeListener == nil else { return }
        guard let me = currentUser else { return }
        guard let meUid = canonicalCurrentUid(fallback: me), !meUid.isEmpty else { return }

        // Admin: sieht alles in einem Listener.
        if me.role == .admin {
            let query = db.collection("tasks").order(by: "createdAt", descending: true)
            tasksListener = query.addSnapshotListener(includeMetadataChanges: false) {
                [weak self] snapshot, error in
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
                    self.tasksAssignedSnapshotCache = self.mapTasksFromDocs(docs)
                    self.tasksCreatedByMeSnapshotCache = []
                    self.mergeTaskSnapshotsAndPublish()
                }
            }
            return
        }

        // Non-admin: merge two sources
        let assignedQuery = db.collection("tasks")
            .whereField("assignedUserId", isEqualTo: meUid)

        tasksListener = assignedQuery.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Tasks (für mich) konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.tasksAssignedSnapshotCache = self.mapTasksFromDocs(docs)
                self.mergeTaskSnapshotsAndPublish()
            }
        }

        let createdByMeQuery = db.collection("tasks")
            .whereField("creatorUserId", isEqualTo: meUid)

        tasksCreatedByMeListener = createdByMeQuery.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Tasks (von mir) konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.tasksCreatedByMeSnapshotCache = self.mapTasksFromDocs(docs)
                self.mergeTaskSnapshotsAndPublish()
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
            } catch {
                let msg = "Task konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.pendingTaskWritesById.removeValue(forKey: task.id)
                    self.mergeTaskSnapshotsAndPublish()
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
                // Kein Nutzer-Fehlerbanner hier: In manchen Fällen ist der Delete
                // serverseitig bereits durch, obwohl lokal ein Fehler zurückkommt.
                await MainActor.run {
                    self.uiErrorMessage = nil
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
            if isBootstrapAdmin {
                let fallback = UserProfile(
                    name: fbUser.displayName ?? email,
                    roleRaw: UserRole.admin.rawValue,
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
                    self.uiErrorMessage = nil

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        guard let self else { return }
                        guard self.currentUser?.id == uid, self.auth.user != nil else { return }
                        self.startRealtimeListenersIfNeeded()
                    }
                }
                return
            }

            // Security: do not auto-create regular employee profiles without an invite.
            do {
                try Auth.auth().signOut()
            } catch {
                // Keep going; we still block access in local state below.
            }

            await MainActor.run {
                self.stopUsersListeners()
                self.currentUser = nil
                self.isProfileReady = false
                self.didStartRealtimeListeners = false
                self.uiErrorMessage = "Kein freigeschaltetes Profil gefunden. Bitte den Admin kontaktieren."
            }
            return
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
                    a.annualLeaveDays != b.annualLeaveDays ||
                    a.birthday != b.birthday {
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
        approvedLeaveRequestsListener?.remove(); approvedLeaveRequestsListener = nil
        tasksListener?.remove(); tasksListener = nil
        tasksCreatedByMeListener?.remove(); tasksCreatedByMeListener = nil
        commissionsListener?.remove(); commissionsListener = nil
        usersSnapshotCache = []
        invitesSnapshotCache = []
        leaveRequests = []
        leaveRequestsOwnSnapshotCache = []
        leaveRequestsApprovedSnapshotCache = []
        tasksAssignedSnapshotCache = []
        tasksCreatedByMeSnapshotCache = []
        pendingTaskWritesById = [:]
        pendingTaskDeletionIds = []
        tasks = []
        commissions = []
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
        startCommissionsListenerIfNeeded()
    }
    
    private func startUsersListenersIfNeeded() {
        // Avoid duplicate listeners
        if usersListener != nil { return }

        // Non-admin users must also see all employees for the Calendar legend.
        // Rules already allow `read` for signed-in users, so we can subscribe to the full collection.
        if let me = currentUser, me.role != .admin {
            usersListener = db.collection("users").addSnapshotListener(includeMetadataChanges: false) {
                [weak self] (snapshot: QuerySnapshot?, error: Error?) in
                guard let self else { return }
                if let error = error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "Users konnten nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }

                let docs = snapshot?.documents ?? []
                self.firestoreListenerQueue.async { [weak self] in
                    guard let self else { return }
                    self.usersSnapshotCache = docs.compactMap { doc in
                        guard let profile = UserProfile(from: doc.data()) else { return nil }
                        return profile.toUser(id: doc.documentID)
                    }
                    // Non-admins do not see invites
                    self.invitesSnapshotCache = []
                    self.mergeUserSnapshotsAndPublish()
                }
            }
            return
        }

        // Admin: listen to all profiles in users/<uid>
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

    private func mergeLeaveRequestSnapshotsAndPublish() {
        // Merge by request UUID string to avoid duplicates
        var byId: [UUID: LeaveRequest] = [:]

        for r in leaveRequestsApprovedSnapshotCache {
            byId[r.id] = r
        }
        for r in leaveRequestsOwnSnapshotCache {
            byId[r.id] = r
        }

        let merged = Array(byId.values)
            .sorted { $0.startDate < $1.startDate }

        DispatchQueue.main.async { [weak self] in
            self?.leaveRequests = merged
        }
    }

    private func mapLeaveRequestsFromDocs(_ docs: [QueryDocumentSnapshot]) -> [LeaveRequest] {
        // Build lookup maps once per snapshot for performance.
        let usersById: [String: User] = Dictionary(
            uniqueKeysWithValues: self.users.map { ($0.id, $0) }
        )
        let usersByEmail: [String: User] = Dictionary(
            uniqueKeysWithValues: self.users.map { ($0.email.lowercased(), $0) }
        )

        let mapped: [LeaveRequest] = docs.compactMap { doc in
            guard let dto = LeaveRequestDTO(id: doc.documentID, data: doc.data()) else {
                return nil
            }
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
                // Minimal fallback
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
            let status = LeaveStatus(
                rawValue: dto.statusRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            ) ?? .pending

            return LeaveRequest(
                id: id,
                user: resolvedUser,
                startDate: dto.startDate.dateValue(),
                endDate: dto.endDate.dateValue(),
                type: type,
                reason: dto.reason,
                status: status,
                createdAt: dto.createdAt.dateValue(),
                createdByUserId: dto.createdByUid
                    ?? "invite:\(dto.createdByEmail.lowercased())",
                updatedAt: dto.updatedAt?.dateValue(),
                updatedByUserId: dto.updatedByUid
                    ?? dto.updatedByEmail.map { "invite:\($0.lowercased())" }
            )
        }

        return mapped
    }

    func startLeaveRequestsListenerIfNeeded() {
        guard leaveRequestsListener == nil else { return }
        guard let me = currentUser else { return }
        guard let authUid = Auth.auth().currentUser?.uid else { return }

        // Admin: single listener for everything
        if me.role == .admin {
            let query: Query = db.collection("leaveRequests")
            leaveRequestsListener = query.addSnapshotListener(includeMetadataChanges: true) {
                [weak self] snapshot, error in
                guard let self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "leaveRequests: \(error.localizedDescription)"
                    }
                    return
                }
                guard let snapshot else { return }

                let docs = snapshot.documents
                self.firestoreListenerQueue.async { [weak self] in
                    guard let self else { return }
                    let mapped = self.mapLeaveRequestsFromDocs(docs)
                    DispatchQueue.main.async { [weak self] in
                        self?.leaveRequests = mapped
                    }
                }
            }
            return
        }

        // Non-admin:
        // 1) Own requests (all statuses) so MyRequests stays correct
        // 2) All approved requests (for calendar visibility across users)

        let ownQuery: Query = db.collection("leaveRequests")
            .whereField("userId", isEqualTo: authUid)

        leaveRequestsListener = ownQuery.addSnapshotListener(includeMetadataChanges: true) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "leaveRequests (own): \(error.localizedDescription)"
                }
                return
            }
            guard let snapshot else { return }

            let docs = snapshot.documents
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.leaveRequestsOwnSnapshotCache = self.mapLeaveRequestsFromDocs(docs)
                self.mergeLeaveRequestSnapshotsAndPublish()
            }
        }

        let approvedQuery: Query = db.collection("leaveRequests")
            .whereField("statusRaw", isEqualTo: LeaveStatus.approved.rawValue)

        approvedLeaveRequestsListener = approvedQuery.addSnapshotListener(
            includeMetadataChanges: true
        ) { [weak self] snapshot, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "leaveRequests (approved): \(error.localizedDescription)"
                }
                return
            }
            guard let snapshot else { return }

            let docs = snapshot.documents
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.leaveRequestsApprovedSnapshotCache = self.mapLeaveRequestsFromDocs(docs)
                self.mergeLeaveRequestSnapshotsAndPublish()
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
                    let msg = "Abwesenheit konnte nicht gespeichert werden: \(error.localizedDescription)"
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
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
