//
//  AppState+ScannerUploads.swift
//  SVS App
//

import FirebaseAuth
import FirebaseFirestore

extension AppState {
    func startScannerUploadsListenerIfNeeded() {
        guard scannerUploadsListener == nil else { return }
        guard let uid = currentUser?.id, !uid.hasPrefix("invite:") else { return }

        scannerUploadsListener = db.collection("scannerReservations")
            .whereField("reservedByUid", isEqualTo: uid)
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage =
                            "Uploads konnten nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }

                let docs = snapshot?.documents ?? []
                self.firestoreListenerQueue.async { [weak self] in
                    guard let self else { return }

                    let uploads = docs.compactMap { doc in
                        ScannerUploadEntry(id: doc.documentID, data: doc.data())
                    }
                    .sorted { lhs, rhs in
                        let lhsDate = lhs.uploadedAt ?? lhs.createdAt ?? .distantPast
                        let rhsDate = rhs.uploadedAt ?? rhs.createdAt ?? .distantPast
                        if lhsDate != rhsDate {
                            return lhsDate > rhsDate
                        }
                        if lhs.year2 != rhs.year2 {
                            return lhs.year2 > rhs.year2
                        }
                        return lhs.number > rhs.number
                    }

                    DispatchQueue.main.async {
                        self.scannerUploads = uploads
                    }
                }
            }
    }

    func stopScannerUploadsListener() {
        scannerUploadsListener?.remove()
        scannerUploadsListener = nil
        scannerUploads = []
    }
}
