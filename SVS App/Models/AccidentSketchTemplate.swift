//
//  AccidentSketchTemplate.swift
//  SVS App
//

import Foundation

enum AccidentSketchTemplate: String, CaseIterable, Identifiable {
    case straightRoad
    case intersection
    case parking
    case freeCanvas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straightRoad: return "Gerade Straße"
        case .intersection: return "Kreuzung"
        case .parking: return "Parkplatz"
        case .freeCanvas: return "Leere Skizze"
        }
    }

    var subtitle: String {
        switch self {
        case .straightRoad:
            return "Zwei Fahrspuren – Auffahrunfall, Spurwechsel"
        case .intersection:
            return "Kreuzung von oben"
        case .parking:
            return "Parkbuchten – Parkrempler, Rangieren"
        case .freeCanvas:
            return "Raster – Autos frei platzieren"
        }
    }

    var systemImage: String {
        switch self {
        case .straightRoad: return "road.lanes"
        case .intersection: return "plus"
        case .parking: return "parkingsign.circle"
        case .freeCanvas: return "square.and.pencil"
        }
    }

    var outputBaseName: String {
        switch self {
        case .freeCanvas:
            return "Schadenhergang"
        default:
            return "Schadenhergang-\(title)"
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")
        }
    }

    var navigationTitle: String {
        switch self {
        case .freeCanvas:
            return "Schadenhergang"
        default:
            return title
        }
    }

    var pdfHeaderTitle: String {
        switch self {
        case .freeCanvas:
            return "Schadenhergang"
        default:
            return "Schadenhergang – \(title)"
        }
    }

    var includesPdfSubtitle: Bool {
        self != .freeCanvas
    }
}
