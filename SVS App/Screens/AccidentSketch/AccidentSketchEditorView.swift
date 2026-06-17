//
//  AccidentSketchEditorView.swift
//  SVS App
//

import PencilKit
import SwiftUI

struct AccidentSketchEditorView: View {
    let template: AccidentSketchTemplate
    let onDismiss: () -> Void

    @State private var vehicles: [AccidentSketchVehicle]
    @State private var editMode: AccidentSketchEditMode = .vehicles
    @State private var selectedVehicleID: UUID?
    @State private var drawing = PKDrawing()
    @State private var drawingBounds: CGRect = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var exportedPDFURL: URL?
    @State private var participantLimitMessage: String?

    private var backgroundImage: UIImage {
        AccidentSketchRenderer.renderBackground(template)
    }

    init(template: AccidentSketchTemplate, onDismiss: @escaping () -> Void) {
        self.template = template
        self.onDismiss = onDismiss
        let defaults = AccidentSketchVehicleLayout.defaults(for: template)
        _vehicles = State(initialValue: defaults)
        if template == .freeCanvas {
            _editMode = State(initialValue: .vehicles)
        } else {
            _editMode = State(initialValue: defaults.isEmpty ? .draw : .vehicles)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                AccidentSketchDrawingCanvas(
                    template: template,
                    backgroundImage: backgroundImage,
                    vehicles: $vehicles,
                    editMode: $editMode,
                    selectedVehicleID: $selectedVehicleID,
                    drawing: $drawing,
                    drawingBounds: $drawingBounds
                )
            }
            .navigationTitle(template.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        onDismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .principal) {
                    Picker("Modus", selection: $editMode) {
                        ForEach(AccidentSketchEditMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("PDF erstellen") {
                        exportPDF()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        addParticipant()
                    } label: {
                        Label("1 Fahrzeug", systemImage: "plus")
                    }
                    .disabled(isSaving || vehicles.count >= AccidentSketchVehicleLayout.maxParticipants)

                    if editMode == .draw {
                        Button("Zeichnung löschen", role: .destructive) {
                            drawing = PKDrawing()
                        }
                        .disabled(drawing.bounds.isEmpty || isSaving)
                    } else if let selectedVehicleID,
                              vehicles.contains(where: { $0.id == selectedVehicleID }) {
                        Button("Entfernen", role: .destructive) {
                            removeSelectedVehicle()
                        }
                        .disabled(isSaving)

                        Button("90° drehen") {
                            rotateSelectedVehicle()
                        }
                        .disabled(isSaving)
                    }

                    Spacer()
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView("PDF wird erstellt …")
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
        .onChange(of: editMode) { _, newMode in
            if newMode == .draw {
                selectedVehicleID = nil
            }
        }
        .alert(
            "Export fehlgeschlagen",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Hinweis",
            isPresented: Binding(
                get: { participantLimitMessage != nil },
                set: { if !$0 { participantLimitMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { participantLimitMessage = nil }
        } message: {
            Text(participantLimitMessage ?? "")
        }
        .sheet(item: Binding(
            get: { exportedPDFURL.map(IdentifiableURL.init) },
            set: { exportedPDFURL = $0?.url }
        )) { item in
            AccidentSketchExportSheet(
                pdfURL: item.url,
                onDone: {
                    exportedPDFURL = nil
                    onDismiss()
                }
            )
        }
    }

    private func addParticipant() {
        guard vehicles.count < AccidentSketchVehicleLayout.maxParticipants else {
            participantLimitMessage = "Maximal \(AccidentSketchVehicleLayout.maxParticipants) Fahrzeuge pro Skizze."
            return
        }

        let newVehicle = AccidentSketchVehicleLayout.additionalParticipant(after: vehicles)
        vehicles.append(newVehicle)
        selectedVehicleID = newVehicle.id
        editMode = .vehicles
    }

    private func removeSelectedVehicle() {
        guard let selectedVehicleID,
              let index = vehicles.firstIndex(where: { $0.id == selectedVehicleID }) else {
            return
        }
        vehicles.remove(at: index)
        self.selectedVehicleID = nil
        if vehicles.isEmpty && template != .freeCanvas {
            editMode = .draw
        }
    }

    private func rotateSelectedVehicle() {
        guard let selectedVehicleID,
              let index = vehicles.firstIndex(where: { $0.id == selectedVehicleID }) else {
            return
        }
        vehicles[index] = vehicles[index].rotated90Degrees()
    }

    private func exportPDF() {
        isSaving = true

        _Concurrency.Task { @MainActor in
            defer { isSaving = false }

            do {
                let composite = AccidentSketchRenderer.renderExport(
                    template: template,
                    vehicles: vehicles,
                    drawing: drawing,
                    drawingBounds: drawingBounds
                )
                let outputURL = try PDFSignatureService.sketchPDFURL(
                    backgroundImage: composite,
                    drawing: PKDrawing(),
                    drawingBounds: .zero,
                    outputBaseName: template.outputBaseName
                )
                exportedPDFURL = outputURL
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct AccidentSketchExportSheet: View {
    let pdfURL: URL
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                Text("Schadenhergang als PDF bereit")
                    .font(.title3.weight(.semibold))

                Text("Teile die Skizze per AirDrop, Mail oder speichere sie in Dateien.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                ShareLink(item: pdfURL) {
                    Label("PDF teilen", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Fertig")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct AccidentSketchDrawingCanvas: UIViewControllerRepresentable {
    let template: AccidentSketchTemplate
    let backgroundImage: UIImage
    @Binding var vehicles: [AccidentSketchVehicle]
    @Binding var editMode: AccidentSketchEditMode
    @Binding var selectedVehicleID: UUID?
    @Binding var drawing: PKDrawing
    @Binding var drawingBounds: CGRect

    func makeCoordinator() -> Coordinator {
        Coordinator(
            vehicles: $vehicles,
            editMode: $editMode,
            selectedVehicleID: $selectedVehicleID,
            drawing: $drawing,
            drawingBounds: $drawingBounds
        )
    }

    func makeUIViewController(context: Context) -> AccidentSketchCanvasViewController {
        let controller = AccidentSketchCanvasViewController(
            template: template,
            backgroundImage: backgroundImage,
            vehicles: vehicles
        )
        controller.canvasView.delegate = context.coordinator
        controller.onVehiclesChanged = { updated in
            context.coordinator.vehicles = updated
        }
        controller.onVehicleSelected = { id in
            context.coordinator.selectedVehicleID = id
        }
        controller.onLayout = { bounds in
            context.coordinator.drawingBounds = bounds
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: AccidentSketchCanvasViewController, context: Context) {
        if uiViewController.canvasView.drawing != drawing {
            uiViewController.canvasView.drawing = drawing
        }
        uiViewController.setEditMode(editMode)
        uiViewController.setSelectedVehicleID(selectedVehicleID)
        uiViewController.updateVehicles(vehicles)
        uiViewController.updateLayout()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var vehicles: [AccidentSketchVehicle]
        @Binding var editMode: AccidentSketchEditMode
        @Binding var selectedVehicleID: UUID?
        @Binding var drawing: PKDrawing
        @Binding var drawingBounds: CGRect

        init(
            vehicles: Binding<[AccidentSketchVehicle]>,
            editMode: Binding<AccidentSketchEditMode>,
            selectedVehicleID: Binding<UUID?>,
            drawing: Binding<PKDrawing>,
            drawingBounds: Binding<CGRect>
        ) {
            _vehicles = vehicles
            _editMode = editMode
            _selectedVehicleID = selectedVehicleID
            _drawing = drawing
            _drawingBounds = drawingBounds
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
            drawingBounds = canvasView.bounds
        }
    }
}

private final class AccidentSketchVehicleHostView: UIView {
    let vehicleID: UUID
    private let imageView = UIImageView()
    private var vehicle: AccidentSketchVehicle
    private let canvasScale: () -> CGFloat
    private let onMoved: (UUID, CGPoint) -> Void
    private let onSelected: (UUID) -> Void

    init(
        vehicle: AccidentSketchVehicle,
        canvasScale: @escaping () -> CGFloat,
        onMoved: @escaping (UUID, CGPoint) -> Void,
        onSelected: @escaping (UUID) -> Void
    ) {
        self.vehicleID = vehicle.id
        self.vehicle = vehicle
        self.canvasScale = canvasScale
        self.onMoved = onMoved
        self.onSelected = onSelected
        super.init(frame: .zero)
        isUserInteractionEnabled = true

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        refreshImage()
        applyLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(vehicle: AccidentSketchVehicle, isSelected: Bool) {
        let needsImageRefresh = self.vehicle.number != vehicle.number
            || self.vehicle.size != vehicle.size
            || abs(self.vehicle.angle - vehicle.angle) > 0.001
        self.vehicle = vehicle
        if needsImageRefresh {
            refreshImage()
        }
        applyLayout()
        layer.borderWidth = isSelected ? 2 : 0
        layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : nil
        layer.cornerRadius = isSelected ? 8 : 0
    }

    private func refreshImage() {
        imageView.image = AccidentSketchRenderer.renderVehicleImage(vehicle)
    }

    private func applyLayout() {
        let scale = canvasScale()
        let hostSize = AccidentSketchRenderer.vehicleHostSize(for: vehicle)
        bounds = CGRect(
            origin: .zero,
            size: CGSize(width: hostSize.width * scale, height: hostSize.height * scale)
        )
        imageView.frame = bounds
        center = CGPoint(x: vehicle.center.x * scale, y: vehicle.center.y * scale)
    }

    @objc private func handleTap() {
        onSelected(vehicleID)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let scale = canvasScale()
        guard scale > 0 else { return }

        let translation = recognizer.translation(in: superview)
        recognizer.setTranslation(.zero, in: superview)

        let newCenter = CGPoint(
            x: center.x + translation.x,
            y: center.y + translation.y
        )
        center = newCenter
        onMoved(vehicleID, CGPoint(x: newCenter.x / scale, y: newCenter.y / scale))
    }
}

private final class AccidentSketchCanvasViewController: UIViewController {
    let template: AccidentSketchTemplate
    let backgroundImage: UIImage

    var onVehiclesChanged: (([AccidentSketchVehicle]) -> Void)?
    var onVehicleSelected: ((UUID?) -> Void)?
    var onLayout: ((CGRect) -> Void)?

    private let pageImageView = UIImageView()
    private let vehiclesContainer = UIView()
    let canvasView = PKCanvasView()
    private var toolPicker: PKToolPicker?
    private var vehicleViews: [UUID: AccidentSketchVehicleHostView] = [:]
    private var vehicles: [AccidentSketchVehicle]
    private var editMode: AccidentSketchEditMode = .vehicles
    private var selectedVehicleID: UUID?
    private var canvasFrame: CGRect = .zero
    private var canvasScale: CGFloat = 1

    init(template: AccidentSketchTemplate, backgroundImage: UIImage, vehicles: [AccidentSketchVehicle]) {
        self.template = template
        self.backgroundImage = backgroundImage
        self.vehicles = vehicles
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
        pageImageView.image = backgroundImage

        vehiclesContainer.backgroundColor = .clear
        vehiclesContainer.isUserInteractionEnabled = true
        vehiclesContainer.clipsToBounds = false

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)

        view.addSubview(pageImageView)
        view.addSubview(vehiclesContainer)
        view.addSubview(canvasView)

        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        backgroundTap.cancelsTouchesInView = false
        vehiclesContainer.addGestureRecognizer(backgroundTap)

        rebuildVehicleViews()
        applyEditMode()
    }

    @objc private func handleBackgroundTap() {
        guard editMode == .vehicles else { return }
        selectedVehicleID = nil
        onVehicleSelected?(nil)
        refreshVehicleSelection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureToolPicker()
        updateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }

    func setEditMode(_ mode: AccidentSketchEditMode) {
        guard editMode != mode else { return }
        editMode = mode
        if mode == .draw {
            selectedVehicleID = nil
            onVehicleSelected?(nil)
        }
        applyEditMode()
        refreshVehicleSelection()
    }

    func setSelectedVehicleID(_ id: UUID?) {
        guard selectedVehicleID != id else { return }
        selectedVehicleID = id
        refreshVehicleSelection()
    }

    func updateVehicles(_ updated: [AccidentSketchVehicle]) {
        vehicles = updated
        for vehicle in updated {
            vehicleViews[vehicle.id]?.update(
                vehicle: vehicle,
                isSelected: vehicle.id == selectedVehicleID
            )
        }
        let ids = Set(updated.map(\.id))
        for (id, host) in vehicleViews where !ids.contains(id) {
            host.removeFromSuperview()
            vehicleViews.removeValue(forKey: id)
        }
        if updated.count > vehicleViews.count {
            rebuildVehicleViews()
        }
        applyEditMode()
    }

    func updateLayout() {
        guard backgroundImage.size.width > 0, backgroundImage.size.height > 0 else { return }

        let insets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let available = view.bounds.inset(by: insets)
        let scale = min(
            available.width / backgroundImage.size.width,
            available.height / backgroundImage.size.height
        )
        let size = CGSize(
            width: backgroundImage.size.width * scale,
            height: backgroundImage.size.height * scale
        )
        let origin = CGPoint(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2
        )
        let frame = CGRect(origin: origin, size: size)

        pageImageView.frame = frame
        vehiclesContainer.frame = frame
        canvasView.frame = frame
        canvasFrame = frame
        canvasScale = scale
        onLayout?(canvasView.bounds)

        for vehicle in vehicles {
            vehicleViews[vehicle.id]?.update(
                vehicle: vehicle,
                isSelected: vehicle.id == selectedVehicleID
            )
        }
    }

    private func rebuildVehicleViews() {
        vehicleViews.values.forEach { $0.removeFromSuperview() }
        vehicleViews.removeAll()

        for vehicle in vehicles {
            let host = AccidentSketchVehicleHostView(
                vehicle: vehicle,
                canvasScale: { [weak self] in self?.canvasScale ?? 1 },
                onMoved: { [weak self] id, center in
                    self?.moveVehicle(id: id, to: center)
                },
                onSelected: { [weak self] id in
                    guard self?.editMode == .vehicles else { return }
                    self?.selectedVehicleID = id
                    self?.onVehicleSelected?(id)
                    self?.refreshVehicleSelection()
                }
            )
            vehiclesContainer.addSubview(host)
            vehicleViews[vehicle.id] = host
            host.update(vehicle: vehicle, isSelected: vehicle.id == selectedVehicleID)
        }
    }

    private func moveVehicle(id: UUID, to center: CGPoint) {
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else { return }
        let drawingRect = AccidentSketchMetrics.drawingRect
        let clamped = CGPoint(
            x: min(max(center.x, drawingRect.minX), drawingRect.maxX),
            y: min(max(center.y, drawingRect.minY), drawingRect.maxY)
        )
        vehicles[index].center = clamped
        onVehiclesChanged?(vehicles)
    }

    private func refreshVehicleSelection() {
        for vehicle in vehicles {
            vehicleViews[vehicle.id]?.update(
                vehicle: vehicle,
                isSelected: vehicle.id == selectedVehicleID
            )
        }
    }

    private func applyEditMode() {
        let vehicleMode = editMode == .vehicles
        vehiclesContainer.isUserInteractionEnabled = vehicleMode && !vehicles.isEmpty
        canvasView.isUserInteractionEnabled = editMode == .draw

        if editMode == .draw {
            canvasView.becomeFirstResponder()
            toolPicker?.setVisible(true, forFirstResponder: canvasView)
        } else {
            toolPicker?.setVisible(false, forFirstResponder: canvasView)
            canvasView.resignFirstResponder()
        }
    }

    private func configureToolPicker() {
        let picker = PKToolPicker()
        picker.addObserver(canvasView)
        toolPicker = picker
        if editMode == .draw {
            picker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }
    }
}
