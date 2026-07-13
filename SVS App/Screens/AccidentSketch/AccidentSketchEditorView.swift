//
//  AccidentSketchEditorView.swift
//  SVS App
//

import PencilKit
import SwiftUI

struct AccidentSketchEditorView: View {
    let template: AccidentSketchTemplate
    let onDismiss: () -> Void

    @State private var activeTemplate: AccidentSketchTemplate
    @State private var vehicles: [AccidentSketchVehicle]
    @State private var selectedVehicleID: UUID?
    @State private var drawing = PKDrawing()
    @State private var drawingBounds: CGRect = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var exportedPDFURL: URL?
    @State private var participantLimitMessage: String?
    @State private var activeDrawingTool: AccidentSketchDrawingTool?
    @State private var showLabelEditor = false
    @State private var labelDraft = ""
    @State private var canUndoDrawing = false
    @State private var undoRequest = 0

    private var backgroundImage: UIImage {
        AccidentSketchRenderer.renderBackground(activeTemplate)
    }

    init(template: AccidentSketchTemplate, onDismiss: @escaping () -> Void) {
        self.template = template
        self.onDismiss = onDismiss
        _activeTemplate = State(initialValue: template)
        _vehicles = State(initialValue: AccidentSketchVehicleLayout.defaults(for: template))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editorActionBar

                AccidentSketchDrawingCanvas(
                    template: activeTemplate,
                    backgroundImage: backgroundImage,
                    activeDrawingTool: activeDrawingTool,
                    vehicles: $vehicles,
                    selectedVehicleID: $selectedVehicleID,
                    drawing: $drawing,
                    drawingBounds: $drawingBounds,
                    canUndoDrawing: $canUndoDrawing,
                    undoRequest: undoRequest
                )
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(activeTemplate.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        onDismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("PDF") {
                        exportPDF()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
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
        .sheet(isPresented: $showLabelEditor) {
            vehicleLabelEditorSheet
        }
    }

    private var vehicleLabelEditorSheet: some View {
        NavigationStack {
            Form {
                TextField("Kürzel (z. B. AS, UG)", text: $labelDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Section("Schnellauswahl") {
                    ForEach(AccidentSketchVehicleLabelPreset.allCases) { preset in
                        Button(preset.title) {
                            labelDraft = preset.rawValue
                        }
                    }
                }
            }
            .navigationTitle("Beschriftung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        showLabelEditor = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Übernehmen") {
                        applyLabelDraft()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var editorActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(AccidentSketchTemplate.allCases) { option in
                        Button {
                            switchTemplate(to: option)
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                        .disabled(option == activeTemplate)
                    }
                } label: {
                    actionChip(title: "Straße", systemImage: activeTemplate.systemImage)
                }
                .disabled(isSaving)

                Button {
                    addParticipant()
                } label: {
                    actionChip(title: "Auto", systemImage: "plus")
                }
                .disabled(isSaving || vehicles.count >= AccidentSketchVehicleLayout.maxParticipants)

                if let selectedVehicleID,
                   vehicles.contains(where: { $0.id == selectedVehicleID }) {
                    Button {
                        beginLabelEditing()
                    } label: {
                        actionChip(title: "Text", systemImage: "textformat")
                    }
                    .disabled(isSaving)

                    Button(role: .destructive) {
                        removeSelectedVehicle()
                    } label: {
                        actionChip(title: "Entfernen", systemImage: "trash", isDestructive: true)
                    }
                    .disabled(isSaving)
                }

                toolDivider

                ForEach(AccidentSketchDrawingTool.allCases) { tool in
                    Button {
                        toggleDrawingTool(tool)
                    } label: {
                        toolChip(tool: tool, isSelected: activeDrawingTool == tool)
                    }
                    .disabled(isSaving)
                }

                Button {
                    undoRequest += 1
                } label: {
                    actionChip(title: "Zurück", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndoDrawing || isSaving)

                Button(role: .destructive) {
                    drawing = PKDrawing()
                    canUndoDrawing = false
                } label: {
                    actionChip(title: "Alles löschen", systemImage: "trash", isDestructive: true)
                }
                .disabled(drawing.bounds.isEmpty || isSaving)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var toolDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 28)
    }

    private func toolChip(tool: AccidentSketchDrawingTool, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: tool.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tool == .eraser ? Color.secondary : Color(uiColor: tool.tintColor))
            Text(tool.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private func actionChip(
        title: String,
        systemImage: String,
        isDestructive: Bool = false
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
    }

    private func beginLabelEditing() {
        guard let selectedVehicleID,
              let vehicle = vehicles.first(where: { $0.id == selectedVehicleID }) else {
            return
        }
        labelDraft = vehicle.label
        showLabelEditor = true
    }

    private func applyLabelDraft() {
        guard let selectedVehicleID,
              let index = vehicles.firstIndex(where: { $0.id == selectedVehicleID }) else {
            showLabelEditor = false
            return
        }
        let trimmed = labelDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        vehicles[index].label = trimmed.isEmpty ? "\(vehicles[index].number)" : String(trimmed.prefix(6))
        showLabelEditor = false
    }

    private func toggleDrawingTool(_ tool: AccidentSketchDrawingTool) {
        if activeDrawingTool == tool {
            activeDrawingTool = nil
        } else {
            activeDrawingTool = tool
        }
    }

    private func switchTemplate(to template: AccidentSketchTemplate) {
        activeTemplate = template
        vehicles = AccidentSketchVehicleLayout.defaults(for: template)
        selectedVehicleID = nil
        drawing = PKDrawing()
    }

    private func addParticipant() {
        guard vehicles.count < AccidentSketchVehicleLayout.maxParticipants else {
            participantLimitMessage = "Maximal \(AccidentSketchVehicleLayout.maxParticipants) Fahrzeuge pro Skizze."
            return
        }

        let newVehicle = AccidentSketchVehicleLayout.additionalParticipant(after: vehicles)
        vehicles.append(newVehicle)
        selectedVehicleID = newVehicle.id
    }

    private func removeSelectedVehicle() {
        guard let selectedVehicleID,
              let index = vehicles.firstIndex(where: { $0.id == selectedVehicleID }) else {
            return
        }
        vehicles.remove(at: index)
        self.selectedVehicleID = nil
    }

    private func exportPDF() {
        isSaving = true

        _Concurrency.Task { @MainActor in
            defer { isSaving = false }

            do {
                let composite = AccidentSketchRenderer.renderExport(
                    template: activeTemplate,
                    vehicles: vehicles,
                    drawing: drawing,
                    drawingBounds: drawingBounds
                )
                let outputURL = try PDFSignatureService.sketchPDFURL(
                    backgroundImage: composite,
                    drawing: PKDrawing(),
                    drawingBounds: .zero,
                    outputBaseName: activeTemplate.outputBaseName
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

// MARK: - Canvas bridge

private struct AccidentSketchDrawingCanvas: UIViewControllerRepresentable {
    let template: AccidentSketchTemplate
    let backgroundImage: UIImage
    let activeDrawingTool: AccidentSketchDrawingTool?
    @Binding var vehicles: [AccidentSketchVehicle]
    @Binding var selectedVehicleID: UUID?
    @Binding var drawing: PKDrawing
    @Binding var drawingBounds: CGRect
    @Binding var canUndoDrawing: Bool
    let undoRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            vehicles: $vehicles,
            selectedVehicleID: $selectedVehicleID,
            drawing: $drawing,
            drawingBounds: $drawingBounds,
            canUndoDrawing: $canUndoDrawing
        )
    }

    func makeUIViewController(context: Context) -> AccidentSketchCanvasViewController {
        let controller = AccidentSketchCanvasViewController(
            backgroundImage: backgroundImage,
            vehicles: vehicles,
            templateID: template.rawValue
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
        if uiViewController.templateID != template.rawValue {
            uiViewController.setBackgroundImage(backgroundImage, templateID: template.rawValue)
        }
        if uiViewController.canvasView.drawing != drawing {
            uiViewController.canvasView.drawing = drawing
        }
        uiViewController.setDrawingTool(activeDrawingTool)
        uiViewController.setSelectedVehicleID(selectedVehicleID)
        uiViewController.updateVehicles(vehicles)
        uiViewController.updateLayout()

        if context.coordinator.lastUndoRequest != undoRequest {
            context.coordinator.lastUndoRequest = undoRequest
            uiViewController.undoLastStroke()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var vehicles: [AccidentSketchVehicle]
        @Binding var selectedVehicleID: UUID?
        @Binding var drawing: PKDrawing
        @Binding var drawingBounds: CGRect
        @Binding var canUndoDrawing: Bool
        var lastUndoRequest = 0

        init(
            vehicles: Binding<[AccidentSketchVehicle]>,
            selectedVehicleID: Binding<UUID?>,
            drawing: Binding<PKDrawing>,
            drawingBounds: Binding<CGRect>,
            canUndoDrawing: Binding<Bool>
        ) {
            _vehicles = vehicles
            _selectedVehicleID = selectedVehicleID
            _drawing = drawing
            _drawingBounds = drawingBounds
            _canUndoDrawing = canUndoDrawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
            drawingBounds = canvasView.bounds
            canUndoDrawing = canvasView.undoManager?.canUndo ?? false
        }
    }
}

// MARK: - Vehicle overlay

private final class AccidentSketchPassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() {
            let converted = convert(point, to: subview)
            if let hit = subview.hitTest(converted, with: event) {
                return hit
            }
        }
        return nil
    }
}

private final class AccidentSketchVehicleHostView: UIView, UIGestureRecognizerDelegate {
    let vehicleID: UUID
    private let imageView = UIImageView()
    private var vehicle: AccidentSketchVehicle
    private let canvasScale: () -> CGFloat
    private let onMoved: (UUID, CGPoint) -> Void
    private let onRotated: (UUID, CGFloat) -> Void
    private let onSelected: (UUID) -> Void
    private var angleAtRotationStart: CGFloat = 0

    init(
        vehicle: AccidentSketchVehicle,
        canvasScale: @escaping () -> CGFloat,
        onMoved: @escaping (UUID, CGPoint) -> Void,
        onRotated: @escaping (UUID, CGFloat) -> Void,
        onSelected: @escaping (UUID) -> Void
    ) {
        self.vehicleID = vehicle.id
        self.vehicle = vehicle
        self.canvasScale = canvasScale
        self.onMoved = onMoved
        self.onRotated = onRotated
        self.onSelected = onSelected
        super.init(frame: .zero)
        isUserInteractionEnabled = true

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        addGestureRecognizer(rotation)

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
            || self.vehicle.label != vehicle.label
            || self.vehicle.size != vehicle.size
            || abs(self.vehicle.angle - vehicle.angle) > 0.001
        self.vehicle = vehicle
        if needsImageRefresh {
            refreshImage()
        }
        applyLayout()
        layer.borderWidth = isSelected ? 2.5 : 0
        layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : nil
        layer.cornerRadius = isSelected ? 10 : 0
        layer.shadowColor = isSelected ? UIColor.systemBlue.cgColor : nil
        layer.shadowOpacity = isSelected ? 0.25 : 0
        layer.shadowRadius = isSelected ? 6 : 0
        layer.shadowOffset = .zero
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
        transform = CGAffineTransform(rotationAngle: 0)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
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

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            angleAtRotationStart = vehicle.angle
            onSelected(vehicleID)
        case .changed:
            onRotated(vehicleID, angleAtRotationStart + recognizer.rotation)
        default:
            break
        }
    }
}

// MARK: - Canvas controller

private final class AccidentSketchCanvasViewController: UIViewController {
    private(set) var backgroundImage: UIImage
    private(set) var templateID: String

    var onVehiclesChanged: (([AccidentSketchVehicle]) -> Void)?
    var onVehicleSelected: ((UUID?) -> Void)?
    var onLayout: ((CGRect) -> Void)?

    private let canvasContainer = UIView()
    private let pageImageView = UIImageView()
    private let vehiclesContainer = AccidentSketchPassThroughView()
    let canvasView = PKCanvasView()
    private var vehicleViews: [UUID: AccidentSketchVehicleHostView] = [:]
    private var vehicles: [AccidentSketchVehicle]
    private var selectedVehicleID: UUID?
    private var activeDrawingTool: AccidentSketchDrawingTool?
    private var canvasScale: CGFloat = 1

    init(backgroundImage: UIImage, vehicles: [AccidentSketchVehicle], templateID: String = "") {
        self.backgroundImage = backgroundImage
        self.templateID = templateID
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

        canvasContainer.backgroundColor = .clear

        pageImageView.contentMode = .scaleToFill
        pageImageView.isUserInteractionEnabled = false
        pageImageView.layer.cornerRadius = 10
        pageImageView.clipsToBounds = true
        pageImageView.image = backgroundImage

        vehiclesContainer.backgroundColor = .clear
        vehiclesContainer.clipsToBounds = false

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput

        canvasContainer.addSubview(pageImageView)
        canvasContainer.addSubview(canvasView)
        canvasContainer.addSubview(vehiclesContainer)
        view.addSubview(canvasContainer)

        rebuildVehicleViews()
    }

    func setBackgroundImage(_ image: UIImage, templateID: String) {
        backgroundImage = image
        self.templateID = templateID
        pageImageView.image = image
        updateLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateLayout()
    }

    func setDrawingTool(_ tool: AccidentSketchDrawingTool?) {
        activeDrawingTool = tool
        if let tool {
            canvasView.isUserInteractionEnabled = true
            canvasView.tool = tool.makeTool()
        } else {
            canvasView.isUserInteractionEnabled = false
        }
    }

    func undoLastStroke() {
        canvasView.undoManager?.undo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
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
    }

    func updateLayout() {
        guard backgroundImage.size.width > 0, backgroundImage.size.height > 0 else { return }

        let insets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let available = view.bounds.inset(by: insets)
        let fitScale = min(
            available.width / backgroundImage.size.width,
            available.height / backgroundImage.size.height
        )
        let fittedSize = CGSize(
            width: backgroundImage.size.width * fitScale,
            height: backgroundImage.size.height * fitScale
        )
        let origin = CGPoint(
            x: available.minX + (available.width - fittedSize.width) / 2,
            y: available.minY + (available.height - fittedSize.height) / 2
        )
        let sceneFrame = CGRect(origin: origin, size: fittedSize)

        canvasContainer.frame = view.bounds
        pageImageView.frame = sceneFrame
        canvasView.frame = sceneFrame
        vehiclesContainer.frame = sceneFrame

        canvasScale = fitScale
        onLayout?(canvasView.bounds)

        refreshVehiclePositions()
    }

    private func refreshVehiclePositions() {
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
                canvasScale: { [weak self] in
                    guard let self else { return 1 }
                    return self.canvasScale
                },
                onMoved: { [weak self] id, center in
                    self?.moveVehicle(id: id, to: center)
                },
                onRotated: { [weak self] id, angle in
                    self?.rotateVehicle(id: id, to: angle)
                },
                onSelected: { [weak self] id in
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

    private func rotateVehicle(id: UUID, to angle: CGFloat) {
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else { return }
        vehicles[index].angle = angle
        vehicleViews[id]?.update(
            vehicle: vehicles[index],
            isSelected: vehicles[index].id == selectedVehicleID
        )
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
}
