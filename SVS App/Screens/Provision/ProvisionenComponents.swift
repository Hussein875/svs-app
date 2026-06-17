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
                
                Section("Vermittlungsprämie") {
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
                    if let gutachtenNumber = row.gutachtenNumber, !gutachtenNumber.isEmpty {
                        LabeledContent("Gutachten-Nr.", value: gutachtenNumber)
                    } else {
                        LabeledContent("Gutachten-Nr.", value: "—")
                    }
                }
            }
            .onAppear {
                resolveCreatedByLabelIfNeeded()
            }
            .navigationTitle("Prämie")
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
    let gutachtenNumber: String?
    let status: String

    let createdAt: Date?
    let createdByUid: String?
}

struct CommissionCreatorStats: Identifiable {
    let userId: String
    let displayName: String
    let orderCount: Int
    let totalAmount: Double
    let openCount: Int
    let paidCount: Int

    var id: String { userId }
}

enum CommissionCreatorStatsBuilder {
    static func build(from documents: [QueryDocumentSnapshot], users: [User]) -> [CommissionCreatorStats] {
        var buckets: [String: (count: Int, total: Double, open: Int, paid: Int)] = [:]

        for doc in documents {
            let data = doc.data()
            let uid = (data["createdByUid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !uid.isEmpty else { continue }

            let amount = data["amount"] as? Double ?? 0
            let status = (data["status"] as? String) ?? ""
            let isPaid = status == "paid"

            var bucket = buckets[uid] ?? (0, 0, 0, 0)
            bucket.count += 1
            bucket.total += amount
            if isPaid {
                bucket.paid += 1
            } else {
                bucket.open += 1
            }
            buckets[uid] = bucket
        }

        return buckets.map { uid, stats in
            CommissionCreatorStats(
                userId: uid,
                displayName: displayName(for: uid, users: users),
                orderCount: stats.count,
                totalAmount: stats.total,
                openCount: stats.open,
                paidCount: stats.paid
            )
        }
        .sorted { lhs, rhs in
            if lhs.orderCount != rhs.orderCount {
                return lhs.orderCount > rhs.orderCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func displayName(for uid: String, users: [User]) -> String {
        if let user = users.first(where: { $0.id == uid }) {
            let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return uid
    }
}

struct CommissionTeamInsightsSection: View {
    let stats: [CommissionCreatorStats]
    let isLoading: Bool

    var body: some View {
        SectionCard(title: "Übersicht nach Mitarbeiter", systemImage: "person.2.fill") {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lade Statistik …")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if stats.isEmpty {
                Text("Noch keine Prämien-Aufträge vorhanden.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(stats) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(formatEUR(row.totalAmount))
                                    .font(.subheadline.weight(.semibold))
                            }

                            HStack(spacing: 12) {
                                Label("\(row.orderCount) Aufträge", systemImage: "doc.text")
                                Label("\(row.openCount) offen", systemImage: "clock")
                                Label("\(row.paidCount) ausgezahlt", systemImage: "checkmark.circle")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)

                        if row.id != stats.last?.id {
                            Divider()
                        }
                    }
                }

                Text("Nur für Admins sichtbar · bis zu 1.000 neueste Einträge")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
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
