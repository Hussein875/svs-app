//
//  MainViewHomeComponents.swift
//  SVS App
//
//  Extracted from MainViewHome.swift for readability.
//

import Foundation
import SwiftUI
import FirebaseFirestore

struct MyOnCallSaturdaysScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var deleteTarget: LeaveRequest?
    @State private var isConfirmingDelete = false
    @State private var deleteErrorMessage: String? = nil

    private var meId: String {
        appState.currentUser?.id ?? ""
    }

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var isDeleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { _ in deleteErrorMessage = nil }
        )
    }

    private var currentYearInterval: DateInterval {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        return DateInterval(start: start, end: end)
    }

    private var myCountThisYear: Int {
        appState.leaveRequests
            .filter { $0.user.id == meId }
            .filter { $0.type == .onCallSaturday }
            .filter { currentYearInterval.contains($0.startDate) }
            .count
    }

    private func allSaturdays(in interval: DateInterval) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var d = cal.startOfDay(for: interval.start)

        while cal.component(.weekday, from: d) != 7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }

        while d < interval.end {
            dates.append(d)
            guard let next = cal.date(byAdding: .day, value: 7, to: d) else { break }
            d = next
        }

        return dates
    }

    private func onCallRequest(for date: Date) -> LeaveRequest? {
        let cal = Calendar.current
        return appState.leaveRequests.first(where: {
            $0.type == .onCallSaturday && cal.isDate($0.startDate, inSameDayAs: date)
        })
    }

    private func isMine(_ r: LeaveRequest?) -> Bool {
        guard let r else { return false }
        return r.user.id == meId
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE, dd.MM.yyyy"
        return f.string(from: date)
    }

    // Helper for displaying a Saturday row
    private func saturdayRow(
        sat: Date,
        mine: Bool,
        taken: Bool,
        ownerName: String,
        format: String,
        showTrash: Bool,
        onTrash: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    mine ? Color.green.opacity(0.18) :
                        (taken ? Color.orange.opacity(0.18) : Color.blue.opacity(0.12))
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: mine ? "checkmark" : (taken ? "lock.fill" : "plus"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(format)
                    .font(.headline)
                if mine {
                    Text("Meine Bereitschaft")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if taken {
                    let label = ownerName.isEmpty ? "Belegt" : "Belegt · \(ownerName)"
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Frei")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            if !taken {
                // Show capsule affordance, but not as a link.
                Text("Eintragen")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            } else if showTrash {
                Button {
                    onTrash()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bereitschaft löschen")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let saturdays = allSaturdays(in: currentYearInterval)
        let upcomingSaturdays = Array(saturdays.filter { $0 >= today }.prefix(8))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Samstage")
                        .font(.headline)

                    VStack(spacing: 10) {
                        ForEach(upcomingSaturdays, id: \.self) { sat in
                            let r = onCallRequest(for: sat)
                            let mine = isMine(r)
                            let taken = (r != nil)
                            let ownerName = r?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                            let row = saturdayRow(
                                sat: sat,
                                mine: mine,
                                taken: taken,
                                ownerName: ownerName,
                                format: format(sat),
                                showTrash: mine,
                                onTrash: {
                                    if let req = r {
                                        deleteTarget = req
                                        isConfirmingDelete = true
                                    }
                                }
                            )

                            if !taken {
                                // Only free Saturdays are tappable (create new on-call).
                                NavigationLink {
                                    NewOnCallSaturdayView(prefilledDate: sat)
                                } label: {
                                    row
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Taken Saturdays are not tappable. My own show a trash button.
                                row
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .background(Color(.systemGroupedBackground))
        .tint(userAccentColor)
        .navigationTitle("Bereitschaft")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Bereitschaft löschen?",
            isPresented: $isConfirmingDelete,
            presenting: deleteTarget
        ) { req in
            Button("Löschen", role: .destructive) {
                deleteOnCall(req)
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) {
                deleteTarget = nil
            }
        } message: { _ in
            Text("Möchtest du die Bereitschaft wirklich löschen?")
        }
        .alert("Löschen fehlgeschlagen", isPresented: isDeleteErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private func deleteOnCall(_ req: LeaveRequest) {
        // Keep a snapshot for rollback.
        let snapshot = appState.leaveRequests

        // Optimistic UI update: remove locally so the Saturday becomes "Frei" immediately.
        appState.leaveRequests.removeAll { $0.id == req.id }

        // Persist delete to Firestore.
        _Concurrency.Task {
            do {
                // Assumption: Firestore document id equals req.id.uuidString.
                // If your backend uses a different document id, adjust here.
                try await Firestore.firestore()
                    .collection("leaveRequests")
                    .document(req.id.uuidString)
                    .delete()
            } catch {
                // Roll back local state and show error.
                await MainActor.run {
                    appState.leaveRequests = snapshot
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct StatPill: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                Text("\(value)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

struct StatTextPill: View {
    let title: String
    let valueText: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                Text(valueText)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

struct WorkCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let trailingValue: Int

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.tint.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if trailingValue > 0 {
                Text("\(trailingValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 5)
    }
}

struct CompactWorkCard: View {
    let title: String
    let systemImage: String
    let badgeText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tint)
                    )

                Spacer(minLength: 0)

                if let badgeText {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 5)
    }
}
