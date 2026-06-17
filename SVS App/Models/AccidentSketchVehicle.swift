//
//  AccidentSketchVehicle.swift
//  SVS App
//

import UIKit

struct AccidentSketchVehicle: Identifiable {
    let id: UUID
    let number: Int
    let color: UIColor
    let size: CGSize
    var center: CGPoint
    var angle: CGFloat

    var displayLabel: String {
        "FZG \(number)"
    }

    init(
        id: UUID = UUID(),
        number: Int,
        color: UIColor,
        size: CGSize,
        center: CGPoint,
        angle: CGFloat = 0
    ) {
        self.id = id
        self.number = number
        self.color = color
        self.size = size
        self.center = center
        self.angle = angle
    }

    func rotated90Degrees() -> AccidentSketchVehicle {
        var copy = self
        copy.angle += .pi / 2
        return copy
    }
}

enum AccidentSketchEditMode: String, CaseIterable, Identifiable {
    case vehicles
    case draw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vehicles: return "Fahrzeuge"
        case .draw: return "Zeichnen"
        }
    }

    var systemImage: String {
        switch self {
        case .vehicles: return "car.fill"
        case .draw: return "pencil.tip"
        }
    }
}

enum AccidentSketchVehicleLayout {
    private static let drawingRect = AccidentSketchMetrics.drawingRect

    private static var midX: CGFloat { drawingRect.midX }
    private static var midY: CGFloat { drawingRect.midY }

    static let maxParticipants = 10

    static func defaults(for template: AccidentSketchTemplate) -> [AccidentSketchVehicle] {
        switch template {
        case .rearEnd:
            return [
                vehicle(1, .systemBlue, CGSize(width: 54, height: 96), CGPoint(x: midX, y: midY - 90)),
                vehicle(2, .systemOrange, CGSize(width: 54, height: 96), CGPoint(x: midX, y: midY + 110))
            ]
        case .intersection:
            return [
                vehicle(1, .systemBlue, CGSize(width: 50, height: 88), CGPoint(x: midX, y: midY - 150)),
                vehicle(2, .systemOrange, CGSize(width: 88, height: 50), CGPoint(x: midX + 150, y: midY), angle: .pi / 2)
            ]
        case .rightOfWay:
            return [
                vehicle(1, .systemOrange, CGSize(width: 88, height: 50), CGPoint(x: midX + 80, y: midY), angle: .pi / 2),
                vehicle(2, .systemBlue, CGSize(width: 50, height: 88), CGPoint(x: midX + 40, y: midY - 120))
            ]
        case .laneChange:
            let left = drawingRect.minX + drawingRect.width * 0.33
            let right = drawingRect.minX + drawingRect.width * 0.66
            return [
                vehicle(1, .systemBlue, CGSize(width: 50, height: 88), CGPoint(x: left - 45, y: midY - 40)),
                vehicle(2, .systemOrange, CGSize(width: 50, height: 88), CGPoint(x: right + 45, y: midY + 60))
            ]
        case .parking:
            let slotWidth: CGFloat = 90
            let startX = drawingRect.minX + 50
            let baseY = midY + 40
            return [
                vehicle(1, .systemGray, CGSize(width: 46, height: 82), CGPoint(x: startX + slotWidth / 2, y: baseY + 75)),
                vehicle(2, .systemOrange, CGSize(width: 82, height: 46), CGPoint(x: startX + (slotWidth + 12) * 2 + slotWidth / 2, y: baseY - 30), angle: .pi / 2)
            ]
        case .roundabout:
            let center = CGPoint(x: midX, y: midY)
            return [
                vehicle(1, .systemBlue, CGSize(width: 50, height: 88), CGPoint(x: center.x, y: drawingRect.minY + 80)),
                vehicle(2, .systemOrange, CGSize(width: 88, height: 50), CGPoint(x: center.x + 170, y: center.y), angle: .pi / 2)
            ]
        case .freeCanvas:
            return []
        }
    }

    static func additionalParticipant(after existingVehicles: [AccidentSketchVehicle]) -> AccidentSketchVehicle {
        let nextNumber = (existingVehicles.map(\.number).max() ?? 0) + 1
        let colors: [UIColor] = [
            .systemPurple, .systemPink, .systemGreen, .systemIndigo,
            .systemRed, .systemCyan, .systemBrown, .systemMint,
            .systemTeal, .systemYellow
        ]
        let slot = nextNumber - 1
        let column = CGFloat(slot % 3 - 1) * 72
        let row = CGFloat((slot / 3) % 3 - 1) * 88

        return vehicle(
            nextNumber,
            colors[(nextNumber - 1) % colors.count],
            CGSize(width: 50, height: 88),
            CGPoint(x: midX + column, y: midY + row)
        )
    }

    private static func vehicle(
        _ number: Int,
        _ color: UIColor,
        _ size: CGSize,
        _ center: CGPoint,
        angle: CGFloat = 0
    ) -> AccidentSketchVehicle {
        AccidentSketchVehicle(
            number: number,
            color: color,
            size: size,
            center: center,
            angle: angle
        )
    }
}
