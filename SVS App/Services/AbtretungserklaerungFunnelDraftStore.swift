//
//  AbtretungserklaerungFunnelDraftStore.swift
//  SVS App
//

import Foundation

struct AbtretungserklaerungFunnelDraft: Codable {
    var stepRawValue: Int
    var form: AbtretungserklaerungForm
    var scanName: String
    var scanNameManuallyEdited: Bool
    var reservation: ScannerReservationResult?
    var ocrNotice: String?
    var driveUploadCompleted: Bool
    var filledPDFPath: String?
    var signedPDFPath: String?
    var savedAt: Date
}

enum AbtretungserklaerungFunnelDraftStore {
    private static let defaultsKey = "ae.funnel.draft"
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    static func load() -> AbtretungserklaerungFunnelDraft? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let draft = try? JSONDecoder().decode(AbtretungserklaerungFunnelDraft.self, from: data) else {
            return nil
        }

        guard Date().timeIntervalSince(draft.savedAt) <= maxAge else {
            clear()
            return nil
        }

        return draft
    }

    static func save(_ draft: AbtretungserklaerungFunnelDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
