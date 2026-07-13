//
//  MainViewHome.swift
//  SVS App
//
//  Extracted from MainView.swift for readability.
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Arbeit (Home)

struct WorkHomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var pushDestination: HomePushDestination?

    private var displayName: String {
        let name = appState.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "" : name
    }

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var isEmployeeRole: Bool {
        appState.currentUser?.role == .employee
    }

    private var showsDocumentsTile: Bool {
        guard isEmployeeRole else { return true }
        return appState.currentUser?.documentsAccessEnabled ?? false
    }

    private var showsMyUploadsTile: Bool {
        guard isEmployeeRole else { return true }
        return appState.currentUser?.myUploadsAccessEnabled ?? false
    }

    private var showsCommissionTile: Bool {
        guard isEmployeeRole else { return false }
        return appState.currentUser?.commissionAccessEnabled ?? false
    }

    private var showsStargutachterTile: Bool {
        guard isEmployeeRole else { return false }
        return appState.currentUser?.stargutachterAccessEnabled ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: Header (clean)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.tint)

                            Text("Mein Bereich")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }

                        Text(displayName.isEmpty ? "Mein Bereich" : "Hallo, \(displayName)")
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)

                        // Subtle accent underline
                        Capsule(style: .continuous)
                            .fill(.tint)
                            .frame(width: 54, height: 4)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    if isEmployeeRole {
                        employeeToolsSection
                            .padding(.horizontal, 18)
                            .padding(.bottom, 18)
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            primaryToolsSection
                            additionalToolsSection
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                }
            }
            .navigationDestination(item: $pushDestination) { destination in
                switch destination.kind {
                case .tasksAssigned:
                    TasksView()
                case .tasksCompleted:
                    TasksView(
                        startInAssignedByMe: true,
                        startInDoneFilter: true
                    )
                case .myRequests:
                    MyRequestsScreen()
                case .myOnCallSaturdays:
                    MyOnCallSaturdaysScreen()
                case .dashboard:
                    DashboardView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .tint(userAccentColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Home sections

    private func homeSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var employeeToolsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsDocumentsTile || showsMyUploadsTile || showsCommissionTile {
                employeePrimarySection
            }

            employeeAdditionalSection

            if !showsDocumentsTile,
               !showsMyUploadsTile,
               !showsStargutachterTile,
               !showsCommissionTile {
                employeeAccessHint
            }
        }
    }

    @ViewBuilder
    private var employeePrimarySection: some View {
        VStack(spacing: 12) {
            if showsCommissionTile {
                NavigationLink {
                    ProvisionenView()
                } label: {
                    WorkCard(
                        title: "Prämie",
                        subtitle: "Vermittlungsprämie und Links",
                        systemImage: "eurosign.circle"
                    )
                }
                .buttonStyle(.plain)
            }

            if showsDocumentsTile {
                NavigationLink {
                    CompanyDocumentsView()
                } label: {
                    WorkCard(
                        title: "Dokumente",
                        subtitle: "Unterlagen und Vollmachten",
                        systemImage: "folder.fill"
                    )
                }
                .buttonStyle(.plain)
            }

            if showsMyUploadsTile {
                NavigationLink {
                    MyScannerUploadsView()
                } label: {
                    WorkCard(
                        title: "Meine Gutachten",
                        subtitle: "Gutachten-Ordner in Google Drive",
                        systemImage: "icloud.and.arrow.up.fill"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var employeeAdditionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionHeader("Weitere Bereiche")

            VStack(spacing: 12) {
                compactToolRow {
                    if showsStargutachterTile {
                        NavigationLink {
                            StargutachterView()
                        } label: {
                            CompactWorkCard(
                                title: "Stargutachter",
                                systemImage: "star.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        AccidentSketchGalleryView()
                    } label: {
                        CompactWorkCard(
                            title: "Schadenhergang",
                            systemImage: "pencil.and.scribble"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var employeeAccessHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weitere Bereiche")
                .font(.headline)
            Text("Dein Admin kann dir in der Nutzerverwaltung Dokumente, Uploads und weitere Kacheln freischalten.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var primaryToolsSection: some View {
        VStack(spacing: 12) {
            NavigationLink {
                DashboardView()
            } label: {
                WorkCard(
                    title: "Dashboard",
                    subtitle: "Übersicht und Kennzahlen",
                    systemImage: "chart.bar.xaxis"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProvisionenView()
            } label: {
                WorkCard(
                    title: "Prämie",
                    subtitle: "Vermittlungsprämie und Links",
                    systemImage: "eurosign.circle"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                CompanyDocumentsView()
            } label: {
                WorkCard(
                    title: "Dokumente",
                    subtitle: "Unterlagen und Vollmachten",
                    systemImage: "folder.fill"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MyScannerUploadsView()
            } label: {
                WorkCard(
                    title: "Meine Gutachten",
                    subtitle: "Gutachten-Ordner in Google Drive",
                    systemImage: "icloud.and.arrow.up.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var additionalToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionHeader("Weitere Bereiche")

            VStack(spacing: 12) {
                compactToolRow {
                    NavigationLink {
                        MyRequestsScreen()
                    } label: {
                        CompactWorkCard(
                            title: "Abwesenheiten",
                            systemImage: "doc.text"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        TasksView()
                    } label: {
                        CompactWorkCard(
                            title: "Aufgaben",
                            systemImage: "checklist"
                        )
                    }
                    .buttonStyle(.plain)
                }

                compactToolRow {
                    NavigationLink {
                        MeetingTopicsView()
                    } label: {
                        CompactWorkCard(
                            title: "Meeting",
                            systemImage: "person.3.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StargutachterView()
                    } label: {
                        CompactWorkCard(
                            title: "Stargutachter",
                            systemImage: "star.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                compactToolRow {
                    NavigationLink {
                        MyOnCallSaturdaysScreen()
                    } label: {
                        CompactWorkCard(
                            title: "Bereitschaft",
                            systemImage: "calendar"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AccidentSketchGalleryView()
                    } label: {
                        CompactWorkCard(
                            title: "Schadenhergang",
                            systemImage: "pencil.and.scribble"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func compactToolRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
    }
}
