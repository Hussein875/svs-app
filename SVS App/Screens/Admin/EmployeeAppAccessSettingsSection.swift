//
//  EmployeeAppAccessSettingsSection.swift
//  SVS App
//

import SwiftUI

struct EmployeeAppAccessSettingsSection: View {
    let showsEmployeeTemplatePicker: Bool

    @Binding var scannerOnlyMode: Bool
    @Binding var documentsAccessEnabled: Bool
    @Binding var myUploadsAccessEnabled: Bool
    @Binding var stargutachterAccessEnabled: Bool
    @Binding var commissionAccessEnabled: Bool
    @Binding var dashboardAccessEnabled: Bool
    @Binding var requestsAccessEnabled: Bool
    @Binding var tasksAccessEnabled: Bool
    @Binding var meetingAccessEnabled: Bool
    @Binding var onCallAccessEnabled: Bool
    @Binding var ordersPlacementAccessEnabled: Bool
    @Binding var accidentSketchAccessEnabled: Bool
    @Binding var allowedLawyerPowerIds: [String]
    @Binding var vermittlungMode: VermittlungMode
    @Binding var selectedTemplate: EmployeeAppAccessTemplate?

    private var lawyerPowerDocuments: [CompanyDocument] {
        CompanyDocumentsCatalog.lawyerPowerItems
    }

    var body: some View {
        if showsEmployeeTemplatePicker {
            Section(
                header: Text("Vorlage"),
                footer: Text("Neue Mitarbeiter starten standardmäßig mit „Alles aus“. Passe die Vorlage an oder stelle die Kacheln einzeln ein.")
            ) {
                Picker("App-Zugang", selection: templateBinding) {
                    Text("Benutzerdefiniert").tag(Optional<EmployeeAppAccessTemplate>.none)
                    ForEach(EmployeeAppAccessTemplate.allCases) { template in
                        Text(template.rawValue).tag(Optional(template))
                    }
                }
            }
        }

        Section(
            header: Text("Kacheln in Mein Bereich"),
            footer: Text("Steuert, welche Bereiche der Nutzer sieht. „Offene Bestellungen“ erscheint zusätzlich für Admins und unter „Zuständig für Bestellungen“ freigeschaltete Personen.")
        ) {
            if showsEmployeeTemplatePicker {
                Toggle("Nur Scanner (ohne Mein Bereich)", isOn: manualBinding($scannerOnlyMode))
            }
            Toggle("Dashboard", isOn: manualBinding($dashboardAccessEnabled))
            Toggle("Prämie", isOn: manualBinding($commissionAccessEnabled))
            Toggle("Dokumente", isOn: manualBinding($documentsAccessEnabled))
            Toggle("Meine Gutachten", isOn: manualBinding($myUploadsAccessEnabled))
            Toggle("Abwesenheiten", isOn: manualBinding($requestsAccessEnabled))
            Toggle("Aufgaben", isOn: manualBinding($tasksAccessEnabled))
            Toggle("Meeting", isOn: manualBinding($meetingAccessEnabled))
            Toggle("Bereitschaft", isOn: manualBinding($onCallAccessEnabled))
            Toggle("Bestellungen aufgeben", isOn: manualBinding($ordersPlacementAccessEnabled))
            Toggle("Schadenhergang", isOn: manualBinding($accidentSketchAccessEnabled))
            Toggle("Stargutachter", isOn: manualBinding($stargutachterAccessEnabled))
        }

        Section(
            header: Text("Scanner – Vermittlung"),
            footer: Text(vermittlungMode.germanDescription)
        ) {
            Picker("Vermittlung", selection: manualBinding($vermittlungMode)) {
                ForEach(VermittlungMode.allCases) { mode in
                    Text(mode.germanTitle).tag(mode)
                }
            }
        }

        Section {
            ForEach(lawyerPowerDocuments) { document in
                Toggle(isOn: lawyerPowerBinding(for: document.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title)
                        if let subtitle = document.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Anwaltsvollmachten")
        } footer: {
            Text("Gilt für Kanzlei-Vollmachten und die Stargutachter-Abtretungserklärung unter Dokumente.")
        }
    }

    private var templateBinding: Binding<EmployeeAppAccessTemplate?> {
        Binding(
            get: { selectedTemplate },
            set: { newValue in
                selectedTemplate = newValue
                guard let template = newValue else { return }
                var draft = currentDraft
                draft.apply(template: template)
                applyDraft(draft)
            }
        )
    }

    private var currentDraft: EmployeeAccessDraft {
        EmployeeAccessDraft(
            scannerOnlyMode: scannerOnlyMode,
            documentsAccessEnabled: documentsAccessEnabled,
            myUploadsAccessEnabled: myUploadsAccessEnabled,
            stargutachterAccessEnabled: stargutachterAccessEnabled,
            commissionAccessEnabled: commissionAccessEnabled,
            dashboardAccessEnabled: dashboardAccessEnabled,
            requestsAccessEnabled: requestsAccessEnabled,
            tasksAccessEnabled: tasksAccessEnabled,
            meetingAccessEnabled: meetingAccessEnabled,
            onCallAccessEnabled: onCallAccessEnabled,
            ordersPlacementAccessEnabled: ordersPlacementAccessEnabled,
            accidentSketchAccessEnabled: accidentSketchAccessEnabled,
            allowedLawyerPowerIds: allowedLawyerPowerIds,
            vermittlungMode: vermittlungMode
        )
    }

    private func applyDraft(_ draft: EmployeeAccessDraft) {
        scannerOnlyMode = draft.scannerOnlyMode
        documentsAccessEnabled = draft.documentsAccessEnabled
        myUploadsAccessEnabled = draft.myUploadsAccessEnabled
        stargutachterAccessEnabled = draft.stargutachterAccessEnabled
        commissionAccessEnabled = draft.commissionAccessEnabled
        dashboardAccessEnabled = draft.dashboardAccessEnabled
        requestsAccessEnabled = draft.requestsAccessEnabled
        tasksAccessEnabled = draft.tasksAccessEnabled
        meetingAccessEnabled = draft.meetingAccessEnabled
        onCallAccessEnabled = draft.onCallAccessEnabled
        ordersPlacementAccessEnabled = draft.ordersPlacementAccessEnabled
        accidentSketchAccessEnabled = draft.accidentSketchAccessEnabled
        allowedLawyerPowerIds = draft.allowedLawyerPowerIds
        vermittlungMode = draft.vermittlungMode
    }

    private func manualBinding(_ value: Binding<VermittlungMode>) -> Binding<VermittlungMode> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                selectedTemplate = nil
                value.wrappedValue = newValue
            }
        )
    }

    private func manualBinding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                selectedTemplate = nil
                value.wrappedValue = newValue
            }
        )
    }

    private func lawyerPowerBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { allowedLawyerPowerIds.contains(id) },
            set: { enabled in
                selectedTemplate = nil
                if enabled {
                    if !allowedLawyerPowerIds.contains(id) {
                        allowedLawyerPowerIds.append(id)
                    }
                } else {
                    allowedLawyerPowerIds.removeAll { $0 == id }
                }
                allowedLawyerPowerIds.sort()
            }
        )
    }
}

private extension EmployeeAccessDraft {
    init(
        scannerOnlyMode: Bool,
        documentsAccessEnabled: Bool,
        myUploadsAccessEnabled: Bool,
        stargutachterAccessEnabled: Bool,
        commissionAccessEnabled: Bool,
        dashboardAccessEnabled: Bool,
        requestsAccessEnabled: Bool,
        tasksAccessEnabled: Bool,
        meetingAccessEnabled: Bool,
        onCallAccessEnabled: Bool,
        ordersPlacementAccessEnabled: Bool,
        accidentSketchAccessEnabled: Bool,
        allowedLawyerPowerIds: [String],
        vermittlungMode: VermittlungMode
    ) {
        self.scannerOnlyMode = scannerOnlyMode
        self.documentsAccessEnabled = documentsAccessEnabled
        self.myUploadsAccessEnabled = myUploadsAccessEnabled
        self.stargutachterAccessEnabled = stargutachterAccessEnabled
        self.commissionAccessEnabled = commissionAccessEnabled
        self.dashboardAccessEnabled = dashboardAccessEnabled
        self.requestsAccessEnabled = requestsAccessEnabled
        self.tasksAccessEnabled = tasksAccessEnabled
        self.meetingAccessEnabled = meetingAccessEnabled
        self.onCallAccessEnabled = onCallAccessEnabled
        self.ordersPlacementAccessEnabled = ordersPlacementAccessEnabled
        self.accidentSketchAccessEnabled = accidentSketchAccessEnabled
        self.allowedLawyerPowerIds = allowedLawyerPowerIds
        self.vermittlungMode = vermittlungMode
    }
}

struct EmployeeAppAccessChipRow: View {
    let chips: [String]

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(.tertiarySystemBackground))
                            )
                    }
                }
            }
        }
    }
}
