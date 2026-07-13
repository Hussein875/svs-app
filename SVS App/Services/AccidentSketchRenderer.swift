//
//  AccidentSketchRenderer.swift
//  SVS App
//

import PencilKit
import UIKit

enum AccidentSketchMetrics {
    static let canvasSize = CGSize(width: 595, height: 842)
    static let drawingRect = CGRect(x: 36, y: 96, width: 523, height: 640)
}

enum AccidentSketchRenderer {
    static func render(_ template: AccidentSketchTemplate) -> UIImage {
        renderExport(
            template: template,
            vehicles: AccidentSketchVehicleLayout.defaults(for: template),
            drawing: PKDrawing(),
            drawingBounds: .zero
        )
    }

    static func renderBackground(_ template: AccidentSketchTemplate) -> UIImage {
        renderScene(template: template, vehicles: [], drawing: PKDrawing(), drawingBounds: .zero)
    }

    static func renderExport(
        template: AccidentSketchTemplate,
        vehicles: [AccidentSketchVehicle],
        drawing: PKDrawing,
        drawingBounds: CGRect
    ) -> UIImage {
        renderScene(
            template: template,
            vehicles: vehicles,
            drawing: drawing,
            drawingBounds: drawingBounds
        )
    }

    private static func renderScene(
        template: AccidentSketchTemplate,
        vehicles: [AccidentSketchVehicle],
        drawing: PKDrawing,
        drawingBounds: CGRect
    ) -> UIImage {
        let size = AccidentSketchMetrics.canvasSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.white.setFill()
            context.fill(rect)

            drawHeader(template: template, in: rect, context: context.cgContext)
            drawRoads(for: template, context: context.cgContext)

            for vehicle in vehicles {
                drawTopDownCar(
                    center: vehicle.center,
                    size: vehicle.size,
                    angle: vehicle.angle,
                    label: vehicle.displayLabel,
                    color: vehicle.color,
                    context: context.cgContext
                )
            }

            if !drawing.bounds.isEmpty, !drawingBounds.isEmpty {
                let drawingImage = drawing.image(from: drawingBounds, scale: 3)
                drawingImage.draw(in: rect)
            }

            drawFooter(in: rect, context: context.cgContext)
        }
    }

    static func renderVehicleImage(_ vehicle: AccidentSketchVehicle, scale: CGFloat = 2) -> UIImage {
        let fitted = vehicleHostSize(for: vehicle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: fitted, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: fitted.width / 2, y: fitted.height / 2)
            drawTopDownCar(
                center: .zero,
                size: vehicle.size,
                angle: vehicle.angle,
                label: vehicle.displayLabel,
                color: vehicle.color,
                context: cg
            )
        }
    }

    static func vehicleHostSize(for vehicle: AccidentSketchVehicle, padding: CGFloat = 12) -> CGSize {
        let directionPadding = vehicle.size.height * 0.58
        return vehicleAxisAlignedSize(
            for: vehicle.size,
            angle: vehicle.angle,
            padding: padding + directionPadding
        )
    }

    private static func vehicleAxisAlignedSize(
        for size: CGSize,
        angle: CGFloat,
        padding: CGFloat
    ) -> CGSize {
        let cosA = abs(cos(angle))
        let sinA = abs(sin(angle))
        return CGSize(
            width: size.width * cosA + size.height * sinA + padding * 2,
            height: size.width * sinA + size.height * cosA + padding * 2
        )
    }

    // MARK: - Roads

    private static let drawingRect = AccidentSketchMetrics.drawingRect

    private static func drawRoads(
        for template: AccidentSketchTemplate,
        context: CGContext
    ) {
        switch template {
        case .straightRoad:
            drawStraightRoad(context: context)
        case .intersection:
            drawIntersectionRoads(context: context)
        case .parking:
            drawParkingRoads(context: context)
        case .freeCanvas:
            drawFreeCanvasRoads(context: context)
        }
    }

    private static func drawStraightRoad(context: CGContext) {
        asphalt(in: drawingRect, context: context)

        let midX = drawingRect.midX
        let laneOffset: CGFloat = 55

        roadLine(
            from: CGPoint(x: midX, y: drawingRect.minY + 16),
            to: CGPoint(x: midX, y: drawingRect.maxY - 16),
            width: 2.5,
            color: .white,
            dashed: true,
            context: context
        )
        roadLine(
            from: CGPoint(x: midX - laneOffset, y: drawingRect.minY + 16),
            to: CGPoint(x: midX - laneOffset, y: drawingRect.maxY - 16),
            width: 2,
            color: UIColor.white.withAlphaComponent(0.55),
            dashed: true,
            context: context
        )
        roadLine(
            from: CGPoint(x: midX + laneOffset, y: drawingRect.minY + 16),
            to: CGPoint(x: midX + laneOffset, y: drawingRect.maxY - 16),
            width: 2,
            color: UIColor.white.withAlphaComponent(0.55),
            dashed: true,
            context: context
        )

        drawRoadEdge(at: drawingRect.minX + 20, context: context)
        drawRoadEdge(at: drawingRect.maxX - 20, context: context)
    }

    private static func drawIntersectionRoads(context: CGContext) {
        asphalt(in: drawingRect, context: context)

        let midX = drawingRect.midX
        let midY = drawingRect.midY
        let roadWidth: CGFloat = 130

        context.setFillColor(UIColor(white: 0.86, alpha: 1).cgColor)
        context.fill(
            CGRect(
                x: midX - roadWidth / 2,
                y: drawingRect.minY,
                width: roadWidth,
                height: drawingRect.height
            )
        )
        context.fill(
            CGRect(
                x: drawingRect.minX,
                y: midY - roadWidth / 2,
                width: drawingRect.width,
                height: roadWidth
            )
        )

        roadLine(
            from: CGPoint(x: midX, y: drawingRect.minY + 12),
            to: CGPoint(x: midX, y: drawingRect.maxY - 12),
            width: 2.5,
            color: .white,
            dashed: true,
            context: context
        )
        roadLine(
            from: CGPoint(x: drawingRect.minX + 12, y: midY),
            to: CGPoint(x: drawingRect.maxX - 12, y: midY),
            width: 2.5,
            color: .white,
            dashed: true,
            context: context
        )

        drawRoadEdge(at: drawingRect.minX + 20, context: context)
        drawRoadEdge(at: drawingRect.maxX - 20, context: context)
    }

    private static func drawParkingRoads(context: CGContext) {
        asphalt(in: drawingRect, context: context)

        let slotWidth: CGFloat = 96
        let slotHeight: CGFloat = 152
        let startX = drawingRect.minX + 48
        let baseY = drawingRect.midY + 36
        let aisleY = baseY - 18

        roadLine(
            from: CGPoint(x: drawingRect.minX + 24, y: aisleY),
            to: CGPoint(x: drawingRect.maxX - 24, y: aisleY),
            width: 3,
            color: UIColor.white.withAlphaComponent(0.7),
            dashed: true,
            context: context
        )

        for index in 0..<4 {
            let x = startX + CGFloat(index) * (slotWidth + 14)
            let slot = CGRect(x: x, y: baseY, width: slotWidth, height: slotHeight)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2.5)
            context.stroke(slot)

            let label = "P\(index + 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75)
            ]
            let textSize = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(
                at: CGPoint(x: slot.midX - textSize.width / 2, y: slot.maxY + 4),
                withAttributes: attrs
            )
        }
    }

    private static func drawFreeCanvasRoads(context: CGContext) {
        asphalt(in: drawingRect, context: context)
        context.setStrokeColor(UIColor(white: 0.86, alpha: 1).cgColor)
        context.setLineWidth(0.5)
        let step: CGFloat = 32
        var x = drawingRect.minX
        while x <= drawingRect.maxX {
            context.move(to: CGPoint(x: x, y: drawingRect.minY))
            context.addLine(to: CGPoint(x: x, y: drawingRect.maxY))
            x += step
        }
        var y = drawingRect.minY
        while y <= drawingRect.maxY {
            context.move(to: CGPoint(x: drawingRect.minX, y: y))
            context.addLine(to: CGPoint(x: drawingRect.maxX, y: y))
            y += step
        }
        context.strokePath()
    }

    private static func drawRoadEdge(at x: CGFloat, context: CGContext) {
        roadLine(
            from: CGPoint(x: x, y: drawingRect.minY),
            to: CGPoint(x: x, y: drawingRect.maxY),
            width: 3.5,
            color: .white,
            dashed: false,
            context: context
        )
    }

    // MARK: - Top-down car

    private static func drawTopDownCar(
        center: CGPoint,
        size: CGSize,
        angle: CGFloat,
        label: String,
        color: UIColor,
        context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)

        let body = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )

        let bodyPath = UIBezierPath(roundedRect: body, cornerRadius: size.width * 0.28)
        context.setFillColor(color.withAlphaComponent(0.82).cgColor)
        context.addPath(bodyPath.cgPath)
        context.fillPath()

        context.setStrokeColor(color.darker(by: 0.18).cgColor)
        context.setLineWidth(2)
        context.addPath(bodyPath.cgPath)
        context.strokePath()

        drawHeadlights(body: body, context: context)

        let windshield = CGRect(
            x: body.minX + size.width * 0.14,
            y: body.minY + size.height * 0.1,
            width: size.width * 0.72,
            height: size.height * 0.2
        )
        let windshieldPath = UIBezierPath(roundedRect: windshield, cornerRadius: 4)
        context.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor)
        context.addPath(windshieldPath.cgPath)
        context.fillPath()

        let rearWindow = CGRect(
            x: body.minX + size.width * 0.16,
            y: body.maxY - size.height * 0.24,
            width: size.width * 0.68,
            height: size.height * 0.14
        )
        let rearPath = UIBezierPath(roundedRect: rearWindow, cornerRadius: 3)
        context.setFillColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        context.addPath(rearPath.cgPath)
        context.fillPath()

        let wheelSize = CGSize(width: size.width * 0.22, height: size.height * 0.1)
        let wheelOffsets: [(CGFloat, CGFloat)] = [
            (-size.width * 0.34, -size.height * 0.3),
            (size.width * 0.34, -size.height * 0.3),
            (-size.width * 0.34, size.height * 0.3),
            (size.width * 0.34, size.height * 0.3),
        ]
        for (offsetX, offsetY) in wheelOffsets {
            let wheel = CGRect(
                x: offsetX - wheelSize.width / 2,
                y: offsetY - wheelSize.height / 2,
                width: wheelSize.width,
                height: wheelSize.height
            )
            context.setFillColor(UIColor(white: 0.12, alpha: 0.9).cgColor)
            context.fillEllipse(in: wheel)
        }

        drawTravelDirectionIndicator(body: body, vehicleColor: color, context: context)

        let text = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let charCount = max(text.count, 1)
        let badgeWidth = min(size.width * 0.88, max(size.width * 0.42, CGFloat(charCount) * 9 + 8))
        let badgeHeight = size.width * 0.4
        let badge = CGRect(
            x: -badgeWidth / 2,
            y: -badgeHeight / 2,
            width: badgeWidth,
            height: badgeHeight
        )

        let badgePath = UIBezierPath(roundedRect: badge, cornerRadius: badgeHeight / 2)
        context.setFillColor(UIColor.white.withAlphaComponent(0.94).cgColor)
        context.addPath(badgePath.cgPath)
        context.fillPath()
        context.setStrokeColor(color.darker(by: 0.22).cgColor)
        context.setLineWidth(1.5)
        context.addPath(badgePath.cgPath)
        context.strokePath()

        let fontSize: CGFloat = charCount <= 2 ? badgeHeight * 0.52 : badgeHeight * 0.38
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color.darker(by: 0.28)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
            withAttributes: attrs
        )

        context.restoreGState()
    }

    /// Frontscheinwerfer + Fahrtrichtungspfeil (Front = oben im lokalen Koordinatensystem).
    private static func drawHeadlights(body: CGRect, context: CGContext) {
        let lightSize = CGSize(width: body.width * 0.14, height: body.height * 0.07)
        let lightY = body.minY + body.height * 0.07
        for offsetX in [-body.width * 0.28, body.width * 0.28] {
            let light = CGRect(
                x: offsetX - lightSize.width / 2,
                y: lightY - lightSize.height / 2,
                width: lightSize.width,
                height: lightSize.height
            )
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.9).cgColor)
            context.fillEllipse(in: light)
        }
    }

    private static func drawTravelDirectionIndicator(
        body: CGRect,
        vehicleColor: UIColor,
        context: CGContext
    ) {
        let chevron = UIBezierPath()
        let tipY = body.minY + body.height * 0.05
        let baseY = body.minY + body.height * 0.24
        let halfWidth = body.width * 0.2
        chevron.move(to: CGPoint(x: 0, y: tipY))
        chevron.addLine(to: CGPoint(x: -halfWidth, y: baseY))
        chevron.addLine(to: CGPoint(x: halfWidth, y: baseY))
        chevron.close()

        context.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor)
        context.addPath(chevron.cgPath)
        context.fillPath()
        context.setStrokeColor(vehicleColor.darker(by: 0.3).cgColor)
        context.setLineWidth(1.2)
        context.addPath(chevron.cgPath)
        context.strokePath()

        let rayStart = CGPoint(x: 0, y: body.minY)
        let rayLength = body.height * 0.55
        let rayEnd = CGPoint(x: 0, y: body.minY - rayLength)

        context.saveGState()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.2)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [7, 5])
        context.move(to: rayStart)
        context.addLine(to: rayEnd)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.setStrokeColor(vehicleColor.darker(by: 0.15).cgColor)
        context.setLineWidth(1.2)
        context.translateBy(x: rayEnd.x, y: rayEnd.y)
        let head = UIBezierPath()
        head.move(to: .zero)
        head.addLine(to: CGPoint(x: -6, y: 9))
        head.addLine(to: CGPoint(x: 6, y: 9))
        head.close()
        context.addPath(head.cgPath)
        context.fillPath()
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Chrome

    private static func drawHeader(
        template: AccidentSketchTemplate,
        in page: CGRect,
        context: CGContext
    ) {
        let title = template.pdfHeaderTitle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        (title as NSString).draw(
            in: CGRect(x: 36, y: 28, width: page.width - 72, height: 28),
            withAttributes: attrs
        )

        if template.includesPdfSubtitle {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (template.subtitle as NSString).draw(
                in: CGRect(x: 36, y: 56, width: page.width - 72, height: 32),
                withAttributes: subAttrs
            )
        }
    }

    private static func drawFooter(in page: CGRect, context: CGContext) {
        let hint = "Fahrweg · Bremspunkte · Sicht · Beschriftung mit Stift ergänzen"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        (hint as NSString).draw(
            in: CGRect(x: 36, y: page.height - 52, width: page.width - 72, height: 20),
            withAttributes: attrs
        )

        let fields = "Ort: ____________________   Datum: ____________   Akten-Nr.: ____________"
        let fieldAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.label
        ]
        (fields as NSString).draw(
            in: CGRect(x: 36, y: page.height - 78, width: page.width - 72, height: 20),
            withAttributes: fieldAttrs
        )
    }

    private static func asphalt(in rect: CGRect, context: CGContext) {
        context.setFillColor(UIColor(red: 0.55, green: 0.57, blue: 0.6, alpha: 1).cgColor)
        context.fill(rect)
    }

    private static func roadLine(
        from: CGPoint,
        to: CGPoint,
        width: CGFloat,
        color: UIColor,
        dashed: Bool,
        context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        if dashed {
            context.setLineDash(phase: 0, lengths: [12, 10])
        }
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.restoreGState()
    }
}

private extension UIColor {
    func darker(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }
        return UIColor(
            red: max(red - amount, 0),
            green: max(green - amount, 0),
            blue: max(blue - amount, 0),
            alpha: alpha
        )
    }
}
