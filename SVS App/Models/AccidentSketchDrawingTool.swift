//
//  AccidentSketchDrawingTool.swift
//  SVS App
//

import PencilKit
import UIKit

enum AccidentSketchDrawingTool: String, CaseIterable, Identifiable {
    case penBlack
    case penRed
    case markerYellow
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .penBlack: return "Schwarz"
        case .penRed: return "Rot"
        case .markerYellow: return "Marker"
        case .eraser: return "Radieren"
        }
    }

    var systemImage: String {
        switch self {
        case .penBlack: return "pencil.tip"
        case .penRed: return "pencil.tip"
        case .markerYellow: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .penBlack: return .label
        case .penRed: return .systemRed
        case .markerYellow: return .systemYellow
        case .eraser: return .secondaryLabel
        }
    }

    func makeTool() -> PKTool {
        switch self {
        case .penBlack:
            return PKInkingTool(.pen, color: .black, width: 2.5)
        case .penRed:
            return PKInkingTool(.pen, color: .systemRed, width: 2.5)
        case .markerYellow:
            return PKInkingTool(.marker, color: UIColor.systemYellow.withAlphaComponent(0.55), width: 14)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }
}

enum AccidentSketchVehicleLabelPreset: String, CaseIterable, Identifiable {
    case anspruchsteller = "AS"
    case unfallgegner = "UG"
    case one = "1"
    case two = "2"
    case three = "3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anspruchsteller: return "AS – Anspruchsteller"
        case .unfallgegner: return "UG – Unfallgegner"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        }
    }
}
