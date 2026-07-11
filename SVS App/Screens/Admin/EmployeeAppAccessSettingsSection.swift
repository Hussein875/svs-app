//
//  EmployeeAppAccessSettingsSection.swift
//  SVS App
//

import SwiftUI

struct EmployeeAppAccessSettingsSection: View {
    @Binding var scannerOnlyMode: Bool
    @Binding var documentsAccessEnabled: Bool
    @Binding var myUploadsAccessEnabled: Bool
    @Binding var stargutachterAccessEnabled: Bool
    @Binding var commissionAccessEnabled: Bool
    @Binding var allowedLawyerPowerIds: [String]
    @Binding var selectedTemplate: EmployeeAppAccessTemplate?

    private var lawyerPowerDocuments: [CompanyDocument] {
        CompanyDocumentsCatalog.lawyerPowerItems
    }

    var body: some View {
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

        Section(
            header: Text("Bereiche"),
            footer: Text("„Nur Scanner“ blendet Mein Bereich aus. Dokumente umfasst AE/BD und freigeschaltete Vollmachten.")
        ) {
            Toggle("Nur Scanner (ohne Mein Bereich)", isOn: manualBinding($scannerOnlyMode))
            Toggle("Dokumente anzeigen", isOn: manualBinding($documentsAccessEnabled))
            Toggle("Meine Gutachten anzeigen", isOn: manualBinding($myUploadsAccessEnabled))
            Toggle("Stargutachter anzeigen", isOn: manualBinding($stargutachterAccessEnabled))
            Toggle("Prämie anzeigen", isOn: manualBinding($commissionAccessEnabled))
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
                var draft = EmployeeAccessDraft(
                    scannerOnlyMode: scannerOnlyMode,
                    documentsAccessEnabled: documentsAccessEnabled,
                    myUploadsAccessEnabled: myUploadsAccessEnabled,
                    stargutachterAccessEnabled: stargutachterAccessEnabled,
                    commissionAccessEnabled: commissionAccessEnabled,
                    allowedLawyerPowerIds: allowedLawyerPowerIds
                )
                draft.apply(template: template)
                scannerOnlyMode = draft.scannerOnlyMode
                documentsAccessEnabled = draft.documentsAccessEnabled
                myUploadsAccessEnabled = draft.myUploadsAccessEnabled
                stargutachterAccessEnabled = draft.stargutachterAccessEnabled
                commissionAccessEnabled = draft.commissionAccessEnabled
                allowedLawyerPowerIds = draft.allowedLawyerPowerIds
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
        allowedLawyerPowerIds: [String]
    ) {
        self.scannerOnlyMode = scannerOnlyMode
        self.documentsAccessEnabled = documentsAccessEnabled
        self.myUploadsAccessEnabled = myUploadsAccessEnabled
        self.stargutachterAccessEnabled = stargutachterAccessEnabled
        self.commissionAccessEnabled = commissionAccessEnabled
        self.allowedLawyerPowerIds = allowedLawyerPowerIds
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
