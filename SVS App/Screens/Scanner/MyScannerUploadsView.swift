//
//  MyScannerUploadsView.swift
//  SVS App
//

import SwiftUI

struct MyScannerUploadsView: View {
    @EnvironmentObject private var appState: AppState

    private var accent: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var uploads: [ScannerUploadEntry] {
        appState.scannerUploads
    }

    private var canViewUploads: Bool {
        guard let user = appState.currentUser else { return false }
        if user.role != .employee { return true }
        return user.myUploadsAccessEnabled
    }

    var body: some View {
        Group {
            if !canViewUploads {
                accessDeniedState
            } else if uploads.isEmpty {
                emptyState
            } else {
                uploadsList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Meine Gutachten")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var uploadsList: some View {
        List {
            Section {
                ForEach(uploads) { upload in
                    uploadRow(upload)
                }
            } footer: {
                Text("Tippe auf einen Eintrag, um den Gutachten-Ordner in Google Drive zu öffnen.")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func uploadRow(_ upload: ScannerUploadEntry) -> some View {
        if let folderURL = upload.driveFolderURL {
            Button {
                UIApplication.shared.open(folderURL)
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: upload.isUploaded ? "checkmark.circle.fill" : "folder.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(accent)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(upload.numberLabel)
                                .font(.headline)
                                .foregroundColor(.primary)

                            statusBadge(for: upload)
                        }

                        Text(upload.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        if let fileName = upload.uploadedFileName, !fileName.isEmpty {
                            Text(fileName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func statusBadge(for upload: ScannerUploadEntry) -> some View {
        Text(upload.isUploaded ? "Hochgeladen" : "Reserviert")
            .font(.caption2.weight(.semibold))
            .foregroundColor(upload.isUploaded ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        (upload.isUploaded ? Color.green : Color.secondary)
                            .opacity(0.12)
                    )
            )
    }

    private var accessDeniedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Gutachten nicht freigeschaltet")
                .font(.headline)

            Text("Dein Admin kann den Zugriff auf Meine Gutachten in der Nutzerverwaltung aktivieren.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Noch keine Gutachten")
                .font(.headline)

            Text("Reservierte Gutachten-Nummern und hochgeladene Scans erscheinen hier mit Link zum Drive-Ordner.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        MyScannerUploadsView()
            .environmentObject(AppState())
    }
}
