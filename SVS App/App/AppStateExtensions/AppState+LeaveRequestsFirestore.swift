import Foundation
import FirebaseAuth
import FirebaseFirestore

extension AppState {
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
    
    func upsertLeaveRequestToFirestore(_ request: LeaveRequest) {
        guard let actorEmail = currentUser?.email.lowercased() else { return }
        guard let actorUid = Auth.auth().currentUser?.uid else { return }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                var patched = request

                // Keep actor audit fields canonical (real auth uid).
                patched.createdByUserId = actorUid
                if patched.updatedAt != nil {
                    patched.updatedByUserId = actorUid
                }

                // Resolve legacy invite/email user ids to a concrete UID before write.
                let resolvedUserId = try await self.resolveLeaveUserUid(for: patched.user)
                if !resolvedUserId.isEmpty && resolvedUserId != patched.user.id {
                    patched.user = User(
                        id: resolvedUserId,
                        name: patched.user.name,
                        role: patched.user.role,
                        colorName: patched.user.colorName,
                        annualLeaveDays: patched.user.annualLeaveDays,
                        email: patched.user.email,
                        birthday: patched.user.birthday,
                        pushNotificationsEnabled: patched.user.pushNotificationsEnabled
                    )
                }

                let dto = LeaveRequestDTO(from: patched, currentActorEmail: actorEmail)
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

    private func resolveLeaveUserUid(for user: User) async throws -> String {
        let rawId = normalizedIdentity(user.id)
        let lowerRawId = rawId.lowercased()
        let isLegacyId =
            lowerRawId.hasPrefix("invite:") || rawId.contains("@")

        if !rawId.isEmpty && !isLegacyId {
            return rawId
        }

        let email = normalizedIdentity(user.email).lowercased()
        guard !email.isEmpty else { return rawId }

        // Fast path for "me".
        if let authUid = Auth.auth().currentUser?.uid,
           normalizedIdentity(currentUser?.email).lowercased() == email {
            return authUid
        }

        let qs = try await db.collection("users")
            .whereField("email", isEqualTo: email)
            .limit(to: 1)
            .getDocuments()

        if let doc = qs.documents.first {
            return doc.documentID
        }

        return rawId
    }
    
    func deleteLeaveRequestFromFirestore(_ request: LeaveRequest) {
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
