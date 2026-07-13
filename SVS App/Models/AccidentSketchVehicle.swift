//
//  AccidentSketchVehicle.swift
//  SVS App
//

import UIKit

struct AccidentSketchVehicle: Identifiable {
    let id: UUID
    let number: Int
    var label: String
    let color: UIColor
    let size: CGSize
    var center: CGPoint
    var angle: CGFloat

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(number)" : trimmed.uppercased()
    }

    init(
        id: UUID = UUID(),
        number: Int,
        label: String? = nil,
        color: UIColor,
        size: CGSize = CGSize(width: 46, height: 92),
        center: CGPoint,
        angle: CGFloat = 0
    ) {
        self.id = id
        self.number = number
        self.label = label ?? "\(number)"
        self.color = color
        self.size = size
        self.center = center
        self.angle = angle
    }
}

enum AccidentSketchVehicleLayout {
    private static let drawingRect = AccidentSketchMetrics.drawingRect

    private static var midX: CGFloat { drawingRect.midX }
    private static var midY: CGFloat { drawingRect.midY }

    static let maxParticipants = 8
    static let defaultCarSize = CGSize(width: 46, height: 92)

    static func defaults(for template: AccidentSketchTemplate) -> [AccidentSketchVehicle] {
        switch template {
        case .straightRoad:
            return [
                vehicle(1, "AS", .systemBlue, CGPoint(x: midX - 55, y: midY - 100)),
                vehicle(2, "UG", .systemRed, CGPoint(x: midX + 55, y: midY + 110), angle: .pi)
            ]
        case .intersection:
            return [
                vehicle(1, "AS", .systemBlue, CGPoint(x: midX, y: midY - 150)),
                vehicle(2, "UG", .systemRed, CGPoint(x: midX + 150, y: midY), angle: .pi / 2)
            ]
        case .parking:
            let slotWidth: CGFloat = 96
            let startX = drawingRect.minX + 48
            let baseY = drawingRect.midY + 36
            return [
                vehicle(1, "AS", .systemBlue, CGPoint(x: startX + slotWidth / 2, y: baseY + 78)),
                vehicle(
                    2,
                    "UG",
                    .systemRed,
                    CGPoint(x: startX + (slotWidth + 14) * 2 + slotWidth / 2, y: baseY - 28),
                    angle: .pi / 2
                )
            ]
        case .freeCanvas:
            return []
        }
    }

    static func additionalParticipant(after existingVehicles: [AccidentSketchVehicle]) -> AccidentSketchVehicle {
        let nextNumber = (existingVehicles.map(\.number).max() ?? 0) + 1
        let colors: [UIColor] = [
            .systemOrange, .systemPurple, .systemGreen, .systemIndigo,
            .systemCyan, .systemPink, .systemTeal, .systemYellow
        ]
        let slot = nextNumber - 1
        let column = CGFloat(slot % 3 - 1) * 80
        let row = CGFloat((slot / 3) % 3 - 1) * 100

        return vehicle(
            nextNumber,
            "\(nextNumber)",
            colors[(nextNumber - 1) % colors.count],
            CGPoint(x: midX + column, y: midY + row)
        )
    }

    private static func vehicle(
        _ number: Int,
        _ label: String,
        _ color: UIColor,
        _ center: CGPoint,
        angle: CGFloat = 0
    ) -> AccidentSketchVehicle {
        AccidentSketchVehicle(
            number: number,
            label: label,
            color: color,
            size: defaultCarSize,
            center: center,
            angle: angle
        )
    }
}
