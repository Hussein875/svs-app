//
//  AdminWeeklyStatsView.swift
//  SVS App
//

import Combine
import Foundation
import SwiftUI

struct AdminWeeklyStatsScreen: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = WeeklyStatsViewModel()

    private var accent: Color {
        appState.currentUser?.color ?? Color(red: 0.09, green: 0.40, blue: 0.75)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !viewModel.lastFetchError.isEmpty {
                    errorBanner
                }

                if let latest = viewModel.latestWeek {
                    currentWeekCard(latest)
                }

                historySection
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Wochenstatistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        _Concurrency.Task { await viewModel.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await viewModel.refresh(force: true)
        }
        .refreshable {
            await viewModel.refresh(force: true)
        }
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(viewModel.lastFetchError)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func currentWeekCard(_ week: WeeklyStatsRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aktuelle KW")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("KW \(week.calendarWeek)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Ab Nr. \(week.weekStartNumber)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Gutachten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("\(week.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.lastFetchError.isEmpty ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(viewModel.lastFetchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if viewModel.isCurrentCalendarWeek(week) {
                    Text("Laufende Kalenderwoche")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historie")
                .font(.headline)

            if viewModel.weeks.isEmpty, !viewModel.isLoading {
                Text("Noch keine Wochenwerte geladen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("KW")
                            .frame(width: 56, alignment: .leading)
                        Text("Ab Nr.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Anzahl")
                            .frame(width: 56, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))

                    ForEach(viewModel.weeks) { week in
                        HStack {
                            Text("KW \(week.calendarWeek)")
                                .font(.subheadline.weight(week.id == viewModel.latestWeek?.id ? .semibold : .regular))
                                .frame(width: 56, alignment: .leading)

                            Text("\(week.weekStartNumber)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(week.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(week.id == viewModel.latestWeek?.id ? accent : .primary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            week.id == viewModel.latestWeek?.id
                                ? accent.opacity(0.08)
                                : Color(.secondarySystemBackground)
                        )

                        if week.id != viewModel.weeks.last?.id {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        AdminWeeklyStatsScreen()
            .environmentObject(AppState())
    }
}
