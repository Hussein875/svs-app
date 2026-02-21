import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

extension AppState {
    // MARK: - Firestore User Profile
    
    func loadOrCreateProfile(for fbUser: FirebaseAuth.User) async {
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
            if inviteSnap.exists {
                // Preferred path: hydrate server-side via callable (bypasses client rules edge cases).
                do {
                    let functions = Functions.functions(region: "us-central1")
                    _ = try await functions
                        .httpsCallable("bootstrapMyProfileFromInvite")
                        .call([:])

                    let hydrated = try await docRef.getDocument()
                    if hydrated.exists,
                       let hydratedData = hydrated.data(),
                       let profile = UserProfile(from: hydratedData) {
                        let mapped = profile.toUser(id: uid)
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
                } catch {
                    // Fallback to legacy client-side invite merge below.
                }

                if let data = inviteSnap.data(), let invited = UserProfile(from: data) {
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
                    a.pushNotificationsEnabled != b.pushNotificationsEnabled ||
                    a.receiveAdminPushes != b.receiveAdminPushes ||
                    a.meetingSchedulePushEnabled != b.meetingSchedulePushEnabled {
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
    
    func stopUsersListeners() {
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
    

}
