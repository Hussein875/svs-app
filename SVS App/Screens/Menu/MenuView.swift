//
//  MenuView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSignOutConfirm: Bool = false
    @State private var isSigningOut: Bool = false
    @State private var selectedColorName: String = "blue"
    @State private var isSavingColor: Bool = false
    
    private let availableColors = UserColor.allCases
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                
                List {
                    Section(header: Text("Benutzer")) {
                        if let user = appState.currentUser {
                            LabeledContent("Eingeloggt als") {
                                Text(user.name)
                                    .foregroundColor(user.color)
                            }

                            LabeledContent("Rolle") {
                                Text(germanRoleName(user.role))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Nicht eingeloggt")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if appState.currentUser != nil {
                        Section(header: Text("Erscheinungsbild")) {
                            Picker("Akzentfarbe", selection: $selectedColorName) {
                                ForEach(availableColors, id: \.self) { c in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(c.color)
                                            .frame(width: 14, height: 14)
                                            .overlay(
                                                Circle().stroke(
                                                    Color.secondary.opacity(0.25),
                                                    lineWidth: 1
                                                )
                                            )
                                        Text(c.germanName)
                                    }
                                    .tag(c.rawValue)
                                }
                            }
                            .disabled(isSavingColor)

                            HStack(spacing: 8) {
                                Text("Vorschau")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Circle()
                                    .fill(Color.svsAccentColor(from: selectedColorName))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                            }
                        }
                    }
                    
                    Section(header: Text("App-Info")) {
                        LabeledContent("Version") {
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("Entwickelt von") {
                            Text("Hussein Souleiman")
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("Entwickelt für") {
                            Text("SV Souleiman")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section {
                        VStack(spacing: 6) {
                            if appState.currentUser != nil {
                                Button {
                                    showSignOutConfirm = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                        Text("Ausloggen")
                                    }
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            VStack(spacing: 6) {
                                let year = String(Calendar.current.component(.year, from: Date()))
                                Text("SVS App")
                                    .font(.footnote.weight(.semibold))
                                Text("© \(year) Sachverständigenbüro Souleiman")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    if let user = appState.currentUser {
                        selectedColorName = UserColor.from(user.colorName).rawValue
                    }
                }
                .onChange(of: appState.currentUser?.id) {
                    if let user = appState.currentUser {
                        selectedColorName = UserColor.from(user.colorName).rawValue
                    }
                }
                .onChange(of: selectedColorName) {
                    guard let user = appState.currentUser else { return }
                    guard !isSavingColor else { return }

                    // Optimistic update: update local user immediately so UI tint updates
                    // even before Firestore listener delivers the new snapshot.
                    var updatedUser = user
                    updatedUser.colorName = selectedColorName
                    appState.currentUser = updatedUser

                    isSavingColor = true

                    let db = Firestore.firestore()
                    db.collection("users").document(user.id).setData([
                        "colorName": selectedColorName,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true) { err in
                        DispatchQueue.main.async {
                            if let err {
                                appState.uiErrorMessage = "Akzentfarbe konnte nicht gespeichert werden: \(err.localizedDescription)"
                                // Optional rollback on error: revert local change
                                appState.currentUser = user
                            }
                            isSavingColor = false
                        }
                    }
                }
                .alert("Wirklich ausloggen?", isPresented: $showSignOutConfirm) {
                    Button("Ausloggen", role: .destructive) {
                        guard !isSigningOut else { return }
                        isSigningOut = true

                        _Concurrency.Task { @MainActor in
                            let userId = appState.currentUser?.id

                            // 0) Token/Device-Registrierung entfernen (best effort)
                            if let userId {
                                do {
                                    try await removeCurrentDevicePushToken(for: userId)
                                } catch {
                                    // Nicht blockieren: Logout soll trotzdem funktionieren
                                    appState.uiErrorMessage = "Hinweis: Push-Token konnte nicht entfernt werden: \(error.localizedDescription)"
                                }
                            }

                            // 1) Firebase Auth abmelden
                            do {
                                try appState.auth.signOut()
                            } catch {
                                appState.uiErrorMessage = "Abmeldung fehlgeschlagen: \(error.localizedDescription)"
                                isSigningOut = false
                                return
                            }

                            // 2) Lokale Session/State bereinigen
                            appState.signOut()
                            isSigningOut = false
                        }
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text("Sie werden in der App abgemeldet.")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Menü")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func removeCurrentDevicePushToken(for userId: String) async throws {
        guard let token = Messaging.messaging().fcmToken, !token.isEmpty else {
            return
        }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)

        // Remove from an array field (common schema)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            userRef.setData([
                "fcmTokens": FieldValue.arrayRemove([token]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true) { err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ())
                }
            }
        }

        // Also try deleting a device doc (alternative schema). Ignore if it doesn't exist.
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                userRef.collection("devices").document(token).delete { _ in
                    // Best effort: ignore errors here
                    cont.resume(returning: ())
                }
            }
        }

        // Finally, delete the local token so this device stops receiving until next sign-in.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Messaging.messaging().deleteToken { err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func germanColorName(_ key: String) -> String {
        Color.svsGermanColorName(from: key)
    }

    private func colorForName(_ key: String) -> Color {
        Color.svsAccentColor(from: key)
    }

    private func germanRoleName(_ role: UserRole) -> String {
        switch role {
        case .admin:
            return "Administrator"
        case .employee:
            return "Mitarbeiter"
        case .expert:
            return "Sachverständiger"
        }
    }
}
