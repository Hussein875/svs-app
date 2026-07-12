//
//  AbtretungserklaerungPlacementStore.swift
//  SVS App
//

import Foundation

enum AbtretungserklaerungPlacementStore {
    private static let defaultsKey = "ae.funnel.fieldPlacements.v5"

    static func placement(for field: AbtretungserklaerungField) -> PDFSignaturePlacement {
        load()[field.rawValue] ?? field.defaultPlacement
    }

    static func save(_ placement: PDFSignaturePlacement, for field: AbtretungserklaerungField) {
        var map = load()
        map[field.rawValue] = placement
        persist(map)
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func load() -> [String: PDFSignaturePlacement] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: StoredPlacement].self, from: data) else {
            return [:]
        }
        return decoded.mapValues(\.placement)
    }

    private static func persist(_ map: [String: PDFSignaturePlacement]) {
        let encoded = Dictionary(uniqueKeysWithValues: map.map { key, value in
            (key, StoredPlacement(placement: value))
        })
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private struct StoredPlacement: Codable {
        let pageIndex: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        var placement: PDFSignaturePlacement {
            PDFSignaturePlacement(pageIndex: pageIndex, x: x, y: y, width: width, height: height)
        }

        init(placement: PDFSignaturePlacement) {
            pageIndex = placement.pageIndex
            x = placement.x
            y = placement.y
            width = placement.width
            height = placement.height
        }
    }
}
