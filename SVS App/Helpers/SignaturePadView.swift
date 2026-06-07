//
//  SignaturePadView.swift
//  SVS App
//

import SwiftUI
import UIKit

struct SignaturePadView: View {
    @Binding var signatureImage: UIImage?
    var canvasHeight: CGFloat = 180
    var locksParentScrolling = false
    var prompt = "Bitte im Feld unterschreiben."
    var emptyLabel = "Noch keine Eingabe"
    var capturedLabel = "Eingabe erfasst"

    @State private var clearToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt)
                .font(.subheadline)
                .foregroundColor(.secondary)

            SignatureCanvasRepresentable(
                signatureImage: $signatureImage,
                locksParentScrolling: locksParentScrolling,
                clearToken: clearToken
            )
                .frame(height: canvasHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )

            HStack {
                Text(signatureImage == nil ? emptyLabel : capturedLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Löschen") {
                    signatureImage = nil
                    clearToken = UUID()
                }
                .font(.caption.weight(.semibold))
                .disabled(signatureImage == nil)
            }
        }
    }
}

private struct SignatureCanvasRepresentable: UIViewRepresentable {
    @Binding var signatureImage: UIImage?
    var locksParentScrolling: Bool
    var clearToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(signatureImage: $signatureImage)
    }

    func makeUIView(context: Context) -> SignatureCanvasUIView {
        let view = SignatureCanvasUIView()
        view.locksParentScrolling = locksParentScrolling
        view.onSignatureChanged = { image in
            context.coordinator.signatureImage = image
        }
        context.coordinator.canvasView = view
        return view
    }

    func updateUIView(_ uiView: SignatureCanvasUIView, context: Context) {
        uiView.locksParentScrolling = locksParentScrolling
        uiView.updateParentScrollLock()

        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            uiView.clearCanvas()
        }
    }

    final class Coordinator {
        @Binding var signatureImage: UIImage?
        weak var canvasView: SignatureCanvasUIView?
        var lastClearToken: UUID?

        init(signatureImage: Binding<UIImage?>) {
            _signatureImage = signatureImage
        }
    }
}

private final class SignatureCanvasUIView: UIView {
    var onSignatureChanged: ((UIImage?) -> Void)?
    var locksParentScrolling = false

    private var strokes: [SignatureStroke] = []
    private var disabledScrollViews: [UIScrollView] = []
    private var activeStroke: SignatureStroke?
    private let strokeColor = UIColor.black
    private let lineWidth: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateParentScrollLock()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateParentScrollLock()
    }

    func updateParentScrollLock() {
        restoreParentScrollViews()

        guard locksParentScrolling else { return }

        var ancestor: UIView? = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                if scrollView.isScrollEnabled {
                    disabledScrollViews.append(scrollView)
                    scrollView.isScrollEnabled = false
                    scrollView.bounces = false
                }
            }
            ancestor = view.superview
        }
    }

    private func restoreParentScrollViews() {
        for scrollView in disabledScrollViews {
            scrollView.isScrollEnabled = true
            scrollView.bounces = true
        }
        disabledScrollViews.removeAll()
    }

    deinit {
        restoreParentScrollViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(lineWidth)

        for stroke in strokes + (activeStroke.map { [$0] } ?? []) {
            guard let first = stroke.points.first else { continue }
            context.beginPath()
            context.move(to: first)
            for point in stroke.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        activeStroke = SignatureStroke(points: [point])
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var stroke = activeStroke,
              let point = touches.first?.location(in: self) else { return }
        stroke.points.append(point)
        activeStroke = stroke
        setNeedsDisplay()
        publishSignature()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    func clearCanvas() {
        strokes = []
        activeStroke = nil
        setNeedsDisplay()
        onSignatureChanged?(nil)
    }

    private func finishStroke() {
        if let stroke = activeStroke, !stroke.points.isEmpty {
            strokes.append(stroke)
        }
        activeStroke = nil
        setNeedsDisplay()
        publishSignature()
    }

    private func publishSignature() {
        onSignatureChanged?(exportImage())
    }

    private func exportImage() -> UIImage? {
        let allStrokes = strokes + (activeStroke.map { [$0] } ?? [])
        guard !allStrokes.isEmpty else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { ctx in
            let context = ctx.cgContext
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(strokeColor.cgColor)
            context.setLineWidth(lineWidth)

            for stroke in allStrokes {
                guard let first = stroke.points.first else { continue }
                context.beginPath()
                context.move(to: first)
                for point in stroke.points.dropFirst() {
                    context.addLine(to: point)
                }
                context.strokePath()
            }
        }
    }
}

private struct SignatureStroke {
    var points: [CGPoint]
}
