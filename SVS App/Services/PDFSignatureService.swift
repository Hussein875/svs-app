//
//  PDFSignatureService.swift
//  SVS App
//

import Foundation
import PDFKit
import PencilKit
import UIKit

struct PDFSignaturePlacement: Hashable {
    let pageIndex: Int
    /// Position als Anteil der Seitenbreite/-höhe (UIKit: Ursprung oben links).
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    func rect(in pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.width * x,
            y: pageBounds.height * y,
            width: pageBounds.width * width,
            height: pageBounds.height * height
        )
    }
}

struct PDFTextOverlay: Hashable {
    let text: String
    let placement: PDFSignaturePlacement
}

struct PDFInkOverlay {
    let image: UIImage
    let placement: PDFSignaturePlacement
}

struct NormalizedTextPlacement: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(from placement: PDFSignaturePlacement) {
        x = placement.x
        y = placement.y
        width = placement.width
        height = placement.height
    }

    func clamped() -> NormalizedTextPlacement {
        var copy = self
        copy.width = min(max(copy.width, 0.12), 0.95)
        copy.height = min(max(copy.height, 0.02), 0.12)
        copy.x = min(max(copy.x, 0), 1 - copy.width)
        copy.y = min(max(copy.y, 0), 1 - copy.height)
        return copy
    }

    func pdfPlacement(pageIndex: Int) -> PDFSignaturePlacement {
        let clamped = clamped()
        return PDFSignaturePlacement(
            pageIndex: pageIndex,
            x: clamped.x,
            y: clamped.y,
            width: clamped.width,
            height: clamped.height
        )
    }
}

struct NormalizedSignaturePlacement: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(from placement: PDFSignaturePlacement) {
        x = placement.x
        y = placement.y
        width = placement.width
        height = placement.height
    }

    func clamped() -> NormalizedSignaturePlacement {
        var copy = self
        copy.width = min(max(copy.width, 0.12), 0.9)
        copy.height = min(max(copy.height, 0.05), 0.35)
        copy.x = min(max(copy.x, 0), 1 - copy.width)
        copy.y = min(max(copy.y, 0), 1 - copy.height)
        return copy
    }

    func pdfPlacement(pageIndex: Int) -> PDFSignaturePlacement {
        let clamped = clamped()
        return PDFSignaturePlacement(
            pageIndex: pageIndex,
            x: clamped.x,
            y: clamped.y,
            width: clamped.width,
            height: clamped.height
        )
    }
}

enum PDFSignatureService {
    enum SignError: LocalizedError {
        case unreadablePDF
        case missingPage(Int)
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .unreadablePDF:
                return "PDF konnte nicht gelesen werden."
            case .missingPage(let index):
                return "Seite \(index + 1) wurde nicht gefunden."
            case .renderFailed:
                return "Signiertes PDF konnte nicht erstellt werden."
            }
        }
    }

    static func renderPageImage(
        sourceURL: URL,
        pageIndex: Int = 0,
        targetWidth: CGFloat = 900
    ) -> UIImage? {
        guard let document = PDFDocument(url: sourceURL),
              let page = document.page(at: pageIndex) else {
            return nil
        }

        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0 else { return nil }

        let scale = targetWidth / pageBounds.width
        let targetSize = CGSize(
            width: pageBounds.width * scale,
            height: pageBounds.height * scale
        )

        return page.thumbnail(of: targetSize, for: .mediaBox)
    }

    static func textStampedPDFURL(
        sourceURL: URL,
        textOverlays: [PDFTextOverlay],
        outputBaseName: String
    ) throws -> URL {
        guard let document = PDFDocument(url: sourceURL) else {
            throw SignError.unreadablePDF
        }

        let data = try textStampedPDFData(
            document: document,
            textOverlays: textOverlays
        )

        let safeBase = outputBaseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeBase)-vorbereitet-\(UUID().uuidString.prefix(8)).pdf"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func signedPDFURL(
        sourceURL: URL,
        signature: UIImage,
        signaturePlacement: PDFSignaturePlacement,
        textOverlays: [PDFTextOverlay] = [],
        inkOverlays: [PDFInkOverlay] = [],
        outputBaseName: String
    ) throws -> URL {
        guard let document = PDFDocument(url: sourceURL) else {
            throw SignError.unreadablePDF
        }

        let data = try signedPDFData(
            document: document,
            signature: signature,
            signaturePlacement: signaturePlacement,
            textOverlays: textOverlays,
            inkOverlays: inkOverlays
        )

        let safeBase = outputBaseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeBase)-signiert-\(UUID().uuidString.prefix(8)).pdf"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func drawnPDFURL(
        sourceURL: URL,
        drawing: PKDrawing,
        drawingBounds: CGRect,
        pageIndex: Int = 0,
        outputBaseName: String
    ) throws -> URL {
        guard let document = PDFDocument(url: sourceURL) else {
            throw SignError.unreadablePDF
        }

        let data = try drawnPDFData(
            document: document,
            drawing: drawing,
            drawingBounds: drawingBounds,
            pageIndex: pageIndex
        )

        let safeBase = outputBaseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeBase)-bearbeitet-\(UUID().uuidString.prefix(8)).pdf"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func drawnPDFData(
        document: PDFDocument,
        drawing: PKDrawing,
        drawingBounds: CGRect,
        pageIndex: Int
    ) throws -> Data {
        guard document.pageCount > 0 else {
            throw SignError.unreadablePDF
        }

        guard let firstPage = document.page(at: 0) else {
            throw SignError.missingPage(0)
        }

        let firstBounds = firstPage.bounds(for: .mediaBox)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        let drawingImage: UIImage? = drawing.bounds.isEmpty ? nil : drawing.image(
            from: drawingBounds,
            scale: 3
        )

        let data = renderer.pdfData { context in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }

                let pageBounds = page.bounds(for: .mediaBox)
                context.beginPage(withBounds: pageBounds, pageInfo: [:])

                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageBounds.height)
                cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: cgContext)
                cgContext.restoreGState()

                if index == pageIndex,
                   let drawingImage {
                    drawSignature(drawingImage, in: pageBounds)
                }
            }
        }

        guard !data.isEmpty else {
            throw SignError.renderFailed
        }

        return data
    }

    private static func textStampedPDFData(
        document: PDFDocument,
        textOverlays: [PDFTextOverlay]
    ) throws -> Data {
        guard document.pageCount > 0 else {
            throw SignError.unreadablePDF
        }

        guard let firstPage = document.page(at: 0) else {
            throw SignError.missingPage(0)
        }

        let firstBounds = firstPage.bounds(for: .mediaBox)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        let data = renderer.pdfData { context in
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }

                let pageBounds = page.bounds(for: .mediaBox)
                context.beginPage(withBounds: pageBounds, pageInfo: [:])

                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageBounds.height)
                cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: cgContext)
                cgContext.restoreGState()

                for overlay in textOverlays where overlay.placement.pageIndex == pageIndex {
                    let textRect = overlay.placement.rect(in: pageBounds)
                    drawText(overlay.text, in: textRect)
                }
            }
        }

        guard !data.isEmpty else {
            throw SignError.renderFailed
        }

        return data
    }

    private static func signedPDFData(
        document: PDFDocument,
        signature: UIImage,
        signaturePlacement: PDFSignaturePlacement,
        textOverlays: [PDFTextOverlay],
        inkOverlays: [PDFInkOverlay]
    ) throws -> Data {
        guard document.pageCount > 0 else {
            throw SignError.unreadablePDF
        }

        guard let firstPage = document.page(at: 0) else {
            throw SignError.missingPage(0)
        }

        let firstBounds = firstPage.bounds(for: .mediaBox)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        let data = renderer.pdfData { context in
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }

                let pageBounds = page.bounds(for: .mediaBox)
                context.beginPage(withBounds: pageBounds, pageInfo: [:])

                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageBounds.height)
                cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: cgContext)
                cgContext.restoreGState()

                if pageIndex == signaturePlacement.pageIndex {
                    let signatureRect = signaturePlacement.rect(in: pageBounds)
                    drawSignature(signature, in: signatureRect)
                }

                for overlay in textOverlays where overlay.placement.pageIndex == pageIndex {
                    let textRect = overlay.placement.rect(in: pageBounds)
                    drawText(overlay.text, in: textRect)
                }

                for overlay in inkOverlays where overlay.placement.pageIndex == pageIndex {
                    let inkRect = overlay.placement.rect(in: pageBounds)
                    drawSignature(overlay.image, in: inkRect)
                }
            }
        }

        guard !data.isEmpty else {
            throw SignError.renderFailed
        }

        return data
    }

    private static func drawSignature(_ signature: UIImage, in rect: CGRect) {
        let fitted = aspectFitRect(for: signature.size, in: rect)
        signature.draw(in: fitted)
    }

    private static func drawText(_ text: String, in rect: CGRect) {
        guard !text.isEmpty else { return }

        let maxFontSize = max(6, rect.height * 0.52)
        var fontSize = maxFontSize

        while fontSize > 5 {
            let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
            let size = (text as NSString).size(withAttributes: [.font: font])
            if size.width <= rect.width * 0.98 {
                break
            }
            fontSize -= 0.5
        }

        fontSize = max(5, fontSize - 6)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let boundingSize = attributed.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size

        let drawRect = CGRect(
            x: rect.minX,
            y: rect.midY - boundingSize.height / 2,
            width: rect.width,
            height: boundingSize.height
        )
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func aspectFitRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }

        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = rect.midX - width / 2
        let y = rect.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
