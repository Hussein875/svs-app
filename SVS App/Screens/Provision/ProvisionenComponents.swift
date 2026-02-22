//
//  ProvisionenComponents.swift
//  SVS App
//
//  Extracted from ProvisionenView.swift for readability.
//

import Foundation
import SwiftUI
import UIKit
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

struct CopyableValueRow: View {
    let title: String
    let value: String
    let copyValue: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)

            Spacer()

            Text(value)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)

            if let copyValue, !copyValue.isEmpty {
                Button {
                    UIPasteboard.general.string = copyValue
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kopieren")
            }
        }
        .padding(.vertical, 2)
    }
}

struct SectionCard<Content: View>: View {
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct CommissionDetailSheet: View {
    let row: CommissionRow
    @Environment(\.dismiss) private var dismiss
    @State private var createdByLabel: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Empfehlender") {
                    LabeledContent("Name", value: row.recommenderName)
                    
                    let street = row.recommenderStreet
                    let zipCity: String = {
                        switch (row.recommenderZip, row.recommenderCity) {
                        case let (z?, c?): return "\(z) \(c)"
                        case let (z?, nil): return z
                        case let (nil, c?): return c
                        default: return ""
                        }
                    }()
                    
                    if street == nil && zipCity.isEmpty {
                        LabeledContent("Adresse", value: "—")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adresse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let street { Text(street) }
                            if !zipCity.isEmpty {
                                Text(zipCity)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section("Provision") {
                    if let a = row.amount {
                        LabeledContent("Betrag", value: formatEUR(a))
                    } else {
                        LabeledContent("Betrag", value: "—")
                    }
                    
                    if row.status == "paid" {
                        Text("AUSGEZAHLT")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                    
                    LabeledContent("Auszahlungsart", value: row.payoutMethod.uppercased())
                    
                    if row.payoutMethod == "iban" {
                        CopyableValueRow(
                            title: "IBAN",
                            value: row.payoutIban ?? "—",
                            copyValue: row.payoutIban
                        )
                    } else if row.payoutMethod == "paypal" {
                        CopyableValueRow(
                            title: "PayPal",
                            value: row.payoutPaypal ?? "—",
                            copyValue: row.payoutPaypal
                        )
                    }
                    
                    if let notes = row.notes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Referenz / Notiz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notes)
                        }
                    } else {
                        LabeledContent("Referenz / Notiz", value: "—")
                    }
                }
                
                Section("Zeit") {
                    if let d = row.createdAt {
                        LabeledContent(
                            "Übermittelt",
                            value: d.formatted(date: .complete, time: .shortened)
                        )
                    } else {
                        LabeledContent("Übermittelt", value: "—")
                    }
                }
                
                Section("Dokument") {
                    LabeledContent("Status", value: row.status.uppercased())
                    LabeledContent("ID", value: row.id)
                    LabeledContent(
                        "Veranlasst durch",
                        value: createdByLabel ?? (row.createdByUid ?? "—")
                    )
                }
            }
            .onAppear {
                resolveCreatedByLabelIfNeeded()
            }
            .navigationTitle("Provision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
    
    private func resolveCreatedByLabelIfNeeded() {
        guard createdByLabel == nil else { return }
        guard let uid = row.createdByUid, !uid.isEmpty else {
            createdByLabel = "—"
            return
        }

        if let current = Auth.auth().currentUser?.uid, current == uid {
            createdByLabel = "Du"
            return
        }

        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { snap, _ in
            let data = snap?.data() ?? [:]
            let candidates: [String] = [
                (data["displayName"] as? String) ?? "",
                (data["name"] as? String) ?? "",
                (data["fullName"] as? String) ?? "",
                (data["email"] as? String) ?? ""
            ]
            let best = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            DispatchQueue.main.async {
                self.createdByLabel = best ?? uid
            }
        }
    }
}

struct InlineErrorBanner: View {
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

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct CommissionRow: Identifiable {
    let id: String
    let recommenderName: String

    let recommenderStreet: String?
    let recommenderZip: String?
    let recommenderCity: String?

    let payoutMethod: String
    let payoutIban: String?
    let payoutPaypal: String?

    let amount: Double?
    let notes: String?
    let status: String

    let createdAt: Date?
    let createdByUid: String?
}


enum ProvisionFormatters {
    static let eur: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 2
        return f
    }()

    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.decimalSeparator = ","
        f.groupingSeparator = "."
        f.usesGroupingSeparator = true
        return f
    }()
}

func formatEUR(_ v: Double) -> String {
    ProvisionFormatters.eur.string(from: NSNumber(value: v)) ??
        String(format: "%.2f EUR", v)
}

func normalizeAmountText(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }

    // Accept comma or dot
    let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized) else { return raw }

    return ProvisionFormatters.decimal.string(from: NSNumber(value: value)) ?? raw
}

func parseAmountToDouble(_ raw: String) -> Double? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Remove spaces and common grouping separators, then convert decimal comma to dot.
    let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
    let noGrouping = noSpaces.replacingOccurrences(of: ".", with: "")
    let normalized = noGrouping.replacingOccurrences(of: ",", with: ".")

    return Double(normalized)
}
