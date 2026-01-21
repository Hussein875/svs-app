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
import UIKit

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSignOutConfirm: Bool = false
    @State private var isSigningOut: Bool = false
    @State private var selectedColorName: String = "blue"
    @State private var isSavingColor: Bool = false
    
    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]
    
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
                                Text(user.role.rawValue)
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
                                ForEach(availableColors, id: \.self) { key in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(colorForName(key))
                                            .frame(width: 14, height: 14)
                                            .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                                        Text(germanColorName(key))
                                    }
                                    .tag(key)
                                }
                            }
                            .disabled(isSavingColor)

                            HStack(spacing: 8) {
                                Text("Vorschau")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Circle()
                                    .fill(colorForName(selectedColorName))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                                Spacer()
                            }

                            if isSavingColor {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Speichere…")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Die Akzentfarbe wird in deinem Profil gespeichert.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                        VStack(spacing: 10) {
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
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    if let user = appState.currentUser {
                        // Prefer persisted palette key if available; fallback to closest match.
                        if availableColors.contains(user.colorName) {
                            selectedColorName = user.colorName
                        } else {
                            selectedColorName = closestColorName(for: user.color)
                        }
                    }
                }
                .onChange(of: appState.currentUser?.id) {
                    if let user = appState.currentUser {
                        if availableColors.contains(user.colorName) {
                            selectedColorName = user.colorName
                        } else {
                            selectedColorName = closestColorName(for: user.color)
                        }
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

                    let chosen = colorForName(selectedColorName)
                    let hex = colorToHex(chosen)
                    let db = Firestore.firestore()
                    db.collection("users").document(user.id).setData([
                        "colorName": selectedColorName,
                        "colorHex": hex,
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
    
    private func germanColorName(_ key: String) -> String {
        switch key {
        case "blue": return "Blau"
        case "green": return "Grün"
        case "orange": return "Orange"
        case "purple": return "Lila"
        case "red": return "Rot"
        case "pink": return "Pink"
        case "teal": return "Türkis"
        case "indigo": return "Indigo"
        case "yellow": return "Gelb"
        case "gray": return "Grau"
        default: return key.capitalized
        }
    }

    private func colorForName(_ key: String) -> Color {
        switch key {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }

    private func closestColorName(for color: Color) -> String {
        let target = colorToHex(color)
        for key in availableColors {
            if colorToHex(colorForName(key)) == target {
                return key
            }
        }
        // fallback: try to keep the current selection if still valid
        return availableColors.contains(selectedColorName) ? selectedColorName : (availableColors.first ?? "gray")
    }

    private func colorToHex(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
