//
//  AdminAppAccessHubView.swift
//  SVS App
//

import SwiftUI

struct AdminAppAccessHubView: View {
    @EnvironmentObject private var appState: AppState

    @State private var roleFilter: AdminUserRoleFilter = .all
    @State private var searchText = ""

    private var filteredUsers: [User] {
        let base = appState.users.filter { user in
            switch roleFilter {
            case .all: return true
            case .admins: return user.role == .admin
            case .employees: return user.role == .employee
            case .experts: return user.role == .expert
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return base
            .filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.email.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Picker("Rolle", selection: $roleFilter) {
                    ForEach(AdminUserRoleFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            ForEach(AppAccessBooleanFeature.groupedFeatures, id: \.group) { section in
                Section(section.group.rawValue) {
                    ForEach(section.features) { feature in
                        NavigationLink {
                            AdminAppAccessBooleanFeatureView(
                                feature: feature,
                                users: filteredUsers
                            )
                            .environmentObject(appState)
                        } label: {
                            featureRow(feature)
                        }
                    }
                }
            }

            if !AppAccessFeatureCatalog.lawyerPowerFeatures.isEmpty {
                Section(AppAccessFeatureGroup.lawyerPowers.rawValue) {
                    ForEach(AppAccessFeatureCatalog.lawyerPowerFeatures) { feature in
                        NavigationLink {
                            AdminAppAccessLawyerPowerFeatureView(
                                feature: feature,
                                users: filteredUsers
                            )
                            .environmentObject(appState)
                        } label: {
                            lawyerPowerRow(feature)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Berechtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Personen filtern")
    }

    private func featureRow(_ feature: AppAccessBooleanFeature) -> some View {
        let enabledCount = filteredUsers.filter { feature.isEnabled(for: $0) }.count
        let totalCount = filteredUsers.count

        return HStack(spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("\(enabledCount)/\(totalCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.tertiarySystemBackground)))
        }
        .padding(.vertical, 2)
    }

    private func lawyerPowerRow(_ feature: AppAccessLawyerPowerFeature) -> some View {
        let enabledCount = filteredUsers.filter { feature.isEnabled(for: $0) }.count
        let totalCount = filteredUsers.count

        return HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle = feature.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text("\(enabledCount)/\(totalCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.tertiarySystemBackground)))
        }
        .padding(.vertical, 2)
    }
}

struct AdminAppAccessBooleanFeatureView: View {
    @EnvironmentObject private var appState: AppState

    let feature: AppAccessBooleanFeature
    let users: [User]

    @State private var workingUsers: [User] = []
    @State private var isApplyingBulk = false

    private var enabledCount: Int {
        workingUsers.filter { feature.isEnabled(for: $0) }.count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(feature.title, systemImage: feature.systemImage)
                        .font(.headline)
                    Text(feature.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(enabledCount) von \(workingUsers.count) aktiv")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Personen") {
                if workingUsers.isEmpty {
                    Text("Keine Personen im aktuellen Filter.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($workingUsers) { $user in
                        Toggle(isOn: binding(for: $user)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(SuperAdmin.displayRoleTitle(for: user))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Alle aus") {
                    applyBulk(enabled: false)
                }
                .disabled(workingUsers.isEmpty || isApplyingBulk)

                Button("Alle an") {
                    applyBulk(enabled: true)
                }
                .disabled(workingUsers.isEmpty || isApplyingBulk)
            }
        }
        .onAppear {
            workingUsers = users
        }
        .onChange(of: users) { _, newUsers in
            workingUsers = newUsers
        }
    }

    private func binding(for user: Binding<User>) -> Binding<Bool> {
        Binding(
            get: { feature.isEnabled(for: user.wrappedValue) },
            set: { newValue in
                var updated = user.wrappedValue
                feature.apply(enabled: newValue, to: &updated)
                user.wrappedValue = updated
                appState.updateUser(updated)
            }
        )
    }

    private func applyBulk(enabled: Bool) {
        guard !workingUsers.isEmpty else { return }
        isApplyingBulk = true

        var updatedUsers = workingUsers
        for index in updatedUsers.indices {
            feature.apply(enabled: enabled, to: &updatedUsers[index])
        }
        workingUsers = updatedUsers

        for user in updatedUsers {
            appState.updateUser(user)
        }

        isApplyingBulk = false
    }
}

struct AdminAppAccessLawyerPowerFeatureView: View {
    @EnvironmentObject private var appState: AppState

    let feature: AppAccessLawyerPowerFeature
    let users: [User]

    @State private var workingUsers: [User] = []
    @State private var isApplyingBulk = false

    private var enabledCount: Int {
        workingUsers.filter { feature.isEnabled(for: $0) }.count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(feature.title)
                        .font(.headline)
                    if let subtitle = feature.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(enabledCount) von \(workingUsers.count) aktiv")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Personen") {
                if workingUsers.isEmpty {
                    Text("Keine Personen im aktuellen Filter.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($workingUsers) { $user in
                        Toggle(isOn: binding(for: $user)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(SuperAdmin.displayRoleTitle(for: user))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Alle aus") {
                    applyBulk(enabled: false)
                }
                .disabled(workingUsers.isEmpty || isApplyingBulk)

                Button("Alle an") {
                    applyBulk(enabled: true)
                }
                .disabled(workingUsers.isEmpty || isApplyingBulk)
            }
        }
        .onAppear {
            workingUsers = users
        }
        .onChange(of: users) { _, newUsers in
            workingUsers = newUsers
        }
    }

    private func binding(for user: Binding<User>) -> Binding<Bool> {
        Binding(
            get: { feature.isEnabled(for: user.wrappedValue) },
            set: { newValue in
                var updated = user.wrappedValue
                feature.apply(enabled: newValue, to: &updated)
                user.wrappedValue = updated
                appState.updateUser(updated)
            }
        )
    }

    private func applyBulk(enabled: Bool) {
        guard !workingUsers.isEmpty else { return }
        isApplyingBulk = true

        var updatedUsers = workingUsers
        for index in updatedUsers.indices {
            feature.apply(enabled: enabled, to: &updatedUsers[index])
        }
        workingUsers = updatedUsers

        for user in updatedUsers {
            appState.updateUser(user)
        }

        isApplyingBulk = false
    }
}
