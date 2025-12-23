import SwiftUI

/// Mitarbeiter-Formular: Provisionen an den Admin melden (als To-do/Task beim Admin).
struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState

    private enum PayoutMethod: String, CaseIterable, Identifiable {
        case paypal = "PayPal"
        case iban = "IBAN"
        var id: String { rawValue }
    }

    // MARK: - Input

    @State private var customerName: String = ""
    @State private var customerAddress: String = ""
    @State private var amountText: String = ""

    @State private var payoutMethod: PayoutMethod = .paypal
    @State private var paypalAddress: String = ""
    @State private var iban: String = ""


    // Inline Error (nur sichtbar, wenn es einen Fehler gibt)
    @State private var showInlineError: Bool = false
    @State private var inlineErrorMessage: String = ""

    @FocusState private var focusedField: Field?
    enum Field {
        case customerName, customerAddress, amount, paypal, iban
    }

    // MARK: - Derived

    private var adminUser: User? {
        appState.users.first(where: { $0.role == .admin })
    }

    private var parsedAmount: Decimal? {
        let trimmed = amountText
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    private var isValid: Bool {
        guard !customerName.trimmed.isEmpty else { return false }
        guard !customerAddress.trimmed.isEmpty else { return false }
        guard let a = parsedAmount, a > 0 else { return false }

        switch payoutMethod {
        case .paypal:
            return !paypalAddress.trimmed.isEmpty
        case .iban:
            return normalizedIBAN(iban).count >= 15
        }
    }

    private var payoutHint: String {
        switch payoutMethod {
        case .paypal:
            return "E-Mail-Adresse für PayPal-Auszahlung"
        case .iban:
            return "IBAN ohne Leerzeichen (z. B. DE...)"
        }
    }

    // MARK: - UI

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    header

                    if showInlineError {
                        InlineErrorBanner(message: inlineErrorMessage)
                            .padding(.horizontal, 18)
                            .transition(.opacity)
                    }

                    SectionCard(title: "Vermittlerdaten", systemImage: "person.text.rectangle") {
                        VStack(spacing: 10) {
                            LabeledTextField(
                                title: "Name",
                                placeholder: "Vorname Nachname",
                                text: $customerName,
                                field: .customerName,
                                focusedField: $focusedField
                            )
                            Divider().opacity(0.18)
                            LabeledTextField(
                                title: "Adresse",
                                placeholder: "Straße, PLZ Ort",
                                text: $customerAddress,
                                axis: .vertical,
                                lineLimit: 2...4,
                                field: .customerAddress,
                                focusedField: $focusedField
                            )
                        }
                    }
                    .padding(.horizontal, 18)

                    SectionCard(title: "Provision", systemImage: "eurosign") {
                        VStack(spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Betrag")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("z. B. 50,00", text: $amountText)
                                        .keyboardType(.decimalPad)
                                        .focused($focusedField, equals: .amount)
                                        .onChange(of: amountText) { _, newValue in
                                            amountText = sanitizeAmountInput(newValue)
                                        }
                                }
                                Spacer()
                                Text("EUR")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(Color(.tertiarySystemBackground))
                                    )
                            }

                            Divider().opacity(0.18)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Auszahlung")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("Auszahlung", selection: $payoutMethod) {
                                    ForEach(PayoutMethod.allCases) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if payoutMethod == .paypal {
                                    LabeledTextField(
                                        title: "PayPal",
                                        placeholder: "E-Mail-Adresse",
                                        text: $paypalAddress,
                                        keyboard: .emailAddress,
                                        autocap: .never,
                                        field: .paypal,
                                        focusedField: $focusedField
                                    )
                                } else {
                                    LabeledTextField(
                                        title: "IBAN",
                                        placeholder: "DE...",
                                        text: $iban,
                                        autocap: .characters,
                                        field: .iban,
                                        focusedField: $focusedField
                                    )
                                    .onChange(of: iban) { _, newValue in
                                        // Anzeige leicht formatiert, intern normalisiert
                                        iban = formatIBANForDisplay(newValue)
                                    }
                                }

                                Text(payoutHint)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 18)


                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Senden")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isValid ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                    .padding(.horizontal, 18)
                }
                .padding(.top, 2)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
                }
            }
            .onChange(of: customerName) { _, _ in clearInlineError() }
            .onChange(of: customerAddress) { _, _ in clearInlineError() }
            .onChange(of: amountText) { _, _ in clearInlineError() }
            .onChange(of: payoutMethod) { _, _ in clearInlineError() }
            .onChange(of: paypalAddress) { _, _ in clearInlineError() }
            .onChange(of: iban) { _, _ in clearInlineError() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Provision")
                    .font(.largeTitle.weight(.bold))
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func submit() {
        clearInlineError()

        guard let current = appState.currentUser else {
            showError("Bitte erneut anmelden.")
            return
        }
        guard let admin = adminUser else {
            showError("Kein Admin-Benutzer gefunden.")
            return
        }
        guard let amount = parsedAmount, amount > 0 else {
            showError("Bitte einen gültigen Betrag eingeben.")
            focusedField = .amount
            return
        }

        if customerName.trimmed.isEmpty {
            showError("Bitte den Kundennamen eintragen.")
            focusedField = .customerName
            return
        }
        if customerAddress.trimmed.isEmpty {
            showError("Bitte die Kundenadresse eintragen.")
            focusedField = .customerAddress
            return
        }

        let payoutLine: String
        switch payoutMethod {
        case .paypal:
            if paypalAddress.trimmed.isEmpty {
                showError("Bitte eine PayPal-Adresse eintragen.")
                focusedField = .paypal
                return
            }
            payoutLine = "PayPal: \(paypalAddress.trimmed)"

        case .iban:
            let n = normalizedIBAN(iban)
            if n.count < 15 {
                showError("Bitte eine gültige IBAN eintragen.")
                focusedField = .iban
                return
            }
            payoutLine = "IBAN: \(n)"
        }

        let amountString = currencyString(amount)

        var details = "Kunde: \(customerName.trimmed)\n"
        details += "Adresse: \(customerAddress.trimmed)\n"
        details += "Provision: \(amountString)\n"
        details += "Auszahlung: \(payoutLine)\n"
        details += "Angefragt von: \(current.name)\n"

        appState.createTask(
            title: "Provision zahlen – \(customerName.trimmed)",
            details: details,
            dueDate: nil,
            assignedUser: admin,
            creator: current
        )

        appState.showToast(.success, "Provision gesendet")

        // Reset
        customerName = ""
        customerAddress = ""
        amountText = ""
        paypalAddress = ""
        iban = ""
        payoutMethod = .paypal
        focusedField = nil
    }

    private func showError(_ msg: String) {
        inlineErrorMessage = msg
        showInlineError = true
    }

    private func clearInlineError() {
        if showInlineError {
            showInlineError = false
            inlineErrorMessage = ""
        }
    }

    // MARK: - Formatting / Sanitizing

    private func currencyString(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "EUR"
        nf.locale = Locale(identifier: "de_DE")
        return nf.string(from: amount as NSDecimalNumber) ?? "€\(amount)"
    }

    private func normalizedIBAN(_ s: String) -> String {
        s.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatIBANForDisplay(_ s: String) -> String {
        // Anzeige in 4er-Blöcken, intern wird beim Absenden normalisiert.
        let n = normalizedIBAN(s)
        var out: [String] = []
        out.reserveCapacity((n.count / 4) + 1)
        var i = n.startIndex
        while i < n.endIndex {
            let j = n.index(i, offsetBy: 4, limitedBy: n.endIndex) ?? n.endIndex
            out.append(String(n[i..<j]))
            i = j
        }
        return out.joined(separator: " ")
    }

    private func sanitizeAmountInput(_ s: String) -> String {
        // Erlaubt Ziffern + genau ein Trennzeichen (, oder .). Optionaler führender Betrag.
        let allowed = Set("0123456789,.")
        var filtered = s.filter { allowed.contains($0) }

        // nur ein Trennzeichen zulassen
        var seenSeparator = false
        filtered.removeAll { ch in
            if ch == "," || ch == "." {
                if seenSeparator { return true }
                seenSeparator = true
            }
            return false
        }

        // Wenn '.' als Trennzeichen genutzt wird, später in parsedAmount ohnehin zu '.' normalisiert.
        return filtered
    }
}

// MARK: - Mini Components

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

private struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

private struct LabeledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int> = 1...1
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .sentences

    let field: ProvisionenView.Field
    @FocusState.Binding var focusedField: ProvisionenView.Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(lineLimit)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    ProvisionenView()
        .environmentObject(AppState())
}
