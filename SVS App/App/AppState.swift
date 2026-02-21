//
//  AppState.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import Combine
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

class AppState: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    let db = Firestore.firestore()
    
    // Firestore listeners
    var usersListener: ListenerRegistration?
    var invitesListener: ListenerRegistration?
    var leaveRequestsListener: ListenerRegistration?
    var approvedLeaveRequestsListener: ListenerRegistration?
    var tasksListener: ListenerRegistration?
    var tasksCreatedByMeListener: ListenerRegistration?
    var commissionsListener: ListenerRegistration?
    var meetingTopicsListener: ListenerRegistration?
    var meetingMetaListener: ListenerRegistration?
    var meetingArchivesListener: ListenerRegistration?
    
    // Run snapshot processing off the main thread
    let firestoreListenerQueue = DispatchQueue(label: "svs.firestore.listeners", qos: .userInitiated)
    
    // Snapshot caches (so we can merge sources)
    var usersSnapshotCache: [User] = []
    var invitesSnapshotCache: [User] = []
    var leaveRequestsOwnSnapshotCache: [LeaveRequest] = []
    var leaveRequestsApprovedSnapshotCache: [LeaveRequest] = []
    var tasksAssignedSnapshotCache: [Task] = []
    var tasksCreatedByMeSnapshotCache: [Task] = []
    var pendingTaskWritesById: [UUID: Task] = [:]
    var pendingTaskDeletionIds: Set<UUID> = []
    var meetingTopicsSnapshotCache: [MeetingTopic] = []
    var meetingArchivesSnapshotCache: [MeetingArchive] = []
    var pendingMeetingTopicWritesById: [UUID: MeetingTopic] = [:]
    var pendingMeetingTopicDeletionIds: Set<UUID> = []
    
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
    var didStartRealtimeListeners: Bool = false
    
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

    @MainActor
    @discardableResult
    func setMyReceiveAdminPushesEnabled(_ enabled: Bool) async -> Bool {
        guard var me = currentUser else { return false }
        guard me.role == .admin else { return false }

        let previous = me.receiveAdminPushes
        if previous == enabled { return true }

        me.receiveAdminPushes = enabled
        currentUser = me
        if let idx = users.firstIndex(where: { $0.id == me.id }) {
            users[idx] = me
        }

        do {
            let functions = Functions.functions(region: "us-central1")
            _ = try await functions.httpsCallable("setMyReceiveAdminPushes").call([
                "enabled": enabled
            ])
            uiErrorMessage = nil
            return true
        } catch {
            // Fallback path:
            // If the callable function is not deployed yet, write directly to
            // users/<uid> so the toggle remains usable.
            do {
                try await db.collection("users").document(me.id).setData([
                    "receiveAdminPushes": enabled,
                    "receiveAdminPushesUpdatedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
                uiErrorMessage = nil
                return true
            } catch {
                me.receiveAdminPushes = previous
                currentUser = me
                if let idx = users.firstIndex(where: { $0.id == me.id }) {
                    users[idx] = me
                }
                uiErrorMessage = "Provisions-Push-Einstellung konnte nicht gespeichert werden: \(error.localizedDescription)"
                return false
            }
        }
    }

    @MainActor
    @discardableResult
    func setMyMeetingSchedulePushEnabled(_ enabled: Bool) async -> Bool {
        guard var me = currentUser else { return false }

        let previous = me.meetingSchedulePushEnabled
        if previous == enabled { return true }

        me.meetingSchedulePushEnabled = enabled
        currentUser = me
        if let idx = users.firstIndex(where: { $0.id == me.id }) {
            users[idx] = me
        }

        do {
            let functions = Functions.functions(region: "us-central1")
            _ = try await functions.httpsCallable("setMyMeetingSchedulePushEnabled").call([
                "enabled": enabled
            ])
            uiErrorMessage = nil
            return true
        } catch {
            me.meetingSchedulePushEnabled = previous
            currentUser = me
            if let idx = users.firstIndex(where: { $0.id == me.id }) {
                users[idx] = me
            }
            uiErrorMessage = "Meeting-Push-Einstellung konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }

    /// Resets the unread push counter for the current user (server-side).
    /// Call this when opening the in-app notifications screen.
    @MainActor
    @discardableResult
    func clearMyUnreadBadge() async -> Bool {
        guard Auth.auth().currentUser != nil else { return false }

        do {
            let functions = Functions.functions(region: "us-central1")
            _ = try await functions.httpsCallable("clearMyUnreadBadge").call([:])
            return true
        } catch {
            return false
        }
    }

    /// Called whenever the app becomes active.
    /// Ensures the app icon badge is cleared locally and server-side.
    @MainActor
    func resetUnreadBadgeOnAppOpen() {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }

            // Auth/Profile restore can lag after cold start.
            // Important: wait for profile readiness, otherwise the callable can
            // create a stub users/<uid> doc before invite hydration completes.
            for _ in 0..<20 {
                let isSignedIn = (Auth.auth().currentUser != nil)
                let profileReady = await MainActor.run {
                    self.isProfileReady && self.currentUser != nil
                }

                if isSignedIn && profileReady {
                    _ = await self.clearMyUnreadBadge()
                    return
                }

                if !isSignedIn {
                    return
                }

                try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
    


}
