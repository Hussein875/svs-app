//
//  EditLeaveRequestView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 02.01.26.
//

import SwiftUI
import Foundation

struct EditLeaveRequestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var request: LeaveRequest
    @State private var originalRequest: LeaveRequest
    @State private var inlineError: String? = nil
    @State private var showDeleteConfirm: Bool = false
    
    
    private func clearErrors() {
        inlineError = nil
        appState.uiErrorMessage = nil
    }

    private func saveAndDismiss() {
        let ok = appState.updateLeaveRequest(request)
        if ok {
            inlineError = nil
            dismiss()
        } else {
            inlineError = appState.uiErrorMessage
        }
    }

    init(request: LeaveRequest) {
        _request = State(initialValue: request)
        _originalRequest = State(initialValue: request)
    }

    private var canEdit: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let requestDay = cal.startOfDay(for: request.startDate)

        if request.type == .onCallSaturday {
            // Samstags-Bereitschaft ist sofort genehmigt, soll aber bis zum Termin editierbar bleiben.
            return requestDay >= today
        }

        return appState.canEditOrDelete(request, by: appState.currentUser)
    }

    private var hasChanges: Bool {
        request.startDate != originalRequest.startDate ||
        request.endDate != originalRequest.endDate
    }

    private var typeIcon: String {
        switch request.type {
        case .vacation:
            return "beach.umbrella"
        case .sick:
            return "cross.case"
        case .onCallSaturday:
            return "person.badge.clock"
        }
    }

    var body: some View {
        listView
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: request.startDate) { _, _ in
                clearErrors()
                if request.endDate < request.startDate { request.endDate = request.startDate }
            }
            .onChange(of: request.endDate) { _, _ in
                clearErrors()
            }
            // type is read-only here; no onChange needed
            .onAppear {
                originalRequest = request
            }
            .alert("Antrag wirklich löschen?", isPresented: $showDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    appState.deleteLeaveRequest(request)
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Der Antrag wird dauerhaft entfernt und kann nicht wiederhergestellt werden.")
            }
    }
    
    private var listView: some View {
        List {
            errorSection
            overviewSection
            dateSection
            typeSection
            if canEdit { actionsSection }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let inlineError {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(inlineError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var overviewSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.secondarySystemBackground))
                    Image(systemName: typeIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.user.name)
                        .font(.headline)
                        .foregroundColor(request.user.color)

                    Text(dateRangeString(request.startDate, request.endDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if request.type != .sick && request.type != .onCallSaturday {
                    statusBadgeView(request.status)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Übersicht")
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker("Von", selection: $request.startDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .disabled(!canEdit)

            DatePicker("Bis", selection: $request.endDate, in: request.startDate..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .disabled(!canEdit)
        } header: {
            Text("Zeitraum")
        } footer: {
            if !canEdit {
                Text(request.type == .onCallSaturday
                     ? "Diese Bereitschaft liegt in der Vergangenheit und kann nicht mehr bearbeitet werden."
                     : "Dieser Antrag wurde bereits entschieden und kann nicht mehr bearbeitet werden.")
            }
        }
    }

    private var typeSection: some View {
        Section {
            HStack {
                Text("Art")
                Spacer()
                Text(request.type.rawValue)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Art der Abwesenheit")
        }
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))

                    Text("Antrag löschen")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
            }
        } header: {
            Text("Aktionen")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if canEdit {
                Button("Speichern") {
                    saveAndDismiss()
                }
                .disabled(!hasChanges)
            }
        }
    }
}
