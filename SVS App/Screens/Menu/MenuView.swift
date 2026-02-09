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
                .navigationTitle("Einstellungen")
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
        Section {
            if let user = appState.currentUser {
                userProfileCard(user)
            } else {
                Text("Nicht eingeloggt")
                    .foregroundColor(.secondary)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var appearanceSection: some View {
        Section(header: Text("Erscheinungsbild")) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                        count: 6
                    ),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(availableColors, id: \.self) { color in
                        colorChip(color)
                    }
                }
            }
            .padding(.vertical, 2)
            .disabled(isSavingColor)
            HStack(spacing: 6) {
                Text("Aktuell:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(UserColor.from(selectedColorName).germanName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var appInfoSection: some View {
        Section(header: Text("App-Info")) {
            infoRow(
                title: "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–",
                systemImage: "number"
            )
            infoRow(
                title: "Entwickelt von",
                value: "Hussein Souleiman",
                systemImage: "person.crop.circle"
            )
            infoRow(
                title: "Entwickelt für",
                value: "SV Souleiman",
                systemImage: "building.2"
            )
        }
    }

    private var signOutAndFooterSection: some View {
        Section {
            VStack(spacing: 12) {
                if appState.currentUser != nil {
                    Button {
                        showSignOutConfirm = true
                    } label: {
                        Text("Ausloggen")
                            .frame(maxWidth: .infinity, alignment: .center)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
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

    private func userProfileCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(user.color.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(user.color)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(germanRoleName(user.role))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(user.email)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(user.color.opacity(0.30), lineWidth: 1)
        )
    }

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func colorChip(_ color: UserColor) -> some View {
        let isSelected = selectedColorName == color.rawValue

        return Button {
            guard !isSavingColor else { return }
            selectedColorName = color.rawValue
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.24),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                            .padding(4)
                    Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white, Color.black.opacity(0.25))
                }
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 36)
        .accessibilityLabel(color.germanName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
