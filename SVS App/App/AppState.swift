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
    var pushEnabled: Bool

    init(name: String,
         roleRaw: String,
         colorName: String,
         annualLeaveDays: Int,
         email: String,
         birthday: Date? = nil,
         pushEnabled: Bool = true) {
        self.name = name
        self.roleRaw = roleRaw
        self.colorName = colorName
        self.annualLeaveDays = annualLeaveDays
        self.email = email
        self.birthday = birthday
        self.pushEnabled = pushEnabled
    }

    init(from user: User) {
        self.name = user.name
        self.roleRaw = user.role.rawValue
        self.colorName = user.colorName
        self.annualLeaveDays = user.annualLeaveDays
        self.email = user.email
        self.birthday = user.birthday
        self.pushEnabled = user.pushNotificationsEnabled
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
        self.pushEnabled = (data["pushEnabled"] as? Bool) ?? true
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
            "email": email,
            "pushEnabled": pushEnabled
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
            birthday: birthday,
            pushNotificationsEnabled: pushEnabled
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
    private var meetingTopicsListener: ListenerRegistration?
    private var meetingMetaListener: ListenerRegistration?
    private var meetingArchivesListener: ListenerRegistration?
    
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
    private var meetingTopicsSnapshotCache: [MeetingTopic] = []
    private var meetingArchivesSnapshotCache: [MeetingArchive] = []
    private var pendingMeetingTopicWritesById: [UUID: MeetingTopic] = [:]
    private var pendingMeetingTopicDeletionIds: Set<UUID> = []
    
    @Published var auth = AuthManager()
    
    @Published var users: [User] = []
    
    @Published var currentUser: User?
    @Published var leaveRequests: [LeaveRequest]
    @Published var tasks: [Task] = []
    @Published var meetingTopics: [MeetingTopic] = []
    @Published var meetingArchives: [MeetingArchive] = []
    @Published var nextMeetingAt: Date? = nil
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
        self.meetingTopics = []
        self.meetingArchives = []
        
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

    @MainActor
    @discardableResult
    func setMyPushNotificationsEnabled(_ enabled: Bool) async -> Bool {
        guard var me = currentUser else { return false }

        let previous = me.pushNotificationsEnabled
        if previous == enabled { return true }

        me.pushNotificationsEnabled = enabled
        currentUser = me
        if let idx = users.firstIndex(where: { $0.id == me.id }) {
            users[idx] = me
        }

        do {
            let functions = Functions.functions(region: "us-central1")
            _ = try await functions.httpsCallable("setMyPushEnabled").call([
                "enabled": enabled
            ])
            uiErrorMessage = nil
            return true
        } catch {
            me.pushNotificationsEnabled = previous
            currentUser = me
            if let idx = users.firstIndex(where: { $0.id == me.id }) {
                users[idx] = me
            }
            uiErrorMessage = "Push-Einstellung konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
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
            updatedAt: nil,
            updatedByUserId: nil
        )

        // Optimistic UI
        pendingTaskDeletionIds.remove(newTask.id)
        pendingTaskWritesById[newTask.id] = newTask
        mergeTaskSnapshotsAndPublish()
        createTaskInFirestore(newTask)
    }

    func updateTask(_ task: Task) {
        let permissionSource = tasks.first(where: { $0.id == task.id }) ?? task
        guard canEditTask(permissionSource, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht bearbeiten.")
            return
        }

        var patched = task
        patched.updatedAt = Date()
        patched.updatedByUserId = canonicalCurrentUid(fallback: currentUser) ?? currentUser?.id

        pendingTaskDeletionIds.remove(patched.id)
        pendingTaskWritesById[patched.id] = patched
        mergeTaskSnapshotsAndPublish()

        updateTaskInFirestore(patched)
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

    func canEditMeetingTopic(_ : MeetingTopic, by user: User?) -> Bool {
        user != nil
    }

    func canDeleteMeetingTopic(_ topic: MeetingTopic, by user: User?) -> Bool {
        guard let user else { return false }
        if user.role == .admin { return true }
        return currentIdentitySet(for: user).contains(normalizedIdentity(topic.createdByUserId))
    }

    func createMeetingTopic(title: String, details: String) {
        guard let creator = currentUser else { return }
        let creatorId = canonicalCurrentUid(fallback: creator) ?? creator.id
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            showToast(.error, "Bitte einen Titel für den Meeting-Punkt eingeben.")
            return
        }

        let topic = MeetingTopic(
            id: UUID(),
            title: cleanTitle,
            details: cleanDetails,
            status: .open,
            createdAt: Date(),
            createdByUserId: creatorId,
            updatedAt: nil,
            updatedByUserId: nil
        )

        pendingMeetingTopicDeletionIds.remove(topic.id)
        pendingMeetingTopicWritesById[topic.id] = topic
        mergeMeetingTopicSnapshotsAndPublish()
        showToast(.success, "Meeting-Punkt hinzugefügt.")
        upsertMeetingTopicToFirestore(topic)
    }

    func toggleMeetingTopicStatus(for topic: MeetingTopic) {
        guard canEditMeetingTopic(topic, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Meeting-Punkt nicht ändern.")
            return
        }

        var patched = topic
        patched.status = (topic.status == .open) ? .done : .open
        patched.updatedAt = Date()
        patched.updatedByUserId = canonicalCurrentUid(fallback: currentUser) ?? currentUser?.id

        pendingMeetingTopicDeletionIds.remove(patched.id)
        pendingMeetingTopicWritesById[patched.id] = patched
        mergeMeetingTopicSnapshotsAndPublish()
        upsertMeetingTopicToFirestore(patched)
    }

    func deleteMeetingTopic(_ topic: MeetingTopic) {
        guard canDeleteMeetingTopic(topic, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Meeting-Punkt nicht löschen.")
            return
        }

        pendingMeetingTopicWritesById.removeValue(forKey: topic.id)
        pendingMeetingTopicDeletionIds.insert(topic.id)
        mergeMeetingTopicSnapshotsAndPublish()
        deleteMeetingTopicFromFirestore(topic)
    }

    func canEditNextMeeting(by user: User?) -> Bool {
        user?.role == .admin
    }

    func canArchiveMeeting(by user: User?) -> Bool {
        user?.role == .admin
    }

    func canDeleteMeetingArchive(by user: User?) -> Bool {
        user?.role == .admin
    }

    @MainActor
    func archiveCurrentMeeting() async {
        guard canArchiveMeeting(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen Meetings archivieren.")
            return
        }

        let topicsToArchive = meetingTopics
            .sorted {
                let lhs = $0.updatedAt ?? $0.createdAt
                let rhs = $1.updatedAt ?? $1.createdAt
                return lhs < rhs
            }

        guard !topicsToArchive.isEmpty else {
            showToast(.error, "Keine Meeting-Punkte zum Archivieren vorhanden.")
            return
        }

        let meetingDate = nextMeetingAt ?? Date()
        let actorUid = canonicalCurrentUid(fallback: currentUser)
            ?? currentUser?.id
            ?? ""
        let archiveId = UUID().uuidString
        let archiveRef = db.collection("meetingArchives").document(archiveId)
        let meetingMetaRef = db.collection("meetingMeta").document("schedule")

        let topicsPayload: [[String: Any]] = topicsToArchive.map { topic in
            var d: [String: Any] = [
                "id": topic.id.uuidString,
                "title": topic.title,
                "details": topic.details,
                "statusRaw": topic.status.rawValue,
                "createdAt": Timestamp(date: topic.createdAt),
                "createdByUserId": topic.createdByUserId
            ]
            if let updatedAt = topic.updatedAt {
                d["updatedAt"] = Timestamp(date: updatedAt)
            }
            if let updatedByUserId = topic.updatedByUserId, !updatedByUserId.isEmpty {
                d["updatedByUserId"] = updatedByUserId
            }
            return d
        }

        let protocolText = buildMeetingProtocol(
            topics: topicsToArchive,
            meetingDate: meetingDate
        )

        let archiveData: [String: Any] = [
            "meetingDate": Timestamp(date: meetingDate),
            "archivedAt": FieldValue.serverTimestamp(),
            "archivedByUserId": actorUid,
            "topicCount": topicsToArchive.count,
            "protocolText": protocolText,
            "topics": topicsPayload
        ]

        do {
            let batch = db.batch()
            batch.setData(archiveData, forDocument: archiveRef, merge: false)
            batch.setData([
                "nextMeetingAt": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp(),
                "updatedByUserId": actorUid
            ], forDocument: meetingMetaRef, merge: true)

            for topic in topicsToArchive {
                let topicRef = db.collection("meetingTopics")
                    .document(topic.id.uuidString)
                batch.deleteDocument(topicRef)
            }

            try await batch.commit()

            // Clear local active points immediately; listener will reconcile shortly.
            meetingTopicsSnapshotCache = []
            pendingMeetingTopicWritesById = [:]
            pendingMeetingTopicDeletionIds = []
            meetingTopics = []
            nextMeetingAt = nil

            uiErrorMessage = nil
            showToast(
                .success,
                "Meeting archiviert. \(topicsToArchive.count) Punkt(e) verschoben."
            )
        } catch {
            let msg = meetingArchiveErrorMessage(
                prefix: "Meeting konnte nicht archiviert werden",
                error: error
            )
            uiErrorMessage = msg
            showToast(.error, msg)
        }
    }

    func clearNextMeetingDate() {
        guard canEditNextMeeting(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen den Meeting-Termin löschen.")
            return
        }

        let actor = canonicalCurrentUid(fallback: currentUser)
        var payload: [String: Any] = [
            "nextMeetingAt": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let actor {
            payload["updatedByUserId"] = actor
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingMeta").document("schedule")
                    .setData(payload, merge: true)
                await MainActor.run {
                    self.nextMeetingAt = nil
                    self.uiErrorMessage = nil
                    self.showToast(.success, "Meeting-Termin gelöscht.")
                }
            } catch {
                let msg = "Meeting-Termin konnte nicht gelöscht werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    func deleteMeetingArchive(_ archive: MeetingArchive) {
        guard canDeleteMeetingArchive(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen archivierte Meetings löschen.")
            return
        }

        let docId = archive.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let functions = Functions.functions(region: "us-central1")
                _ = try await functions.httpsCallable("adminDeleteMeetingArchive").call([
                    "archiveId": docId
                ])
                await MainActor.run {
                    self.meetingArchivesSnapshotCache.removeAll { $0.id == archive.id }
                    self.meetingArchives.removeAll { $0.id == archive.id }
                    self.uiErrorMessage = nil
                    self.showToast(.success, "Archiviertes Meeting gelöscht.")
                }
            } catch {
                let msg = self.meetingArchiveErrorMessage(
                    prefix: "Archiviertes Meeting konnte nicht gelöscht werden",
                    error: error
                )
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    func saveNextMeeting(date: Date) {
        guard canEditNextMeeting(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen den Meeting-Termin bearbeiten.")
            return
        }

        let actor = canonicalCurrentUid(fallback: currentUser)
        var payload: [String: Any] = [
            "nextMeetingAt": Timestamp(date: date),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let actor {
            payload["updatedByUserId"] = actor
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingMeta").document("schedule")
                    .setData(payload, merge: true)
                await MainActor.run {
                    self.nextMeetingAt = date
                    self.uiErrorMessage = nil
                    self.showToast(.success, "Nächstes Meeting aktualisiert.")
                }
            } catch {
                let msg = "Meeting-Termin konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    @MainActor
    func refreshMeetingTopicsFromServer() async {
        do {
            let topicsSnap = try await db.collection("meetingTopics")
                .order(by: "createdAt", descending: true)
                .getDocuments(source: .server)

            meetingTopicsSnapshotCache = mapMeetingTopicsFromDocs(topicsSnap.documents)
            mergeMeetingTopicSnapshotsAndPublish()
            uiErrorMessage = nil
        } catch {
            let msg = "Meeting-Punkte konnten nicht aktualisiert werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
            return
        }

        do {
            let archivesSnap = try await db.collection("meetingArchives")
                .order(by: "meetingDate", descending: true)
                .getDocuments(source: .server)

            meetingArchivesSnapshotCache = mapMeetingArchivesFromDocs(archivesSnap.documents)
            meetingArchives = meetingArchivesSnapshotCache
        } catch {
            // Archive read can be intentionally restricted by rules.
            // Do not fail the whole meeting refresh in that case.
            if isPermissionDeniedError(error) {
                meetingArchivesSnapshotCache = []
                meetingArchives = []
                return
            }

            let msg = "Meeting-Archiv konnte nicht aktualisiert werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
        }
    }

    private func buildMeetingProtocol(
        topics: [MeetingTopic],
        meetingDate: Date
    ) -> String {
        let dateText = meetingArchiveDateString(meetingDate)

        var lines: [String] = [
            "Meetingprotokoll vom \(dateText)",
            "",
            "Punkte (\(topics.count)):"
        ]

        for (index, topic) in topics.enumerated() {
            let statusText = topic.status == .done ? "Erledigt" : "Offen"
            var line = "\(index + 1). \(topic.title) [\(statusText)]"
            let cleanDetails = topic.details.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanDetails.isEmpty {
                line += " - \(cleanDetails)"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    private func meetingArchiveDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.string(from: date)
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
        var updatedByUserId: String?

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
            self.updatedByUserId = (data["updatedByUserId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
            self.updatedByUserId = task.updatedByUserId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let updatedByUserId, !updatedByUserId.isEmpty {
                d["updatedByUserId"] = updatedByUserId
            }
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
                updatedAt: dto.updatedAt?.dateValue(),
                updatedByUserId: dto.updatedByUserId
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

    private func createTaskInFirestore(_ task: Task) {
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

    private func updateTaskInFirestore(_ task: Task) {
        let docId = task.id.uuidString

        var payload: [String: Any] = [
            "title": task.title,
            "details": task.details,
            "statusRaw": task.status.rawValue,
            "assignedUserId": task.assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let dueDate = task.dueDate {
            payload["dueDate"] = Timestamp(date: dueDate)
        } else {
            payload["dueDate"] = FieldValue.delete()
        }

        if let updatedBy = task.updatedByUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !updatedBy.isEmpty {
            payload["updatedByUserId"] = updatedBy
        } else {
            payload["updatedByUserId"] = FieldValue.delete()
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("tasks").document(docId).updateData(payload)
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

    // MARK: - Firestore MeetingTopics DTO

    private struct MeetingTopicDTO {
        var id: String
        var title: String
        var details: String
        var statusRaw: String
        var createdAt: Timestamp
        var createdByUserId: String
        var updatedAt: Timestamp?
        var updatedByUserId: String?

        init?(id: String, data: [String: Any]) {
            guard
                let title = data["title"] as? String,
                let statusRaw = data["statusRaw"] as? String,
                let createdAt = data["createdAt"] as? Timestamp,
                let createdByUserId = data["createdByUserId"] as? String
            else { return nil }

            self.id = id
            self.title = title
            self.details = (data["details"] as? String) ?? ""
            self.statusRaw = statusRaw
            self.createdAt = createdAt
            self.createdByUserId = createdByUserId
            self.updatedAt = data["updatedAt"] as? Timestamp
            self.updatedByUserId = data["updatedByUserId"] as? String
        }

        init(from topic: MeetingTopic) {
            self.id = topic.id.uuidString
            self.title = topic.title
            self.details = topic.details
            self.statusRaw = topic.status.rawValue
            self.createdAt = Timestamp(date: topic.createdAt)
            self.createdByUserId = topic.createdByUserId
            self.updatedAt = topic.updatedAt.map { Timestamp(date: $0) }
            self.updatedByUserId = topic.updatedByUserId
        }

        func toDictionary() -> [String: Any] {
            var d: [String: Any] = [
                "title": title,
                "details": details,
                "statusRaw": statusRaw,
                "createdAt": createdAt,
                "createdByUserId": createdByUserId
            ]
            if let updatedAt { d["updatedAt"] = updatedAt }
            if let updatedByUserId { d["updatedByUserId"] = updatedByUserId }
            return d
        }
    }

    private struct MeetingArchiveDTO {
        var id: String
        var meetingDate: Timestamp
        var archivedAt: Timestamp?
        var archivedByUserId: String
        var topicCount: Int
        var protocolText: String
        var topics: [[String: Any]]

        init?(id: String, data: [String: Any]) {
            guard let meetingDate = data["meetingDate"] as? Timestamp else { return nil }

            self.id = id
            self.meetingDate = meetingDate
            self.archivedAt = data["archivedAt"] as? Timestamp
            self.archivedByUserId = (data["archivedByUserId"] as? String) ?? ""
            self.topicCount = (data["topicCount"] as? Int) ?? 0
            self.protocolText = (data["protocolText"] as? String) ?? ""
            self.topics = (data["topics"] as? [[String: Any]]) ?? []
        }
    }

    // MARK: - Firestore MeetingTopics / MeetingArchives Listener

    private func mapMeetingTopicsFromDocs(_ docs: [QueryDocumentSnapshot]) -> [MeetingTopic] {
        docs.compactMap { doc in
            guard let dto = MeetingTopicDTO(id: doc.documentID, data: doc.data()) else { return nil }
            guard let id = UUID(uuidString: dto.id) else { return nil }

            let status = MeetingTopicStatus(rawValue: dto.statusRaw) ?? .open

            return MeetingTopic(
                id: id,
                title: dto.title,
                details: dto.details,
                status: status,
                createdAt: dto.createdAt.dateValue(),
                createdByUserId: dto.createdByUserId,
                updatedAt: dto.updatedAt?.dateValue(),
                updatedByUserId: dto.updatedByUserId
            )
        }
    }

    private func mapMeetingArchivesFromDocs(_ docs: [QueryDocumentSnapshot]) -> [MeetingArchive] {
        docs.compactMap { doc in
            guard let dto = MeetingArchiveDTO(id: doc.documentID, data: doc.data()) else { return nil }
            guard let archiveId = UUID(uuidString: dto.id) else { return nil }

            let mappedTopics: [MeetingTopic] = dto.topics.compactMap { topicData in
                guard
                    let topicIdRaw = topicData["id"] as? String,
                    let topicId = UUID(uuidString: topicIdRaw),
                    let title = topicData["title"] as? String,
                    let statusRaw = topicData["statusRaw"] as? String,
                    let createdByUserId = topicData["createdByUserId"] as? String
                else {
                    return nil
                }

                let createdAt = (topicData["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                let status = MeetingTopicStatus(rawValue: statusRaw) ?? .open
                let details = (topicData["details"] as? String) ?? ""
                let updatedAt = (topicData["updatedAt"] as? Timestamp)?.dateValue()
                let updatedBy = topicData["updatedByUserId"] as? String

                return MeetingTopic(
                    id: topicId,
                    title: title,
                    details: details,
                    status: status,
                    createdAt: createdAt,
                    createdByUserId: createdByUserId,
                    updatedAt: updatedAt,
                    updatedByUserId: updatedBy
                )
            }

            return MeetingArchive(
                id: archiveId,
                meetingDate: dto.meetingDate.dateValue(),
                archivedAt: dto.archivedAt?.dateValue() ?? dto.meetingDate.dateValue(),
                archivedByUserId: dto.archivedByUserId,
                topicCount: dto.topicCount,
                protocolText: dto.protocolText,
                topics: mappedTopics
            )
        }
        .sorted { $0.meetingDate > $1.meetingDate }
    }

    private func mergeMeetingTopicSnapshotsAndPublish() {
        var byId: [UUID: MeetingTopic] = [:]

        for topic in meetingTopicsSnapshotCache {
            byId[topic.id] = topic
        }

        for id in byId.keys {
            pendingMeetingTopicWritesById.removeValue(forKey: id)
            pendingMeetingTopicDeletionIds.remove(id)
        }

        for id in pendingMeetingTopicDeletionIds {
            byId.removeValue(forKey: id)
        }

        for (id, topic) in pendingMeetingTopicWritesById where !pendingMeetingTopicDeletionIds.contains(id) {
            byId[id] = topic
        }

        let merged = Array(byId.values).sorted { $0.createdAt > $1.createdAt }
        DispatchQueue.main.async { [weak self] in
            self?.meetingTopics = merged
        }
    }

    private func startMeetingTopicsListenerIfNeeded() {
        guard meetingTopicsListener == nil else { return }
        guard currentUser != nil else { return }

        let query = db.collection("meetingTopics").order(by: "createdAt", descending: true)
        meetingTopicsListener = query.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Meeting-Punkte konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.meetingTopicsSnapshotCache = self.mapMeetingTopicsFromDocs(docs)
                self.mergeMeetingTopicSnapshotsAndPublish()
            }
        }
    }

    private func startMeetingMetaListenerIfNeeded() {
        guard meetingMetaListener == nil else { return }
        guard currentUser != nil else { return }

        meetingMetaListener = db.collection("meetingMeta").document("schedule")
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "Meeting-Termin konnte nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }

                guard
                    let data = snapshot?.data(),
                    let ts = data["nextMeetingAt"] as? Timestamp
                else {
                    DispatchQueue.main.async { [weak self] in
                        self?.nextMeetingAt = nil
                    }
                    return
                }

                let date = ts.dateValue()
                DispatchQueue.main.async { [weak self] in
                    self?.nextMeetingAt = date
                }
            }
    }

    private func startMeetingArchivesListenerIfNeeded() {
        guard meetingArchivesListener == nil else { return }
        guard currentUser != nil else { return }

        let query = db.collection("meetingArchives").order(by: "meetingDate", descending: true)
        meetingArchivesListener = query.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                if self.isPermissionDeniedError(error) {
                    DispatchQueue.main.async {
                        self.meetingArchivesSnapshotCache = []
                        self.meetingArchives = []
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Meeting-Archiv konnte nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                let mapped = self.mapMeetingArchivesFromDocs(docs)
                DispatchQueue.main.async {
                    self.meetingArchivesSnapshotCache = mapped
                    self.meetingArchives = mapped
                }
            }
        }
    }

    private func meetingTopicErrorMessage(prefix: String, error: Error) -> String {
        if isPermissionDeniedError(error) {
            return "\(prefix): Zugriff verweigert. Bitte Firestore-Regeln für `meetingTopics` prüfen."
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    private func meetingArchiveErrorMessage(prefix: String, error: Error) -> String {
        if isPermissionDeniedError(error) {
            return "\(prefix): Zugriff verweigert. Bitte Firestore-Regeln für `meetingTopics` und `meetingArchives` prüfen."
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    private func isPermissionDeniedError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain &&
            ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    private func upsertMeetingTopicToFirestore(_ topic: MeetingTopic) {
        let dto = MeetingTopicDTO(from: topic)
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingTopics").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
            } catch {
                let msg = self.meetingTopicErrorMessage(
                    prefix: "Meeting-Punkt konnte nicht gespeichert werden",
                    error: error
                )
                await MainActor.run {
                    self.pendingMeetingTopicWritesById.removeValue(forKey: topic.id)
                    self.mergeMeetingTopicSnapshotsAndPublish()
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func deleteMeetingTopicFromFirestore(_ topic: MeetingTopic) {
        let docId = topic.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingTopics").document(docId).delete()
            } catch {
                let msg = self.meetingTopicErrorMessage(
                    prefix: "Meeting-Punkt konnte nicht gelöscht werden",
                    error: error
                )
                await MainActor.run {
                    self.pendingMeetingTopicDeletionIds.remove(topic.id)
                    self.pendingMeetingTopicWritesById[topic.id] = topic
                    self.mergeMeetingTopicSnapshotsAndPublish()
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
                    a.birthday != b.birthday ||
                    a.pushNotificationsEnabled != b.pushNotificationsEnabled {
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
        meetingTopicsListener?.remove(); meetingTopicsListener = nil
        meetingMetaListener?.remove(); meetingMetaListener = nil
        meetingArchivesListener?.remove(); meetingArchivesListener = nil
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
        meetingTopicsSnapshotCache = []
        meetingArchivesSnapshotCache = []
        pendingMeetingTopicWritesById = [:]
        pendingMeetingTopicDeletionIds = []
        meetingTopics = []
        meetingArchives = []
        nextMeetingAt = nil
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
        startMeetingTopicsListenerIfNeeded()
        startMeetingMetaListenerIfNeeded()
        startMeetingArchivesListenerIfNeeded()
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
