//
//  GutachtenYearBetService.swift
//  SVS App
//

import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class GutachtenYearBetViewModel: ObservableObject {
    @Published private(set) var entries: [GutachtenYearBetEntry] = []
    @Published private(set) var activeYear: Int = GutachtenYearBetConfig.defaultYear
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingYear = false
    @Published private(set) var errorMessage: String = ""
    @Published private(set) var infoMessage: String = ""

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    func startListeningIfNeeded() {
        guard listener == nil else { return }
        isLoading = true
        errorMessage = ""

        _Concurrency.Task {
            await loadActiveYear()
            attachEntriesListener()
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func updateActiveYear(_ year: Int) async {
        guard GutachtenYearBetConfig.canSelectMultipleYears else { return }

        let clamped = GutachtenYearBetConfig.clampYear(year)
        guard clamped != activeYear else { return }

        isSavingYear = true
        defer { isSavingYear = false }

        do {
            try await db.collection("gutachtenYearBets")
                .document(GutachtenYearBetConfig.settingsDocumentId)
                .setData([
                    "activeYear": clamped,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)

            listener?.remove()
            listener = nil
            entries = []
            activeYear = clamped
            attachEntriesListener()
            infoMessage = "Wette-Jahr auf \(GutachtenYearBetFormatters.year(clamped)) umgestellt."
        } catch {
            errorMessage = friendlyFirestoreMessage(for: error)
        }
    }

    func saveEntry(_ entry: GutachtenYearBetEntry) async throws {
        let ref = db.collection("gutachtenYearBets")
            .document("\(activeYear)")
            .collection("predictions")
            .document(entry.id)

        try await ref.setData([
            "displayName": entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "predictedTotal": entry.predictedTotal,
            "userId": entry.userId as Any,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)

        try await db.collection("gutachtenYearBets").document("\(activeYear)").setData([
            "year": activeYear,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    func deleteEntry(_ entry: GutachtenYearBetEntry) async throws {
        try await db.collection("gutachtenYearBets")
            .document("\(activeYear)")
            .collection("predictions")
            .document(entry.id)
            .delete()
    }

    // MARK: - Private

    private func loadActiveYear() async {
        guard GutachtenYearBetConfig.canSelectMultipleYears else {
            activeYear = GutachtenYearBetConfig.defaultYear
            return
        }

        do {
            let snap = try await db.collection("gutachtenYearBets")
                .document(GutachtenYearBetConfig.settingsDocumentId)
                .getDocument()
            if let year = snap.data()?["activeYear"] as? Int {
                activeYear = GutachtenYearBetConfig.clampYear(year)
            } else if let year = snap.data()?["activeYear"] as? NSNumber {
                activeYear = GutachtenYearBetConfig.clampYear(year.intValue)
            } else {
                activeYear = GutachtenYearBetConfig.displayYear
            }
        } catch {
            activeYear = GutachtenYearBetConfig.displayYear
            errorMessage = friendlyFirestoreMessage(for: error)
        }
    }

    private func attachEntriesListener() {
        isLoading = true
        listener = db.collection("gutachtenYearBets")
            .document("\(activeYear)")
            .collection("predictions")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = self.friendlyFirestoreMessage(for: error)
                    return
                }

                self.errorMessage = ""
                self.entries = (snapshot?.documents ?? [])
                    .compactMap { Self.entry(from: $0) }
                    .sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
            }
    }

    private func friendlyFirestoreMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "Keine Berechtigung für die Jahreswette. Bitte als Admin anmelden — ggf. einmal ab- und wieder anmelden."
        }
        return error.localizedDescription
    }

    private static func entry(from doc: QueryDocumentSnapshot) -> GutachtenYearBetEntry? {
        let data = doc.data()
        guard let name = data["displayName"] as? String else { return nil }

        let predicted: Int?
        if let value = data["predictedTotal"] as? Int {
            predicted = value
        } else if let value = data["predictedTotal"] as? NSNumber {
            predicted = value.intValue
        } else {
            predicted = nil
        }
        guard let predicted else { return nil }

        return GutachtenYearBetEntry(
            id: doc.documentID,
            displayName: name,
            predictedTotal: predicted,
            userId: data["userId"] as? String
        )
    }
}
