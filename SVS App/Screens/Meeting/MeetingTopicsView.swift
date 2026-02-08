//
//  MeetingTopicsView.swift
//  SVS App
//
//  Created by Codex on 08.02.26.
//

import SwiftUI

struct MeetingTopicsView: View {
    @EnvironmentObject var appState: AppState

    @State private var newTitle: String = ""
    @State private var newDetails: String = ""
    @State private var isEditingMeetingDate: Bool = false
    @State private var meetingDateDraft: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @FocusState private var isInputFocused: Bool

    private var isAdmin: Bool {
        appState.currentUser?.role == .admin
    }

    private var openTopics: [MeetingTopic] {
        appState.meetingTopics
            .filter { $0.status == .open }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var doneTopics: [MeetingTopic] {
        appState.meetingTopics
            .filter { $0.status == .done }
            .sorted {
                let lhs = $0.updatedAt ?? $0.createdAt
                let rhs = $1.updatedAt ?? $1.createdAt
                return lhs > rhs
            }
    }

    private var nextMeetingDisplayText: String {
        guard let next = appState.nextMeetingAt else { return "Nicht festgelegt" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd.MM.yyyy · HH:mm"
        return f.string(from: next)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.tint)
                        Text(nextMeetingDisplayText)
                            .font(.subheadline.weight(.semibold))
                    }

                    if isAdmin {
                        if isEditingMeetingDate {
                            DatePicker(
                                "Datum & Uhrzeit",
                                selection: $meetingDateDraft,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)

                            HStack(spacing: 10) {
                                Button {
                                    appState.saveNextMeeting(date: meetingDateDraft)
                                    isEditingMeetingDate = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark")
                                        Text("Speichern")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(MeetingActionPrimaryButtonStyle())

                                Button(role: .cancel) {
                                    if let existing = appState.nextMeetingAt {
                                        meetingDateDraft = existing
                                    }
                                    isEditingMeetingDate = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "xmark")
                                        Text("Abbrechen")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(MeetingActionSecondaryButtonStyle())
                            }
                            .padding(.top, 2)
                        } else {
                            Button {
                                meetingDateDraft = appState.nextMeetingAt
                                    ?? (Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
                                isEditingMeetingDate = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Meeting-Termin bearbeiten")
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(MeetingActionSecondaryButtonStyle())
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Nächstes Meeting", systemImage: "clock")
            } footer: {
                Text("Dieser Termin ist für alle sichtbar. Bearbeiten kann ihn nur ein Admin.")
            }

            Section {
                TextField("Thema", text: $newTitle)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($isInputFocused)

                TextField("Details (optional)", text: $newDetails, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($isInputFocused)

                Button {
                    addTopic()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Meeting-Punkt hinzufügen")
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MeetingActionPrimaryButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Label("Neuer Punkt", systemImage: "plus.bubble")
            } footer: {
                Text("Jeder Mitarbeiter kann hier Themen für das Monatsmeeting sammeln.")
            }

            if openTopics.isEmpty {
                Section {
                    Text("Aktuell keine offenen Meeting-Punkte.")
                        .foregroundColor(.secondary)
                } header: {
                    Label("Offen", systemImage: "list.bullet.circle")
                }
            } else {
                Section {
                    ForEach(openTopics) { topic in
                        MeetingTopicRow(
                            topic: topic,
                            creatorName: appState.userName(for: topic.createdByUserId),
                            canEdit: appState.canEditMeetingTopic(topic, by: appState.currentUser),
                            canDelete: appState.canDeleteMeetingTopic(topic, by: appState.currentUser),
                            onToggle: { appState.toggleMeetingTopicStatus(for: topic) },
                            onDelete: { appState.deleteMeetingTopic(topic) }
                        )
                    }
                } header: {
                    Label("Offen", systemImage: "list.bullet.circle")
                }
            }

            if !doneTopics.isEmpty {
                Section {
                    ForEach(doneTopics) { topic in
                        MeetingTopicRow(
                            topic: topic,
                            creatorName: appState.userName(for: topic.createdByUserId),
                            canEdit: appState.canEditMeetingTopic(topic, by: appState.currentUser),
                            canDelete: appState.canDeleteMeetingTopic(topic, by: appState.currentUser),
                            onToggle: { appState.toggleMeetingTopicStatus(for: topic) },
                            onDelete: { appState.deleteMeetingTopic(topic) }
                        )
                    }
                } header: {
                    Label("Erledigt", systemImage: "checkmark.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                isInputFocused = false
            },
            including: .subviews
        )
        .refreshable {
            await appState.refreshMeetingTopicsFromServer()
        }
        .onAppear {
            if let existing = appState.nextMeetingAt {
                meetingDateDraft = existing
            }
        }
        .onChange(of: appState.nextMeetingAt) { next in
            guard let next else { return }
            if !isEditingMeetingDate {
                meetingDateDraft = next
            }
        }
        .navigationTitle("Meeting")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addTopic() {
        appState.createMeetingTopic(title: newTitle, details: newDetails)
        newTitle = ""
        newDetails = ""
        isInputFocused = false
    }
}

private struct MeetingActionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.78 : 0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MeetingActionSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(configuration.isPressed ? 0.28 : 0.18), lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MeetingTopicRow: View {
    let topic: MeetingTopic
    let creatorName: String
    let canEdit: Bool
    let canDelete: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var createdText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: topic.createdAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: topic.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(topic.status == .done ? .green : .secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .opacity(canEdit ? 1.0 : 0.55)

            VStack(alignment: .leading, spacing: 5) {
                Text(topic.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(topic.status == .done, color: .secondary)

                if !topic.details.isEmpty {
                    Text(topic.details)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                Text("Von \(creatorName) · \(createdText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }
}
