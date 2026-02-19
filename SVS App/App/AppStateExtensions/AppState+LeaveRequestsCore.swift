import Foundation
import FirebaseAuth
import FirebaseFirestore

extension AppState {
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

    func normalizedIdentity(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func canonicalCurrentUid(fallback user: User?) -> String? {
        let authUid = normalizedIdentity(Auth.auth().currentUser?.uid)
        if !authUid.isEmpty { return authUid }

        let userId = normalizedIdentity(user?.id)
        if !userId.isEmpty { return userId }
        return nil
    }

    func currentIdentitySet(for user: User?) -> Set<String> {
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
    

}
