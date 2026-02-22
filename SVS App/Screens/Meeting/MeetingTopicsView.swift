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
    @State private var showArchiveConfirmation: Bool = false
    @State private var showDeleteMeetingDateConfirmation: Bool = false
    @State private var selectedArchive: MeetingArchive?
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

    private var hasActiveMeetingTopics: Bool {
        !appState.meetingTopics.isEmpty
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

                            if appState.nextMeetingAt != nil {
                                Button {
                                    showDeleteMeetingDateConfirmation = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                        Text("Termin löschen")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            }
                        } else {
                            Button {
                                meetingDateDraft = appState.nextMeetingAt
                                    ?? (Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
                                isEditingMeetingDate = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text(appState.nextMeetingAt == nil ? "Meeting-Termin anlegen" : "Meeting-Termin bearbeiten")
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
                Label("Neuer Meeting-Punkt", systemImage: "plus.bubble")
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

            Section {
                if appState.meetingArchives.isEmpty {
                    Text("Noch keine archivierten Meetings.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.meetingArchives) { archive in
                        if isAdmin {
                            Button {
                                isInputFocused = false
                                selectedArchive = archive
                            } label: {
                                MeetingArchiveRow(archive: archive)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appState.deleteMeetingArchive(archive)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        } else {
                            Button {
                                isInputFocused = false
                                selectedArchive = archive
                            } label: {
                                MeetingArchiveRow(archive: archive)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Label("Archiv", systemImage: "archivebox")
            }

            if isAdmin {
                Section {
                    Button(role: .destructive) {
                        isInputFocused = false
                        showArchiveConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox.fill")
                            Text("Meeting abschließen & archivieren")
                            Spacer()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(MeetingActionDangerButtonStyle())
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .disabled(!hasActiveMeetingTopics)
                } header: {
                    Label("Meeting abschließen", systemImage: "flag.checkered")
                } footer: {
                    Text("Archiviert alle aktuellen Punkte als unveränderbares Protokoll und leert die offene Liste.")
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
        .alert("Meeting-Termin löschen?", isPresented: $showDeleteMeetingDateConfirmation) {
            Button("Löschen", role: .destructive) {
                isEditingMeetingDate = false
                appState.clearNextMeetingDate()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der nächste Meeting-Termin wird entfernt.")
        }
        .alert("Meeting abschließen?", isPresented: $showArchiveConfirmation) {
            Button("Archivieren", role: .destructive) {
                _Concurrency.Task {
                    await appState.archiveCurrentMeeting()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle aktuellen Meeting-Punkte werden ins Archiv verschoben und können danach nicht mehr bearbeitet werden.")
        }
        .sheet(item: $selectedArchive) { archive in
            MeetingArchiveDetailView(
                archive: archive,
                userNameForId: { userId in appState.userName(for: userId) },
                canDeleteArchive: isAdmin,
                canEditProtocol: isAdmin,
                onSaveProtocol: { updatedText in
                    await appState.updateMeetingArchiveProtocol(
                        archive,
                        protocolText: updatedText
                    )
                },
                onDeleteArchive: {
                    appState.deleteMeetingArchive(archive)
                    selectedArchive = nil
                }
            )
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
