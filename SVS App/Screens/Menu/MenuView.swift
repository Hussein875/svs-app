//
//  MenuView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseAuth

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSignOutConfirm: Bool = false
    @State private var isSigningOut: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                
                List {
                    Section(header: Text("Benutzer")) {
                        if let user = appState.currentUser {
                            LabeledContent("Eingeloggt als") {
                                Text(user.name)
                                    .foregroundColor(.accentColor)
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
                    
                    Section(header: Text("App-Info")) {
                        LabeledContent("Version") {
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
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
                                Text("SVS App")
                                    .font(.footnote.weight(.semibold))
                                Text("© \(Calendar.current.component(.year, from: Date())) Sachverständigenbüro Souleiman")
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
}

