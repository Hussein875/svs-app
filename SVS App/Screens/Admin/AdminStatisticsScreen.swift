//
//  AdminStatisticsScreen.swift
//  SVS App
//

import SwiftUI

private enum AdminStatisticsTab: String, CaseIterable, Identifiable {
    case weekly = "Wochen"
    case yearBet = "Jahreswette"

    var id: String { rawValue }
}

struct AdminStatisticsScreen: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var weeklyViewModel = WeeklyStatsViewModel()
    @StateObject private var betViewModel = GutachtenYearBetViewModel()
    @State private var tab: AdminStatisticsTab = .weekly

    private var accent: Color {
        appState.currentUser?.color ?? Color(red: 0.09, green: 0.40, blue: 0.75)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $tab) {
                ForEach(AdminStatisticsTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            switch tab {
            case .weekly:
                AdminWeeklyStatsContent(viewModel: weeklyViewModel, accent: accent)
            case .yearBet:
                GutachtenYearBetView(
                    weeklyViewModel: weeklyViewModel,
                    betViewModel: betViewModel,
                    accent: accent
                )
                .environmentObject(appState)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if weeklyViewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        _Concurrency.Task { await weeklyViewModel.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await weeklyViewModel.refresh(force: true)
            betViewModel.startListeningIfNeeded()
        }
        .onDisappear {
            betViewModel.stopListening()
        }
    }
}

#Preview {
    NavigationStack {
        AdminStatisticsScreen()
            .environmentObject(AppState())
    }
}
