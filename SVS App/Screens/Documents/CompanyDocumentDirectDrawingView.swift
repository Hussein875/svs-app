//
//  CompanyDocumentDirectDrawingView.swift
//  SVS App
//

import PencilKit
import SwiftUI

struct CompanyDocumentDirectDrawingView: View {
    let fileURL: URL
    let outputBaseName: String
    let onCancel: () -> Void
    let onComplete: (URL) -> Void

    @State private var drawing = PKDrawing()
    @State private var drawingBounds: CGRect = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                PDFDirectDrawingCanvas(
                    fileURL: fileURL,
                    drawing: $drawing,
                    drawingBounds: $drawingBounds
                )
            }
            .navigationTitle("Auf PDF zeichnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        saveDrawing()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Löschen", role: .destructive) {
                        drawing = PKDrawing()
                    }
                    .disabled(drawing.bounds.isEmpty || isSaving)

                    Spacer()

                    Text("Mit dem Finger oder Apple Pencil direkt auf dem PDF malen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView("PDF wird gespeichert …")
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .alert(
            "Speichern fehlgeschlagen",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func saveDrawing() {
        isSaving = true

        _Concurrency.Task { @MainActor in
            defer { isSaving = false }

            do {
                let outputURL = try PDFSignatureService.drawnPDFURL(
                    sourceURL: fileURL,
                    drawing: drawing,
                    drawingBounds: drawingBounds,
                    outputBaseName: outputBaseName
                )
                onComplete(outputURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PDFDirectDrawingCanvas: UIViewControllerRepresentable {
    let fileURL: URL
    @Binding var drawing: PKDrawing
    @Binding var drawingBounds: CGRect

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, drawingBounds: $drawingBounds)
    }

    func makeUIViewController(context: Context) -> PDFDirectDrawingViewController {
        let controller = PDFDirectDrawingViewController(fileURL: fileURL)
        controller.canvasView.delegate = context.coordinator
        controller.onLayout = { bounds in
            context.coordinator.drawingBounds = bounds
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: PDFDirectDrawingViewController, context: Context) {
        if uiViewController.canvasView.drawing != drawing {
            uiViewController.canvasView.drawing = drawing
        }
        uiViewController.updateLayout()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        @Binding var drawingBounds: CGRect

        init(drawing: Binding<PKDrawing>, drawingBounds: Binding<CGRect>) {
            _drawing = drawing
            _drawingBounds = drawingBounds
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
            drawingBounds = canvasView.bounds
        }
    }
}

private final class PDFDirectDrawingViewController: UIViewController {
    let fileURL: URL
    var onLayout: ((CGRect) -> Void)?

    private let pageImageView = UIImageView()
    let canvasView = PKCanvasView()
    private var toolPicker: PKToolPicker?
    private var pageImage: UIImage?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground

        pageImageView.contentMode = .scaleToFill
        pageImageView.isUserInteractionEnabled = false
        pageImageView.layer.cornerRadius = 12
        pageImageView.clipsToBounds = true

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)

        view.addSubview(pageImageView)
        view.addSubview(canvasView)

        pageImage = PDFSignatureService.renderPageImage(sourceURL: fileURL, pageIndex: 0)
        pageImageView.image = pageImage
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureToolPicker()
        canvasView.becomeFirstResponder()
        updateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }

    func updateLayout() {
        guard let pageImage, pageImage.size.width > 0, pageImage.size.height > 0 else { return }

        let insets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let available = view.bounds.inset(by: insets)
        let scale = min(
            available.width / pageImage.size.width,
            available.height / pageImage.size.height
        )
        let size = CGSize(width: pageImage.size.width * scale, height: pageImage.size.height * scale)
        let origin = CGPoint(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2
        )
        let frame = CGRect(origin: origin, size: size)

        pageImageView.frame = frame
        canvasView.frame = frame
        onLayout?(canvasView.bounds)
    }

    private func configureToolPicker() {
        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvasView)
        picker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        toolPicker = picker
    }
}
