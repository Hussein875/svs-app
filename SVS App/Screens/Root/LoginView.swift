//
//  LoginView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedUser: User? = nil
    @State private var pin: String = ""
    @State private var showError: Bool = false

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

                        Text("Mitarbeiter auswählen und mit PIN anmelden")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }

                    // Selected User Card + PIN (immer sichtbar, sobald gewählt)
                    if let selected = selectedUser {
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                InitialsAvatarView(name: selected.name, color: selected.color)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selected.name)
                                        .font(.headline)
                                    Text(roleLabel(for: selected.role))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    // Auswahl zurücksetzen
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedUser = nil
                                        pin = ""
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 10) {
                                SecureField("PIN", text: $pin)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    if pin == selected.pin {
                                        appState.currentUser = selected
                                        appState.lastUserId = selected.id
                                        appState.sessionUserId = selected.id
                                        pin = ""
                                        selectedUser = nil
                                    } else {
                                        showError = true
                                    }
                                } label: {
                                    Text("Anmelden")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(pin.isEmpty)
                            }
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Schnellzugriff: zuletzt verwendet (kompakt)
                    if let lastId = appState.lastUserId,
                       let lastUser = appState.users.first(where: { $0.id == lastId }),
                       selectedUser == nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedUser = lastUser
                                pin = ""
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                Text("Zuletzt: ")
                                    .foregroundColor(.secondary)
                                Text(lastUser.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    // Mitarbeiter-Auswahl (2 Spalten, scrollt nur bei Bedarf)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mitarbeiter")
                            .font(.headline)
                            .padding(.horizontal)

                        let columns = [GridItem(.flexible()), GridItem(.flexible())]

                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(appState.users) { user in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedUser = user
                                            pin = ""
                                        }
                                    } label: {
                                        let selected = selectedUser?.id == user.id
                                        HStack(spacing: 10) {
                                            InitialsAvatarView(name: user.name, color: user.color)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(user.name)
                                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                                    .foregroundColor(.primary)
                                                Text(roleLabel(for: user.role))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(selected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(selected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                        }
                        .frame(maxHeight: max(220, geo.size.height * 0.36))
                    }

                    Spacer(minLength: 6)
                }
                .padding(.top, 6)
            }
            .alert("Falsche PIN", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    pin = ""
                }
            } message: {
                Text("Die eingegebene PIN ist nicht korrekt.")
            }
        }
    }
}
