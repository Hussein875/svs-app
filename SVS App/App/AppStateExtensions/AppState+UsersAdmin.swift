import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

extension AppState {
    @MainActor
    @discardableResult
    func adminResetScannerSequenceFromSheet() async -> Bool {
        guard currentUser?.role == .admin else {
            showToast(.error, "Nur Admins dürfen die Scanner-Nummer zurücksetzen.")
            return false
        }

        do {
            guard let user = Auth.auth().currentUser else {
                showToast(.error, "Nicht angemeldet.")
                return false
            }

            let endpoint = URL(
                string: "https://us-central1-svs-app-864ed.cloudfunctions.net/adminResetScannerSequenceFromSheetHttp"
            )!
            let idToken = try await user.getIDToken()

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [:])

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? -1
            let rawText = String(data: data, encoding: .utf8) ?? ""

            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let dataDict = jsonObject as? [String: Any] else {
                let prefix = rawText.prefix(500)
                throw NSError(
                    domain: "AdminResetScanner",
                    code: status,
                    userInfo: [NSLocalizedDescriptionKey: "Unerwartete Server-Antwort (HTTP \(status)): \(prefix)"]
                )
            }

            if let ok = dataDict["ok"] as? Bool, !ok {
                let msg = String(dataDict["error"] as? String ?? "Scanner-Nummer konnte nicht zurückgesetzt werden.")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "AdminResetScanner",
                    code: status,
                    userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Scanner-Nummer konnte nicht zurückgesetzt werden." : msg]
                )
            }

            guard let nextNumber = dataDict["nextNumber"] as? Int else {
                showToast(.error, "Scanner-Nummer konnte nicht zurückgesetzt werden.")
                return false
            }

            let year2 = (dataDict["year2"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ignoredReservations =
                (dataDict["ignoredReservations"] as? Bool) ?? false

            if ignoredReservations {
                showToast(
                    .success,
                    "Scanner-Nummer hart auf \(nextNumber)/\(year2) aus dem Google Sheet gesetzt. Firestore-Reservierungen wurden ignoriert."
                )
            } else {
                showToast(
                    .success,
                    "Scanner-Nummer auf \(nextNumber)/\(year2) aus dem Google Sheet gesetzt."
                )
            }
            uiErrorMessage = nil
            return true
        } catch {
            let msg = "Scanner-Nummer konnte nicht aus dem Google Sheet gesetzt werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
            return false
        }
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
    
    @MainActor
    @discardableResult
    func deleteUser(_ user: User) async -> Bool {
        // Cloud delete (Admin only)
        guard currentUser?.role == .admin else {
            uiErrorMessage = "Nur Admins dürfen Benutzer löschen."
            return false
        }

        let cleanEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

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

            self.users.removeAll { $0.id == user.id }
            self.leaveRequests.removeAll { $0.user.id == user.id }
            self.uiErrorMessage = nil
            return true
        } catch {
            self.uiErrorMessage = "Profil konnte nicht gelöscht werden: \(error.localizedDescription)"
            return false
        }
    }


}
