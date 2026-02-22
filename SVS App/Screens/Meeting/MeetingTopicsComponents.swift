//
//  MeetingTopicsComponents.swift
//  SVS App
//
//  Extracted from MeetingTopicsView.swift for readability.
//

import Foundation
import SwiftUI

struct MeetingActionPrimaryButtonStyle: ButtonStyle {
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

struct MeetingActionSecondaryButtonStyle: ButtonStyle {
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

struct MeetingActionDangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.72 : 0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MeetingTopicRow: View {
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

struct MeetingArchiveRow: View {
    let archive: MeetingArchive

    private var meetingDateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd.MM.yyyy · HH:mm"
        return f.string(from: archive.meetingDate)
    }

    private var topicCountText: String {
        let c = archive.topicCount
        return "\(c) Punkt" + (c == 1 ? "" : "e")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(meetingDateText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(topicCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct MeetingArchiveDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteArchiveConfirmation: Bool = false
    @State private var protocolDraft: String = ""
    @State private var isEditingProtocol: Bool = false
    @State private var isSavingProtocol: Bool = false

    let archive: MeetingArchive
    let userNameForId: (String) -> String
    let canDeleteArchive: Bool
    let canEditProtocol: Bool
    let onSaveProtocol: (String) async -> Bool
    let onDeleteArchive: () -> Void

    private var sortedTopics: [MeetingTopic] {
        archive.topics.sorted { $0.createdAt < $1.createdAt }
    }

    private var meetingDateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd.MM.yyyy · HH:mm"
        return f.string(from: archive.meetingDate)
    }

    private var archivedAtText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.string(from: archive.archivedAt)
    }

    private var hasProtocolChanges: Bool {
        protocolDraft != archive.protocolText
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(meetingDateText, systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                        Label("Archiviert am \(archivedAtText)", systemImage: "archivebox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("\(archive.topicCount) Punkt" + (archive.topicCount == 1 ? "" : "e"), systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Meeting")
                }

                Section {
                    if sortedTopics.isEmpty {
                        Text("Keine Punkte im Archiv hinterlegt.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedTopics) { topic in
                            ArchivedMeetingTopicRow(
                                topic: topic,
                                creatorName: userNameForId(topic.createdByUserId)
                            )
                        }
                    }
                } header: {
                    Text("Archivierte Punkte")
                }

                Section {
                    if isEditingProtocol && canEditProtocol {
                        TextEditor(text: $protocolDraft)
                            .font(.footnote.monospaced())
                            .frame(minHeight: 180)

                        HStack(spacing: 10) {
                            Button("Abbrechen", role: .cancel) {
                                protocolDraft = archive.protocolText
                                isEditingProtocol = false
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(MeetingActionSecondaryButtonStyle())

                            Button {
                                guard !isSavingProtocol else { return }
                                isSavingProtocol = true
                                _Concurrency.Task {
                                    let ok = await onSaveProtocol(protocolDraft)
                                    await MainActor.run {
                                        isSavingProtocol = false
                                        if ok {
                                            isEditingProtocol = false
                                        }
                                    }
                                }
                            } label: {
                                if isSavingProtocol {
                                    Text("Speichern …")
                                } else {
                                    Text("Speichern")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(MeetingActionPrimaryButtonStyle())
                            .disabled(isSavingProtocol || !hasProtocolChanges)
                        }
                    } else {
                        if protocolDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Noch kein Protokolltext vorhanden.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(protocolDraft)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }

                        if canEditProtocol {
                            Button {
                                isEditingProtocol = true
                            } label: {
                                Label("Protokoll bearbeiten", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Protokoll")
                }
            }
            .navigationTitle("Meeting-Archiv")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                protocolDraft = archive.protocolText
            }
            .toolbar {
                if canDeleteArchive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive) {
                            showDeleteArchiveConfirmation = true
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
            .alert("Archiviertes Meeting löschen?", isPresented: $showDeleteArchiveConfirmation) {
                Button("Löschen", role: .destructive) {
                    onDeleteArchive()
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Dieses archivierte Meeting wird dauerhaft gelöscht.")
            }
        }
    }
}

struct ArchivedMeetingTopicRow: View {
    let topic: MeetingTopic
    let creatorName: String

    private var createdText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: topic.createdAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: topic.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(topic.status == .done ? .green : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.body.weight(.semibold))

                if !topic.details.isEmpty {
                    Text(topic.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Von \(creatorName) · \(createdText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
