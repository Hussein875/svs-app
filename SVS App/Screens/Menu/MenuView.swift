//
//  MenuView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseMessaging
import UIKit

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSignOutConfirm: Bool = false
    @State private var isSigningOut: Bool = false
    @State private var selectedColorName: String = "blue"
    @State private var isSavingColor: Bool = false

    private let availableColors = UserColor.allCases

    var body: some View {
        NavigationStack {
            menuList
                .navigationTitle("Menü")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var menuList: some View {
        List {
            userSection
            if appState.currentUser != nil {
                appearanceSection
            }
            appInfoSection
            signOutAndFooterSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            syncStateFromCurrentUser()
        }
        .onChange(of: appState.currentUser?.id) {
            syncStateFromCurrentUser()
        }
        .onChange(of: selectedColorName) {
            handleColorChange()
        }
        .alert("Wirklich ausloggen?", isPresented: $showSignOutConfirm) {
            Button("Ausloggen", role: .destructive) {
                guard !isSigningOut else { return }
                isSigningOut = true

                _Concurrency.Task { @MainActor in
                    await performSignOut()
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Sie werden in der App abgemeldet.")
        }
    }

    private var userSection: some View {
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
    }

    private var appearanceSection: some View {
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

    private var appInfoSection: some View {
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
    }

    private var signOutAndFooterSection: some View {
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

    private func syncStateFromCurrentUser() {
        if let user = appState.currentUser {
            selectedColorName = UserColor.from(user.colorName).rawValue
        }
    }

    private func handleColorChange() {
        guard let user = appState.currentUser else { return }
        guard !isSavingColor else { return }

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
                    appState.currentUser = user
                }
                isSavingColor = false
            }
        }
    }

    @MainActor
    private func performSignOut() async {
        let userId = appState.currentUser?.id

        if let userId {
            do {
                try await removeCurrentDevicePushToken(for: userId)
            } catch {
                appState.uiErrorMessage = "Hinweis: Push-Token konnte nicht entfernt werden: \(error.localizedDescription)"
            }
        }

        do {
            try appState.auth.signOut()
        } catch {
            appState.uiErrorMessage = "Abmeldung fehlgeschlagen: \(error.localizedDescription)"
            isSigningOut = false
            return
        }

        appState.signOut()
        isSigningOut = false
    }

    private func removeCurrentDevicePushToken(for userId: String) async throws {
        let token = Messaging.messaging().fcmToken
        let deviceId = UIDevice.current.identifierForVendor?.uuidString
        let hasToken = token?.isEmpty == false
        let hasDeviceId = deviceId?.isEmpty == false

        guard hasToken || hasDeviceId else {
            return
        }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)

        if let token, !token.isEmpty {
            // Remove from array field if present (legacy schema).
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
        }

        // Remove device registration from the active schema: users/<uid>/devices/<deviceId>
        if let deviceId, !deviceId.isEmpty {
            do {
                try await userRef.collection("devices").document(deviceId).delete()
            } catch {
                // Best effort.
            }
        }

        // Backward-compatible cleanup if older entries used token as document id.
        if let token, !token.isEmpty, token != deviceId {
            do {
                try await userRef.collection("devices").document(token).delete()
            } catch {
                // Best effort.
            }
        }

        if hasToken {
            // Finally, delete local token so this device stops receiving until next sign-in.
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
