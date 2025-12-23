//
//  AppState.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
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
            self.users = [
                User(id: UUID(), name: "Hussein", role: .admin,   pin: "1111", colorName: "blue",   annualLeaveDays: 30),
                User(id: UUID(), name: "Ahmet",   role: .employee, pin: "2222", colorName: "green",  annualLeaveDays: 30),
                User(id: UUID(), name: "Hadi",    role: .employee, pin: "3333", colorName: "orange", annualLeaveDays: 30),
                User(id: UUID(), name: "Osama",   role: .employee, pin: "4444", colorName: "purple", annualLeaveDays: 30)
            ]
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

        // Auto-Restore: wenn Session vorhanden, direkt einloggen
        if let sid = self.sessionUserId,
           let u = self.users.first(where: { $0.id == sid }) {
            self.currentUser = u
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

    func addUser(name: String, role: UserRole, pin: String, colorName: String, annualLeaveDays: Int) {
        let newUser = User(id: UUID(), name: name, role: role, pin: pin, colorName: colorName, annualLeaveDays: annualLeaveDays)
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
        } else {
            successText = (initialStatus == .approved) ? "Urlaub erfolgreich eingetragen." : "Urlaubsantrag erfolgreich erstellt."
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
}
