//
//  AccidentSketchTemplate.swift
//  SVS App
//

import Foundation

enum AccidentSketchTemplate: String, CaseIterable, Identifiable {
    case rearEnd
    case intersection
    case rightOfWay
    case laneChange
    case parking
    case roundabout
    case freeCanvas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rearEnd: return "Auffahrunfall"
        case .intersection: return "Kreuzung"
        case .rightOfWay: return "Vorfahrt / Einfahrt"
        case .laneChange: return "Spurwechsel"
        case .parking: return "Parkrempler"
        case .roundabout: return "Kreisverkehr"
        case .freeCanvas: return "Leere Skizze"
        }
    }

    var subtitle: String {
        switch self {
        case .rearEnd:
            return "Zwei Fahrzeuge hintereinander auf einer Straße"
        case .intersection:
            return "Kreuzung mit Fahrtrichtungen"
        case .rightOfWay:
            return "Nebenstraße trifft auf Vorfahrtsstraße"
        case .laneChange:
            return "Parallele Fahrspuren"
        case .parking:
            return "Parkplatz / seitliches Einparken"
        case .roundabout:
            return "Kreisverkehr mit Ein- und Ausfahrten"
        case .freeCanvas:
            return "Raster – ein Fahrzeug pro Plus-Tipp"
        }
    }

    var systemImage: String {
        switch self {
        case .rearEnd: return "arrow.up.circle"
        case .intersection: return "plus"
        case .rightOfWay: return "arrow.turn.up.right"
        case .laneChange: return "arrow.left.and.right"
        case .parking: return "parkingsign.circle"
        case .roundabout: return "arrow.triangle.2.circlepath"
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

    /// Titel in der Editor-Navigationsleiste.
    var navigationTitle: String {
        switch self {
        case .freeCanvas:
            return "Schadenhergang"
        default:
            return title
        }
    }

    /// Überschrift auf dem exportierten PDF.
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
