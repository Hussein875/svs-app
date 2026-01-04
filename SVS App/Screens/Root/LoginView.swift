//
//  LoginView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    // Header (kompakt)
                    VStack(spacing: 8) {
                        Image("svs_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 54)
                            .padding(.top, 8)

                        Text("SVS Mitarbeiter-App")
                            .font(.title3.weight(.semibold))

                        Text("Mit E-Mail und Passwort anmelden")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }

                    // Login-Formular (E-Mail + Passwort)
                    VStack(spacing: 12) {
                        TextField("E-Mail", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Passwort", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            guard !trimmedEmail.isEmpty, !password.isEmpty else {
                                errorText = "Bitte E-Mail und Passwort eingeben."
                                return
                            }

                            _Concurrency.Task {
                                isLoading = true
                                defer { isLoading = false }
                                errorText = nil
                                do {
                                    try await appState.auth.signIn(email: trimmedEmail, password: password)
                                } catch {
                                    errorText = "Anmeldung fehlgeschlagen. Bitte Zugangsdaten prüfen oder Admin kontaktieren."
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isLoading ? "Bitte warten" : "Anmelden")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                        Button("Passwort vergessen?") {
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            guard !trimmedEmail.isEmpty else {
                                errorText = "Bitte zuerst die E-Mail eingeben."
                                return
                            }

                            _Concurrency.Task {
                                isLoading = true
                                defer { isLoading = false }
                                do {
                                    try await FirebaseAuth.Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
                                    errorText = "E-Mail zum Zurücksetzen wurde versendet."
                                } catch {
                                    errorText = "Reset-E-Mail konnte nicht versendet werden. Bitte E-Mail prüfen."
                                }
                            }
                        }
                        .font(.footnote)
                        .padding(.top, 2)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    Spacer(minLength: 6)
                }
                .padding(.top, 6)
            }
            .alert("Anmeldung nicht möglich", isPresented: .constant(errorText != nil)) {
                Button("OK", role: .cancel) {
                    password = ""
                    errorText = nil
                }
            } message: {
                Text(errorText ?? "Unbekannter Fehler")
            }
        }
    }
}
