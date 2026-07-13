//
//  AbtretungserklaerungFunnelView.swift
//  SVS App
//

import SwiftUI
import UIKit

struct AbtretungserklaerungFunnelView: View {
    let sourcePDFURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: AbtretungserklaerungFunnelStep = .vehicleRegistrationScan
    @State private var form = AbtretungserklaerungForm()
    @State private var scanName = ""
    @State private var scanNameManuallyEdited = false
    @State private var currentSequence: ScannerSequenceInfo?
    @State private var reservation: ScannerReservationResult?
    @State private var filledPDFURL: URL?
    @State private var signedPDFURL: URL?
    @State private var signaturePlacement = NormalizedSignaturePlacement(
        from: AbtretungserklaerungPlacementStore.placement(for: .signatureImage)
    )

    @State private var isLoading = false
    @State private var isRendering = false
    @State private var isSigning = false
    @State private var showVehicleScanner = false
    @State private var signatureImage: UIImage?
    @State private var errorMessage: String?
    @State private var ocrNotice: String?
    @State private var isAdvancing = false
    @State private var showCancelConfirmation = false
    @State private var isUploadingToDrive = false
    @State private var driveUploadCompleted = false
    @State private var driveUploadNotice: String?
    @State private var didRestoreDraft = false
    @State private var isRecognizingVehicle = false
    @State private var isKeyboardVisible = false
    @State private var priorDamageResult: UltraExpertPriorDamageResult?
    @State private var priorDamageNotice: String?
    @State private var isCheckingPriorDamage = false
    @State private var priorDamageCheckVin: String?

    @FocusState private var focusedField: FunnelField?

    private enum FunnelField: Hashable {
        case scanName
        case clientLastName
        case clientFirstName
        case licensePlate
        case streetAndNumber
        case postalCodeAndCity
        case phoneOrEmail
        case damageLocation
        case opponentLicensePlate
        case opponentName
        case insuranceCompany
        case claimOrPolicyNumber
    }

    private var stepIndex: Int { step.rawValue }
    private var totalSteps: Int { AbtretungserklaerungFunnelStep.allCases.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactProgressHeader
                stepNavigationBar
                if !isKeyboardVisible {
                    stepOptionalHint
                }

                if usesStandaloneStepLayout {
                    standaloneStepContent
                } else {
                    Form {
                        formStepContent
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if let current = focusedField, !isLastFormField(current) {
                        Button("Weiter") {
                            focusNext(after: current)
                        }
                        .fontWeight(.semibold)
                    }
                    Button {
                        dismissKeyboard()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Tastatur ausblenden")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .fullScreenCover(isPresented: $showVehicleScanner) {
                DocumentScanner(
                    onFinish: { images in
                        showVehicleScanner = false
                        guard let first = images.first else { return }
                        _Concurrency.Task {
                            await runOCR(on: first)
                        }
                    },
                    onCancel: { showVehicleScanner = false }
                )
                .ignoresSafeArea()
            }
            .alert("Fehler", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Vorgang abbrechen?", isPresented: $showCancelConfirmation) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Abbrechen", role: .destructive) {
                    _Concurrency.Task {
                        await cancelReservationIfNeeded()
                        clearSavedDraft()
                        dismiss()
                    }
                }
            } message: {
                Text("Alle eingegebenen Daten gehen verloren. Eine reservierte Gutachten-Nr. wird freigegeben.")
            }
            .onAppear {
                restoreDraftIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    saveDraft()
                }
            }
            .onChange(of: step) { _, newStep in
                dismissKeyboard()
                saveDraft()
                if newStep == .clientIdentity {
                    _Concurrency.Task { await runPriorDamageCheckIfNeeded() }
                }
            }
            .onChange(of: form) { _, _ in
                saveDraft()
            }
            .onChange(of: scanName) { _, _ in
                saveDraft()
            }
            .onChange(of: reservation) { _, _ in
                saveDraft()
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var usesStandaloneStepLayout: Bool {
        switch step {
        case .preview, .signature:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var formStepContent: some View {
        switch step {
        case .vehicleRegistrationScan:
            vehicleScanStep
        case .clientIdentity:
            clientIdentityStep
        case .clientAddress:
            clientAddressStep
        case .accidentDetails:
            accidentDetailsStep
        case .vatChoice:
            vatStep
        case .gutachtenNumber:
            gutachtenStep
        case .preview, .signature:
            EmptyView()
        }
    }

    @ViewBuilder
    private var standaloneStepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch step {
                case .preview:
                    previewStep
                case .signature:
                    signatureStep
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var compactProgressHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(stepIndex + 1)/\(totalSteps)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                ProgressView(value: Double(stepIndex + 1), total: Double(totalSteps))
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var gutachtenStep: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Aktuelle Nummer wird geladen …")
                }
            } else if let reservation {
                LabeledContent("Reserviert") {
                    Text(reservation.displayNumber)
                        .font(.headline.monospacedDigit())
                }
                Text("Ordner: \(reservation.scanName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let currentSequence {
                LabeledContent("Nächste Nummer") {
                    Text(currentSequence.displayNumber)
                        .font(.headline.monospacedDigit())
                }
            }

            if reservation == nil {
                configureFieldFocus(
                    TextField("Ordnername", text: $scanName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: scanName) { _, _ in
                            scanNameManuallyEdited = true
                        },
                    field: .scanName
                )
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ordnername aus Nachname vorgeschlagen. Mit „Reservieren & weiter“ fortfahren.")

                if reservation == nil {
                    Button("Ausnahme: ohne Gutachten-Nr. fortfahren") {
                        _Concurrency.Task { await goForwardWithoutGutachtenNumber() }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
                    .disabled(isAdvancing || isLoading || isSigning)
                }
            }
        }
        .onAppear {
            updateSuggestedScanNameIfNeeded()
            _Concurrency.Task { await loadCurrentSequenceIfNeeded() }
        }
    }

    private var vehicleScanStep: some View {
        Section {
            Button {
                showVehicleScanner = true
            } label: {
                Label("Fahrzeugschein fotografieren", systemImage: "camera.viewfinder")
            }
            .disabled(isRecognizingVehicle)

            if isRecognizingVehicle {
                VehicleRegistrationRecognitionLoadingView()
            } else if let ocrNotice {
                Text(ocrNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Optional")
        } footer: {
            Text("Du kannst diesen Schritt überspringen – tippe einfach auf Weiter. Ideal: Schein flach, gut beleuchtet, linke Spalte mit Kennzeichen und Namen vollständig sichtbar.")
        }
    }

    private var clientIdentityStep: some View {
        Group {
            Section {
                configureFieldFocus(
                    TextField("Nachname", text: $form.clientLastName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: form.clientLastName) { _, _ in
                            updateSuggestedScanNameIfNeeded()
                        },
                    field: .clientLastName
                )
                configureFieldFocus(
                    TextField("Vorname", text: $form.clientFirstName)
                        .textInputAutocapitalization(.words),
                    field: .clientFirstName
                )
                configureFieldFocus(
                    TextField("Amtliches Kennzeichen", text: $form.licensePlate)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: form.licensePlate) { _, newValue in
                            applyLicensePlateFormatting(&form.licensePlate, newValue: newValue)
                        },
                    field: .licensePlate
                )

                if !form.vin.isEmpty {
                    LabeledContent("FIN") {
                        Text(form.vin)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let firstRegistrationDate = form.firstRegistrationDate {
                    LabeledContent("Erstzulassung") {
                        Text(VehicleIdentificationStore.formatFirstRegistrationDate(
                            firstRegistrationDate
                        ))
                        .textSelection(.enabled)
                    }
                }
            } footer: {
                if form.vin.isEmpty && form.firstRegistrationDate == nil {
                    Text("Nach dem Fahrzeugschein-Scan sind diese Felder oft schon ausgefüllt.")
                } else {
                    Text("FIN und Erstzulassung werden lokal gespeichert und erscheinen nicht auf der Abtretungserklärung.")
                }
            }

            priorDamageCheckSection
        }
        .onAppear {
            _Concurrency.Task { await runPriorDamageCheckIfNeeded() }
        }
    }

    @ViewBuilder
    private var priorDamageCheckSection: some View {
        if !form.vin.isEmpty {
            Section("Vorschaden-Check") {
                if isCheckingPriorDamage {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Vorschäden werden geprüft …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let result = priorDamageResult {
                    if result.hasPriorReports {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                Text("Achtung: Vorschäden vorhanden")
                                    .font(.subheadline.weight(.semibold))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gutachten:")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                ForEach(priorDamageRows(from: result)) { row in
                                    if let url = row.url {
                                        PriorDamageGutachtenLinkRow(
                                            gutachtenNumber: row.gutachtenNumber,
                                            url: url
                                        )
                                    } else {
                                        Text(row.gutachtenNumber)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    } else {
                        Label {
                            Text("Kein Treffer für Vorschäden")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .foregroundStyle(.secondary)
                    }
                } else if let priorDamageNotice {
                    Text(priorDamageNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct PriorDamageRow: Identifiable {
        let id: String
        let gutachtenNumber: String
        let url: URL?
    }

    private func priorDamageRows(
        from result: UltraExpertPriorDamageResult
    ) -> [PriorDamageRow] {
        let matches: [UltraExpertPriorDamageMatch] = result.matches.isEmpty
            ? result.gutachtenNumbers.map {
                UltraExpertPriorDamageMatch(
                    gutachtenNumber: $0,
                    dossierId: nil,
                    dossierUrl: nil
                )
            }
            : result.matches

        return matches.enumerated().map { index, match in
            let trimmedUrl = match.dossierUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = trimmedUrl.isEmpty ? nil : URL(string: trimmedUrl)
            return PriorDamageRow(
                id: "\(index)-\(match.gutachtenNumber)",
                gutachtenNumber: match.gutachtenNumber,
                url: url
            )
        }
    }

    @ViewBuilder
    private var clientAddressStep: some View {
        Section("Adresse") {
            configureFieldFocus(
                TextField("Straße und Hausnummer", text: $form.streetAndNumber),
                field: .streetAndNumber
            )
            configureFieldFocus(
                TextField("PLZ / Ort", text: $form.postalCodeAndCity),
                field: .postalCodeAndCity
            )
        }

        Section("Optional") {
            configureFieldFocus(
                TextField("Telefon / E-Mail", text: $form.phoneOrEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never),
                field: .phoneOrEmail
            )
        }
    }

    @ViewBuilder
    private var accidentDetailsStep: some View {
        Section {
            configureFieldFocus(
                TextField("Schadenort", text: $form.damageLocation),
                field: .damageLocation
            )
            DatePicker(
                "Schadentag",
                selection: $form.damageDate,
                displayedComponents: .date
            )
            configureFieldFocus(
                TextField("Kennzeichen des Unfallgegners", text: $form.opponentLicensePlate)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: form.opponentLicensePlate) { _, newValue in
                        applyLicensePlateFormatting(&form.opponentLicensePlate, newValue: newValue)
                    },
                field: .opponentLicensePlate
            )
        } footer: {
            Text("Die Felder in der nächsten Sektion sind optional.")
        }

        Section("Optional – kann leer bleiben") {
            configureFieldFocus(
                TextField("Unfallgegner", text: $form.opponentName),
                field: .opponentName
            )
            configureFieldFocus(
                TextField("Versicherung", text: $form.insuranceCompany),
                field: .insuranceCompany
            )
            configureFieldFocus(
                TextField("Schaden-Nr. / Versicherungs-Nr.", text: $form.claimOrPolicyNumber),
                field: .claimOrPolicyNumber
            )
        }
        .id("ae-accident-optional-section")
        .onAppear {
            form.damageDate = Calendar.current.startOfDay(for: form.damageDate)
        }
    }

    private var vatStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vorsteuerabzugsberechtigt?")
                    .font(.headline)

                HStack(spacing: 12) {
                    vatChoiceButton(
                        title: "Ja",
                        isSelected: form.isVatDeductible == true
                    ) {
                        form.isVatDeductible = true
                    }

                    vatChoiceButton(
                        title: "Nein",
                        isSelected: form.isVatDeductible == false
                    ) {
                        form.isVatDeductible = false
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func vatChoiceButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isSelected {
            Button(action: action) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var previewStep: some View {
        Group {
            if isRendering {
                HStack {
                    ProgressView()
                    Text("PDF wird erstellt …")
                }
            } else if let filledPDFURL {
                PDFPreview(url: filledPDFURL)
                    .frame(minHeight: 420)
            } else {
                Text("Vorschau wird vorbereitet …")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            _Concurrency.Task { await renderPreviewIfNeeded() }
        }
    }

    private var signatureStep: some View {
        Group {
            if let signedPDFURL {
                PDFPreview(url: signedPDFURL)
                    .frame(minHeight: 320)

                if let driveUploadNotice {
                    Text(driveUploadNotice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ShareLink(item: signedPDFURL) {
                    Label("PDF teilen", systemImage: "square.and.arrow.up")
                }
            } else {
                SignaturePadView(
                    signatureImage: $signatureImage,
                    canvasHeight: 220,
                    locksParentScrolling: true,
                    prompt: "Kundenunterschrift",
                    emptyLabel: "Noch keine Unterschrift",
                    capturedLabel: "Unterschrift erfasst"
                )
            }
        }
        .onAppear {
            _Concurrency.Task { await renderPreviewIfNeeded() }
        }
        .overlay {
            if isSigning {
                ProgressView("Wird gespeichert …")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private var stepOptionalHint: some View {
        switch step {
        case .accidentDetails:
            optionalHintLabel(
                "Unfallgegner, Versicherung und Schaden-Nr. sind optional – einfach Weiter tippen, wenn du sie überspringen willst."
            )
        case .clientAddress:
            optionalHintLabel(
                "Telefon / E-Mail ist optional – weiter unten im Formular."
            )
        default:
            EmptyView()
        }
    }

    private func optionalHintLabel(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private var stepNavigationBar: some View {
        HStack(spacing: 12) {
            if step != .vehicleRegistrationScan {
                Button("Zurück") {
                    goBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 8)

            Button {
                _Concurrency.Task { await goForward() }
            } label: {
                HStack(spacing: 8) {
                    if isRecognizingVehicle, step == .vehicleRegistrationScan {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryBottomActionTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !canContinue
                    || isAdvancing
                    || isSigning
                    || isUploadingToDrive
                    || isRecognizingVehicle
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var primaryBottomActionTitle: String {
        switch step {
        case .signature where signedPDFURL != nil:
            if canUploadSignedPDFToDrive && !driveUploadCompleted {
                return isUploadingToDrive ? "Wird hochgeladen …" : "Dokument in Drive hochladen"
            }
            return "Fertig"
        case .signature:
            return "Unterschrift übernehmen"
        case .vehicleRegistrationScan:
            return isRecognizingVehicle ? "Wird erkannt …" : "Weiter"
        case .gutachtenNumber:
            return reservation == nil ? "Reservieren & weiter" : "Weiter mit GA-Nr."
        default:
            return "Weiter"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .vehicleRegistrationScan:
            return !isRecognizingVehicle
        case .clientIdentity:
            return !form.clientLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !form.licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .clientAddress:
            return !form.streetAndNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !form.postalCodeAndCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .accidentDetails:
            return !form.damageLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vatChoice:
            return form.isVatDeductible != nil
        case .preview:
            return filledPDFURL != nil && !isRendering
        case .gutachtenNumber:
            return !scanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isLoading
        case .signature:
            return signedPDFURL != nil || signatureImage != nil
        }
    }

    private var canUploadSignedPDFToDrive: Bool {
        reservation != nil && form.gutachtenReservationId != nil
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Navigation

    private func goBack() {
        dismissKeyboard()
        guard let previous = AbtretungserklaerungFunnelStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var orderedFormFields: [FunnelField] {
        switch step {
        case .gutachtenNumber:
            return reservation == nil ? [.scanName] : []
        case .clientIdentity:
            return [.clientLastName, .clientFirstName, .licensePlate]
        case .clientAddress:
            return [.streetAndNumber, .postalCodeAndCity, .phoneOrEmail]
        case .accidentDetails:
            return [
                .damageLocation,
                .opponentLicensePlate,
                .opponentName,
                .insuranceCompany,
                .claimOrPolicyNumber,
            ]
        default:
            return []
        }
    }

    private func isLastFormField(_ field: FunnelField) -> Bool {
        orderedFormFields.last == field
    }

    private func focusNext(after field: FunnelField) {
        guard let index = orderedFormFields.firstIndex(of: field),
              index + 1 < orderedFormFields.count
        else {
            dismissKeyboard()
            return
        }
        focusedField = orderedFormFields[index + 1]
    }

    private func configureFieldFocus<Content: View>(
        _ content: Content,
        field: FunnelField
    ) -> some View {
        content
            .focused($focusedField, equals: field)
            .submitLabel(isLastFormField(field) ? .done : .next)
            .onSubmit {
                if isLastFormField(field) {
                    dismissKeyboard()
                } else {
                    focusNext(after: field)
                }
            }
    }

    private func goForward() async {
        let shouldAdvance = await MainActor.run { () -> Bool in
            guard !isAdvancing else { return false }
            isAdvancing = true
            return true
        }
        guard shouldAdvance else { return }
        defer { _Concurrency.Task { @MainActor in isAdvancing = false } }

        if await MainActor.run(body: { step == .vehicleRegistrationScan && isRecognizingVehicle }) {
            return
        }

        await MainActor.run {
            dismissKeyboard()
        }

        if step == .signature {
            if signedPDFURL != nil {
                if canUploadSignedPDFToDrive && !driveUploadCompleted {
                    await uploadSignedPDFToDrive()
                    return
                }
                clearSavedDraft()
                dismiss()
                return
            }
            if signatureImage != nil {
                await applySignatureFromPad()
            }
            return
        }

        if step == .gutachtenNumber {
            await goForwardWithGutachtenReservation()
            return
        }

        guard let next = AbtretungserklaerungFunnelStep(rawValue: step.rawValue + 1) else { return }

        if step == .vatChoice {
            await renderPreviewIfNeeded()
            let hasPDF = await MainActor.run { filledPDFURL != nil }
            guard hasPDF else { return }
        }

        step = next
    }

    private func goForwardWithGutachtenReservation() async {
        let trimmedScanName = await MainActor.run {
            scanName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmedScanName.isEmpty else {
            await MainActor.run {
                errorMessage = "Bitte einen Ordnernamen eingeben."
            }
            return
        }

        let alreadyReserved = await MainActor.run { reservation != nil }
        if !alreadyReserved {
            await reserveNumber()
        }

        let reserved = await MainActor.run { reservation }
        guard let reserved else { return }

        await MainActor.run {
            form.gutachtenNumber = reserved.displayNumber
            form.gutachtenReservationId = reserved.reservationId
            filledPDFURL = nil
            signedPDFURL = nil
        }

        await renderPreviewIfNeeded(force: true)
        let hasPDF = await MainActor.run { filledPDFURL != nil }
        guard hasPDF else { return }

        await MainActor.run {
            step = .signature
        }
    }

    private func goForwardWithoutGutachtenNumber() async {
        let shouldAdvance = await MainActor.run { () -> Bool in
            guard !isAdvancing else { return false }
            isAdvancing = true
            return true
        }
        guard shouldAdvance else { return }
        defer { _Concurrency.Task { @MainActor in isAdvancing = false } }

        if await MainActor.run(body: { reservation != nil }) {
            await releaseReservation()
        }

        await MainActor.run {
            form.gutachtenNumber = ""
            form.gutachtenReservationId = nil
            filledPDFURL = nil
            signedPDFURL = nil
        }

        await renderPreviewIfNeeded(force: true)
        let hasPDF = await MainActor.run { filledPDFURL != nil }
        guard hasPDF else { return }

        await MainActor.run {
            step = .signature
        }
    }

    // MARK: - Scanner

    private func loadCurrentSequenceIfNeeded() async {
        guard currentSequence == nil else { return }
        await loadCurrentSequence()
    }

    private func updateSuggestedScanNameIfNeeded() {
        guard !scanNameManuallyEdited else { return }
        let suggested = AbtretungserklaerungScanNameBuilder.suggestedFolderName(
            clientLastName: form.clientLastName
        )
        guard !suggested.isEmpty else { return }
        scanName = suggested
    }

    private func loadCurrentSequence() async {
        await MainActor.run { isLoading = true }
        defer { _Concurrency.Task { @MainActor in isLoading = false } }

        do {
            let sequence = try await ScannerReservationService.fetchCurrentSequence()
            await MainActor.run {
                currentSequence = sequence
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reserveNumber() async {
        await MainActor.run { isLoading = true }
        defer { _Concurrency.Task { @MainActor in isLoading = false } }

        do {
            let result = try await ScannerReservationService.reserve(scanName: scanName)
            await MainActor.run {
                reservation = result
                form.gutachtenNumber = result.displayNumber
                form.gutachtenReservationId = result.reservationId
                currentSequence = ScannerSequenceInfo(
                    nextNumber: result.number + 1,
                    year2: result.year2
                )
            }
            ScannerWidgetStore.publish(number: result.number, year2: result.year2, isReserved: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func releaseReservation() async {
        guard let reservation else { return }
        await MainActor.run { isLoading = true }
        defer { _Concurrency.Task { @MainActor in isLoading = false } }

        do {
            try await ScannerReservationService.cancel(reservationId: reservation.reservationId)
            await MainActor.run {
                self.reservation = nil
                form.gutachtenReservationId = nil
            }
            ScannerWidgetStore.endReservation()
            await loadCurrentSequence()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelReservationIfNeeded() async {
        guard let reservationId = form.gutachtenReservationId else { return }
        try? await ScannerReservationService.cancel(reservationId: reservationId)
        ScannerWidgetStore.endReservation()
    }

    // MARK: - OCR

    private func runOCR(on image: UIImage) async {
        await MainActor.run {
            isRecognizingVehicle = true
            ocrNotice = nil
        }

        do {
            let result = try await VehicleRegistrationDocuPipeService.recognize(from: image)
            await MainActor.run {
                result.apply(to: &form)
                updateSuggestedScanNameIfNeeded()
                ocrNotice = "Daten per DocuPipe übernommen – bitte in den nächsten Schritten prüfen."
                isRecognizingVehicle = false
            }
            await runPriorDamageCheckIfNeeded()
            return
        } catch let docuPipeError as VehicleRegistrationDocuPipeError {
            let fallbackReason = docuPipeError.localizedDescription
            guard docuPipeError.allowsVisionFallback else {
                await MainActor.run {
                    isRecognizingVehicle = false
                    errorMessage = fallbackReason
                }
                return
            }

            do {
                let result = try await VehicleRegistrationOCRService.recognize(from: image)
                await MainActor.run {
                    result.apply(to: &form)
                    updateSuggestedScanNameIfNeeded()
                    ocrNotice = "DocuPipe: \(fallbackReason) – Daten lokal erkannt."
                    isRecognizingVehicle = false
                }
                await runPriorDamageCheckIfNeeded()
            } catch {
                await MainActor.run {
                    isRecognizingVehicle = false
                    errorMessage = error.localizedDescription
                }
            }
            return
        } catch {
            let fallbackReason = error.localizedDescription
            do {
                let result = try await VehicleRegistrationOCRService.recognize(from: image)
                await MainActor.run {
                    result.apply(to: &form)
                    updateSuggestedScanNameIfNeeded()
                    ocrNotice = "DocuPipe: \(fallbackReason) – Daten lokal erkannt."
                    isRecognizingVehicle = false
                }
                await runPriorDamageCheckIfNeeded()
            } catch {
                await MainActor.run {
                    isRecognizingVehicle = false
                    errorMessage = error.localizedDescription
                }
            }
            return
        }
    }

    // MARK: - PDF

    private func renderPreviewIfNeeded(force: Bool = false) async {
        let needsRender = await MainActor.run { force || filledPDFURL == nil }
        guard needsRender else { return }

        await MainActor.run {
            isRendering = true
            form.signingDate = Date()
            normalizeLicensePlatesInForm()
        }

        do {
            let url = try AbtretungserklaerungPDFRenderer.renderFilledPDF(
                sourceURL: sourcePDFURL,
                form: form
            )
            await MainActor.run {
                filledPDFURL = url
                isRendering = false
                saveDraft()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isRendering = false
            }
        }
    }

    private func applySignatureFromPad() async {
        guard let filledPDFURL else { return }
        guard let signatureImage else {
            await MainActor.run {
                errorMessage = "Bitte zuerst unterschreiben."
            }
            return
        }
        guard let document = CompanyDocumentsCatalog.items.first(where: { $0.id == "ae" }) else { return }
        let placement = await MainActor.run {
            signaturePlacement.width > 0
                ? signaturePlacement.pdfPlacement(pageIndex: 0)
                : AbtretungserklaerungPlacementStore.placement(for: .signatureImage)
        }

        await MainActor.run { isSigning = true }
        defer { _Concurrency.Task { @MainActor in isSigning = false } }

        do {
            let signedURL = try PDFSignatureService.signedPDFURL(
                sourceURL: filledPDFURL,
                signature: signatureImage,
                signaturePlacement: placement,
                textOverlays: [],
                inkOverlays: [],
                outputBaseName: document.resourceName
            )

            _ = try LocalSignedDocumentArchive.archive(
                pdfAt: signedURL,
                document: document,
                label: form.clientName
            )

            await MainActor.run {
                signedPDFURL = signedURL
                self.signatureImage = nil
                saveDraft()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyLicensePlateFormatting(_ field: inout String, newValue: String) {
        let formatted = GermanLicensePlateFormatter.format(newValue)
        guard formatted != newValue else { return }
        field = formatted
    }

    private func normalizeLicensePlatesInForm() {
        form.licensePlate = GermanLicensePlateFormatter.format(form.licensePlate)
        form.opponentLicensePlate = GermanLicensePlateFormatter.format(form.opponentLicensePlate)
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true

        guard let draft = AbtretungserklaerungFunnelDraftStore.load(),
              let restoredStep = AbtretungserklaerungFunnelStep(rawValue: draft.stepRawValue) else {
            return
        }

        step = restoredStep
        form = draft.form
        scanName = draft.scanName
        scanNameManuallyEdited = draft.scanNameManuallyEdited
        reservation = draft.reservation
        ocrNotice = draft.ocrNotice
        driveUploadCompleted = draft.driveUploadCompleted

        if let path = draft.filledPDFPath,
           FileManager.default.fileExists(atPath: path) {
            filledPDFURL = URL(fileURLWithPath: path)
        }
        if let path = draft.signedPDFPath,
           FileManager.default.fileExists(atPath: path) {
            signedPDFURL = URL(fileURLWithPath: path)
        }

        if step.rawValue >= AbtretungserklaerungFunnelStep.preview.rawValue {
            _Concurrency.Task { await renderPreviewIfNeeded(force: filledPDFURL == nil) }
        }
        if step == .gutachtenNumber {
            _Concurrency.Task { await loadCurrentSequenceIfNeeded() }
        }
        if !form.vin.isEmpty {
            _Concurrency.Task { await runPriorDamageCheckIfNeeded() }
        }
    }

    private func runPriorDamageCheckIfNeeded() async {
        let vin = await MainActor.run {
            VehicleIdentificationStore.normalizeVin(form.vin)
        }
        guard vin.count >= 11 else { return }

        let shouldSkip = await MainActor.run {
            priorDamageCheckVin == vin &&
            (priorDamageResult != nil || isCheckingPriorDamage)
        }
        if shouldSkip { return }

        await MainActor.run {
            isCheckingPriorDamage = true
            priorDamageNotice = nil
            priorDamageResult = nil
        }

        do {
            let result = try await UltraExpertPriorDamageService.check(vin: vin)
            await MainActor.run {
                priorDamageCheckVin = vin
                priorDamageResult = result
                isCheckingPriorDamage = false
                priorDamageNotice = nil
            }
        } catch let error as UltraExpertPriorDamageError {
            await MainActor.run {
                priorDamageCheckVin = vin
                isCheckingPriorDamage = false
                if case .notConfigured = error {
                    priorDamageNotice = nil
                } else {
                    priorDamageNotice = error.localizedDescription
                }
            }
        } catch {
            await MainActor.run {
                priorDamageCheckVin = vin
                isCheckingPriorDamage = false
                priorDamageNotice = error.localizedDescription
            }
        }
    }

    private func saveDraft() {
        guard didRestoreDraft else { return }

        let draft = AbtretungserklaerungFunnelDraft(
            stepRawValue: step.rawValue,
            form: form,
            scanName: scanName,
            scanNameManuallyEdited: scanNameManuallyEdited,
            reservation: reservation,
            ocrNotice: ocrNotice,
            driveUploadCompleted: driveUploadCompleted,
            filledPDFPath: filledPDFURL?.path,
            signedPDFPath: signedPDFURL?.path,
            savedAt: Date()
        )
        AbtretungserklaerungFunnelDraftStore.save(draft)
    }

    private func clearSavedDraft() {
        AbtretungserklaerungFunnelDraftStore.clear()
    }

    /// Nach AE-Upload wie im Scanner: Reservierung in Widget/Anzeige beenden, nächste Nr. laden.
    private func syncScannerAvailabilityAfterAE() async {
        ScannerWidgetStore.endReservation()
        do {
            let sequence = try await ScannerReservationService.fetchCurrentSequence()
            await MainActor.run {
                currentSequence = sequence
            }
            ScannerWidgetStore.publishAvailable(
                number: sequence.nextNumber,
                year2: sequence.year2
            )
        } catch {
            // Firestore-Listener im Scanner-Tab holt die Nummer nach; kein Blocker.
        }
    }

    private func uploadSignedPDFToDrive() async {
        guard let signedPDFURL else { return }
        guard let reservation, let reservationId = form.gutachtenReservationId else {
            await MainActor.run {
                errorMessage = "Keine reservierte Gutachten-Nr. – Drive-Upload nicht möglich."
            }
            return
        }

        await MainActor.run { isUploadingToDrive = true }
        defer { _Concurrency.Task { @MainActor in isUploadingToDrive = false } }

        let fileName = "\(reservation.displayNumber.replacingOccurrences(of: "/", with: "-")) AE.pdf"

        do {
            let result = try await ScannerDriveUploadService.uploadPDF(
                localURL: signedPDFURL,
                fileName: fileName,
                reservationId: reservationId,
                useReservationFolder: true
            )

            await MainActor.run {
                driveUploadCompleted = true
                if let folderURL = result.driveFolderURL {
                    driveUploadNotice = "„\(fileName)“ wurde in den Gutachten-Ordner hochgeladen."
                    UIApplication.shared.open(folderURL)
                } else {
                    driveUploadNotice = "„\(fileName)“ wurde in Google Drive abgelegt."
                }
                saveDraft()
            }
            await syncScannerAvailabilityAfterAE()
        } catch {
            await MainActor.run {
                errorMessage = "Drive-Upload fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }
}

private struct PriorDamageGutachtenLinkRow: View {
    let gutachtenNumber: String
    let url: URL

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Text(gutachtenNumber)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.tint)
    }
}

private struct VehicleRegistrationRecognitionLoadingView: View {
    @State private var pulse = false
    @State private var phaseIndex = 0

    private let phases = [
        "Fahrzeugschein wird hochgeladen …",
        "DocuPipe erkennt die Felder …",
        "Kennzeichen und Halter werden übernommen …",
    ]

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(pulse ? 0.18 : 0.10))
                    .frame(width: 76, height: 76)
                    .scaleEffect(pulse ? 1.06 : 0.94)

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
            }

            ProgressView()
                .controlSize(.regular)

            Text(phases[phaseIndex])
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.35), value: phaseIndex)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .task {
            guard phases.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                phaseIndex = (phaseIndex + 1) % phases.count
            }
        }
    }
}
