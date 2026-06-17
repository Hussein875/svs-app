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
            drawRoads(for: template, in: rect, context: context.cgContext)

            for vehicle in vehicles {
                drawCar(
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
        let fitted = vehicleAxisAlignedSize(for: vehicle.size, angle: vehicle.angle, padding: 10)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: fitted, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: fitted.width / 2, y: fitted.height / 2)
            drawCar(
                center: .zero,
                size: vehicle.size,
                angle: vehicle.angle,
                label: vehicle.displayLabel,
                color: vehicle.color,
                context: cg
            )
        }
    }

    static func vehicleHostSize(for vehicle: AccidentSketchVehicle, padding: CGFloat = 10) -> CGSize {
        vehicleAxisAlignedSize(for: vehicle.size, angle: vehicle.angle, padding: padding)
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

    // MARK: - Layout helpers

    private static let drawingRect = AccidentSketchMetrics.drawingRect

    private static func drawRoads(
        for template: AccidentSketchTemplate,
        in page: CGRect,
        context: CGContext
    ) {
        switch template {
        case .rearEnd:
            drawRearEndRoads(in: page, context: context)
        case .intersection:
            drawIntersectionRoads(in: page, context: context)
        case .rightOfWay:
            drawRightOfWayRoads(in: page, context: context)
        case .laneChange:
            drawLaneChangeRoads(in: page, context: context)
        case .parking:
            drawParkingRoads(in: page, context: context)
        case .roundabout:
            drawRoundaboutRoads(in: page, context: context)
        case .freeCanvas:
            drawFreeCanvasRoads(in: page, context: context)
        }
    }

    private static func drawStraightRoad(context: CGContext) {
        asphalt(in: drawingRect, context: context)
        let midX = drawingRect.midX
        roadLine(
            from: CGPoint(x: midX, y: drawingRect.minY + 20),
            to: CGPoint(x: midX, y: drawingRect.maxY - 20),
            width: 2,
            color: .white,
            dashed: true,
            context: context
        )
        roadLine(
            from: CGPoint(x: drawingRect.minX + 24, y: drawingRect.minY),
            to: CGPoint(x: drawingRect.minX + 24, y: drawingRect.maxY),
            width: 3,
            color: .white,
            dashed: false,
            context: context
        )
        roadLine(
            from: CGPoint(x: drawingRect.maxX - 24, y: drawingRect.minY),
            to: CGPoint(x: drawingRect.maxX - 24, y: drawingRect.maxY),
            width: 3,
            color: .white,
            dashed: false,
            context: context
        )
    }

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
        let hint = "Mit Stift ergänzen: Fahrweg · Bremspunkte · Sicht · Beschriftung"
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
        context.setFillColor(UIColor(white: 0.93, alpha: 1).cgColor)
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
            context.setLineDash(phase: 0, lengths: [10, 8])
        }
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawCar(
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
        let path = UIBezierPath(roundedRect: body, cornerRadius: 6)
        context.setFillColor(color.withAlphaComponent(0.35).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.addPath(path.cgPath)
        context.strokePath()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: color
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(
            at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
            withAttributes: attrs
        )
        context.restoreGState()
    }

    private static func drawArrow(
        from: CGPoint,
        to: CGPoint,
        color: UIColor,
        context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(2.5)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = CGPoint(x: to.x, y: to.y)
        context.translateBy(x: head.x, y: head.y)
        context.rotate(by: angle)
        let arrow = UIBezierPath()
        arrow.move(to: .zero)
        arrow.addLine(to: CGPoint(x: -10, y: -5))
        arrow.addLine(to: CGPoint(x: -10, y: 5))
        arrow.close()
        context.addPath(arrow.cgPath)
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Templates

    private static func drawFreeCanvasRoads(in page: CGRect, context: CGContext) {
        asphalt(in: drawingRect, context: context)
        context.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
        context.setLineWidth(0.5)
        let step: CGFloat = 28
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

    private static func drawRearEndRoads(in page: CGRect, context: CGContext) {
        drawStraightRoad(context: context)

        let midX = drawingRect.midX
        drawArrow(
            from: CGPoint(x: midX + 70, y: drawingRect.midY + 40),
            to: CGPoint(x: midX + 70, y: drawingRect.midY - 30),
            color: UIColor.systemRed,
            context: context
        )
    }

    private static func drawIntersectionRoads(in page: CGRect, context: CGContext) {
        asphalt(in: drawingRect, context: context)
        let midX = drawingRect.midX
        let midY = drawingRect.midY
        let roadWidth: CGFloat = 120

        context.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
        context.fill(CGRect(x: midX - roadWidth / 2, y: drawingRect.minY, width: roadWidth, height: drawingRect.height))
        context.fill(CGRect(x: drawingRect.minX, y: midY - roadWidth / 2, width: drawingRect.width, height: roadWidth))

        roadLine(
            from: CGPoint(x: midX, y: drawingRect.minY),
            to: CGPoint(x: midX, y: drawingRect.maxY),
            width: 2,
            color: .white,
            dashed: true,
            context: context
        )
        roadLine(
            from: CGPoint(x: drawingRect.minX, y: midY),
            to: CGPoint(x: drawingRect.maxX, y: midY),
            width: 2,
            color: .white,
            dashed: true,
            context: context
        )
    }

    private static func drawRightOfWayRoads(in page: CGRect, context: CGContext) {
        asphalt(in: drawingRect, context: context)
        let midY = drawingRect.midY
        let joinX = drawingRect.midX - 40

        context.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
        context.fill(CGRect(x: drawingRect.minX + 40, y: midY - 55, width: drawingRect.width - 80, height: 110))
        context.fill(CGRect(x: joinX - 55, y: midY, width: 110, height: drawingRect.maxY - midY - 20))

        drawPriorityRoadSign(
            center: CGPoint(x: drawingRect.midX + 95, y: midY - 8),
            size: 34,
            context: context
        )
        drawYieldSign(
            center: CGPoint(x: joinX + 8, y: midY + 88),
            size: 36,
            context: context
        )
    }

    /// StVO Zeichen 205 – Vorfahrt gewähren (rot umrandetes Dreieck).
    private static func drawYieldSign(center: CGPoint, size: CGFloat, context: CGContext) {
        let height = size
        let width = size * 0.95
        let apex = CGPoint(x: center.x, y: center.y + height * 0.42)
        let topLeft = CGPoint(x: center.x - width / 2, y: center.y - height * 0.38)
        let topRight = CGPoint(x: center.x + width / 2, y: center.y - height * 0.38)

        let triangle = UIBezierPath()
        triangle.move(to: apex)
        triangle.addLine(to: topLeft)
        triangle.addLine(to: topRight)
        triangle.close()

        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(triangle.cgPath)
        context.fillPath()
        context.setStrokeColor(UIColor(red: 0.85, green: 0.05, blue: 0.08, alpha: 1).cgColor)
        context.setLineWidth(max(2.5, size * 0.09))
        context.setLineJoin(.round)
        context.addPath(triangle.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    /// StVO Zeichen 306 – Vorfahrtstraße (gelbe Raute).
    private static func drawPriorityRoadSign(center: CGPoint, size: CGFloat, context: CGContext) {
        let half = size / 2
        let diamond = UIBezierPath()
        diamond.move(to: CGPoint(x: center.x, y: center.y - half))
        diamond.addLine(to: CGPoint(x: center.x + half, y: center.y))
        diamond.addLine(to: CGPoint(x: center.x, y: center.y + half))
        diamond.addLine(to: CGPoint(x: center.x - half, y: center.y))
        diamond.close()

        context.saveGState()
        context.setFillColor(UIColor(red: 0.98, green: 0.82, blue: 0.08, alpha: 1).cgColor)
        context.addPath(diamond.cgPath)
        context.fillPath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(max(2, size * 0.08))
        context.addPath(diamond.cgPath)
        context.strokePath()
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(max(1, size * 0.04))
        context.addPath(diamond.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawLaneChangeRoads(in page: CGRect, context: CGContext) {
        asphalt(in: drawingRect, context: context)
        let left = drawingRect.minX + drawingRect.width * 0.33
        let right = drawingRect.minX + drawingRect.width * 0.66

        roadLine(
            from: CGPoint(x: left, y: drawingRect.minY),
            to: CGPoint(x: left, y: drawingRect.maxY),
            width: 2,
            color: .white,
            dashed: true,
            context: context
        )
        roadLine(
            from: CGPoint(x: right, y: drawingRect.minY),
            to: CGPoint(x: right, y: drawingRect.maxY),
            width: 2,
            color: .white,
            dashed: true,
            context: context
        )

        let curve = UIBezierPath()
        curve.move(to: CGPoint(x: left - 45, y: drawingRect.midY + 10))
        curve.addQuadCurve(
            to: CGPoint(x: right + 45, y: drawingRect.midY + 30),
            controlPoint: CGPoint(x: drawingRect.midX, y: drawingRect.midY - 40)
        )
        context.setStrokeColor(UIColor.systemRed.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 6])
        context.addPath(curve.cgPath)
        context.strokePath()
    }

    private static func drawParkingRoads(in page: CGRect, context: CGContext) {
        asphalt(in: drawingRect, context: context)
        let slotWidth: CGFloat = 90
        let startX = drawingRect.minX + 50
        let baseY = drawingRect.midY + 40

        for index in 0..<4 {
            let x = startX + CGFloat(index) * (slotWidth + 12)
            let slot = CGRect(x: x, y: baseY, width: slotWidth, height: 150)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2)
            context.stroke(slot)
        }
    }

    private static func drawRoundaboutRoads(in page: CGRect, context: CGContext) {
        asphalt(in: drawingRect, context: context)
        let center = CGPoint(x: drawingRect.midX, y: drawingRect.midY)
        let outer: CGFloat = 110
        let inner: CGFloat = 55

        context.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        context.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))

        context.setStrokeColor(UIColor.systemGreen.cgColor)
        context.setLineWidth(2)
        context.addArc(center: center, radius: (outer + inner) / 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
    }
}
