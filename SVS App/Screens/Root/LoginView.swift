//
//  LoginView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
@preconcurrency import FirebaseAuth

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil
    @State private var isPasswordVisible: Bool = false

    @FocusState private var focusedField: Field?
    private enum Field { case email, password }

    private var isShowingAlert: Binding<Bool> {
        Binding(
            get: { errorText != nil },
            set: { newValue in
                if !newValue { errorText = nil }
            }
        )
    }

    var body: some View {
        ZStack {
            // Hintergrund
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemBackground),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Dezente Akzentflächen
            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: -140, y: -220)

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 340, height: 340)
                .blur(radius: 22)
                .offset(x: 170, y: 240)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    // Header
                    VStack(spacing: 10) {
                        Image("svs_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 72)
                            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
                            .padding(.top, 26)

                        Text("SVS App")
                            .font(.title2.weight(.semibold))

                        Text("Mit E‑Mail und Passwort anmelden")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                    }
                    .padding(.bottom, 8)

                    // Card
                    VStack(spacing: 14) {
                        // E-Mail
                        HStack(spacing: 10) {
                            Image(systemName: "envelope")
                                .foregroundColor(.secondary)
                                .frame(width: 22)

                            TextField("E‑Mail", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .email)
                                .onSubmit { focusedField = .password }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemBackground))
                        )

                        // Passwort
                        HStack(spacing: 10) {
                            Image(systemName: "lock")
                                .foregroundColor(.secondary)
                                .frame(width: 22)

                            Group {
                                if isPasswordVisible {
                                    TextField("Passwort", text: $password)
                                } else {
                                    SecureField("Passwort", text: $password)
                                }
                            }
                            .font(.body)
                            .frame(height: 22)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit { attemptLogin() }

                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemBackground))
                        )

                        // Primary CTA
                        Button(action: { attemptLogin() }) {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .imageScale(.medium)
                                }

                                Text(isLoading ? "Bitte warten" : "Anmelden")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .buttonBorderShape(.capsule)
                        .sensoryFeedback(.success, trigger: isLoading == false && (errorText == nil))
                        .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                        // Reset
                        Button {
                            sendPasswordReset()
                        } label: {
                            Text("Passwort vergessen?")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)

                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.horizontal, 18)

                    Spacer(minLength: 10)
                }
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
        }
        .alert("Anmeldung nicht möglich", isPresented: isShowingAlert) {
            Button("OK", role: .cancel) {
                password = ""
                errorText = nil
            }
        } message: {
            Text(errorText ?? "Unbekannter Fehler")
        }
    }

    // MARK: - Actions

    private func attemptLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorText = "Bitte E‑Mail und Passwort eingeben."
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
    }

    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else {
            errorText = "Bitte zuerst die E‑Mail eingeben."
            return
        }

        _Concurrency.Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await FirebaseAuth.Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
                errorText = "E‑Mail zum Zurücksetzen wurde versendet."
            } catch {
                errorText = "Reset‑E‑Mail konnte nicht versendet werden. Bitte E‑Mail prüfen."
            }
        }
    }
}
