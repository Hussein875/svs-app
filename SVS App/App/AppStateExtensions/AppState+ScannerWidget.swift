//
//  AppState+ScannerWidget.swift
//  SVS App
//

import FirebaseAuth
import FirebaseFirestore

extension AppState {
    func startScannerWidgetSyncIfNeeded() {
        guard scannerMetaListener == nil else { return }
        guard Auth.auth().currentUser != nil else { return }

        scannerMetaListener = db.collection("scannerMeta")
            .document("current")
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, _ in
                guard let data = snapshot?.data(),
                      let nextNumber = data["nextNumber"] as? Int else { return }

                let year2 = (data["year2"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? Self.currentYear2String()

                DispatchQueue.main.async {
                    ScannerWidgetStore.publishAvailable(
                        number: nextNumber,
                        year2: year2
                    )
                }
            }
    }

    func stopScannerWidgetSync() {
        scannerMetaListener?.remove()
        scannerMetaListener = nil
        ScannerWidgetStore.clear()
    }

    private static func currentYear2String() -> String {
        let year = Calendar.current.component(.year, from: Date())
        return String(format: "%02d", year % 100)
    }
}
