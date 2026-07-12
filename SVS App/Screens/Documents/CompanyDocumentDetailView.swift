//
//  CompanyDocumentDetailView.swift
//  SVS App
//

import SwiftUI

struct CompanyDocumentDetailView: View {
    let document: CompanyDocument
    let fileURL: URL

    @State private var signedPDFURL: URL?
    @State private var showSignatureFlow = false
    @State private var showDirectDrawing = false
    @State private var showRemoteSigning = false
    @State private var showFormFunnel = false
    @State private var isSigning = false
    @State private var signErrorMessage: String?

    private var activePDFURL: URL {
        signedPDFURL ?? fileURL
    }

    private var isShowingSignedVersion: Bool {
        signedPDFURL != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if isShowingSignedVersion {
                signedBanner
            }

            PDFPreview(url: activePDFURL)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if document.supportsFormFunnel {
                    Button {
                        showFormFunnel = true
                    } label: {
                        Label("Ausfüllen", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(isSigning)
                }

                if document.supportsRemoteSigning {
                    Button {
                        showRemoteSigning = true
                    } label: {
                        Label("Kundenlink", systemImage: "link")
                    }
                    .disabled(isSigning)
                }

                if document.usesDirectPDFDrawing {
                    Button {
                        showDirectDrawing = true
                    } label: {
                        Label("Zeichnen", systemImage: "pencil.tip.crop.circle")
                    }
                    .disabled(isSigning)
                } else {
                    Button {
                        showSignatureFlow = true
                    } label: {
                        Label("Unterschreiben", systemImage: "signature")
                    }
                    .disabled(isSigning)
                }

                ShareLink(item: activePDFURL) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fullScreenCover(isPresented: $showFormFunnel) {
            AbtretungserklaerungFunnelView(sourcePDFURL: fileURL)
        }
        .interactiveDismissDisabled(showFormFunnel)
        .fullScreenCover(isPresented: $showRemoteSigning) {
            DocumentRemoteSigningSheet(document: document, sourcePDFURL: fileURL)
        }
        .fullScreenCover(isPresented: $showDirectDrawing) {
            CompanyDocumentDirectDrawingView(
                fileURL: fileURL,
                outputBaseName: document.resourceName,
                onCancel: { showDirectDrawing = false },
                onComplete: { url in
                    persistSignedPDF(url)
                    showDirectDrawing = false
                }
            )
        }
        .fullScreenCover(isPresented: $showSignatureFlow) {
            CompanyDocumentSignatureFlow(
                documentTitle: document.title,
                fileURL: fileURL,
                textFields: document.textFields,
                inkFields: document.inkFields,
                inkOnDrawStep: document.inkFieldsOnDrawStep,
                defaultPlacement: document.signaturePlacement,
                isProcessing: isSigning,
                onCancel: { showSignatureFlow = false },
                onApply: { image, signaturePlacement, textOverlays, inkOverlays in
                    applySignature(
                        image,
                        signaturePlacement: signaturePlacement,
                        textOverlays: textOverlays,
                        inkOverlays: inkOverlays
                    )
                }
            )
        }
        .alert(
            "Unterschrift fehlgeschlagen",
            isPresented: Binding(
                get: { signErrorMessage != nil },
                set: { if !$0 { signErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { signErrorMessage = nil }
        } message: {
            Text(signErrorMessage ?? "")
        }
        .overlay {
            if isSigning {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("PDF wird signiert …")
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
    }

    private var signedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.usesDirectPDFDrawing ? "Bearbeitete Version" : "Signierte Version")
                    .font(.subheadline.weight(.semibold))
                Text(
                    document.usesDirectPDFDrawing
                        ? "Du kannst das Dokument jetzt teilen oder erneut bearbeiten."
                        : "Du kannst das Dokument jetzt teilen oder erneut unterschreiben."
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Button("Original") {
                signedPDFURL = nil
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private func applySignature(
        _ image: UIImage,
        signaturePlacement: PDFSignaturePlacement,
        textOverlays: [PDFTextOverlay],
        inkOverlays: [PDFInkOverlay]
    ) {
        isSigning = true

        _Concurrency.Task { @MainActor in
            defer { isSigning = false }

            do {
                let outputURL = try PDFSignatureService.signedPDFURL(
                    sourceURL: fileURL,
                    signature: image,
                    signaturePlacement: signaturePlacement,
                    textOverlays: textOverlays,
                    inkOverlays: inkOverlays,
                    outputBaseName: document.resourceName
                )
                let label = textOverlays
                    .map(\.text)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
                persistSignedPDF(outputURL, label: label)
                showSignatureFlow = false
            } catch {
                signErrorMessage = error.localizedDescription
            }
        }
    }

    private func persistSignedPDF(_ url: URL, label: String? = nil) {
        do {
            let record = try LocalSignedDocumentArchive.archive(
                pdfAt: url,
                document: document,
                label: label
            )
            signedPDFURL = LocalSignedDocumentArchive.pdfURL(for: record) ?? url
        } catch {
            signedPDFURL = url
        }
    }
}

private struct DocumentTextFieldState: Identifiable {
    let field: CompanyDocumentTextField
    var date: Date
    var customText: String
    var secondaryText: String
    var placement: NormalizedTextPlacement

    var id: String { field.id }

    var renderedText: String {
        field.renderedText(date: date, customText: customText, secondaryText: secondaryText)
    }
}

private struct DocumentInkFieldState: Identifiable {
    let field: CompanyDocumentInkField
    var image: UIImage?
    var placement: NormalizedSignaturePlacement

    var id: String { field.id }
}

private struct CompanyDocumentSignatureFlow: View {
    private enum Step {
        case draw
        case fields
        case place
    }

    let documentTitle: String
    let fileURL: URL
    let textFields: [CompanyDocumentTextField]
    let inkFields: [CompanyDocumentInkField]
    let inkOnDrawStep: Bool
    let defaultPlacement: PDFSignaturePlacement
    let isProcessing: Bool
    let onCancel: () -> Void
    let onApply: (UIImage, PDFSignaturePlacement, [PDFTextOverlay], [PDFInkOverlay]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .draw
    @State private var signatureImage: UIImage?
    @State private var placement: NormalizedSignaturePlacement
    @State private var fieldStates: [DocumentTextFieldState]
    @State private var inkStates: [DocumentInkFieldState]

    private var hasDetailsStep: Bool {
        !textFields.isEmpty || (!inkFields.isEmpty && !inkOnDrawStep)
    }

    init(
        documentTitle: String,
        fileURL: URL,
        textFields: [CompanyDocumentTextField],
        inkFields: [CompanyDocumentInkField],
        inkOnDrawStep: Bool = false,
        defaultPlacement: PDFSignaturePlacement,
        isProcessing: Bool,
        onCancel: @escaping () -> Void,
        onApply: @escaping (UIImage, PDFSignaturePlacement, [PDFTextOverlay], [PDFInkOverlay]) -> Void
    ) {
        self.documentTitle = documentTitle
        self.fileURL = fileURL
        self.textFields = textFields
        self.inkFields = inkFields
        self.inkOnDrawStep = inkOnDrawStep
        self.defaultPlacement = defaultPlacement
        self.isProcessing = isProcessing
        self.onCancel = onCancel
        self.onApply = onApply
        _placement = State(initialValue: NormalizedSignaturePlacement(from: defaultPlacement))
        _fieldStates = State(
            initialValue: textFields.map { field in
                DocumentTextFieldState(
                    field: field,
                    date: Date(),
                    customText: "",
                    secondaryText: "",
                    placement: NormalizedTextPlacement(from: field.defaultPlacement)
                )
            }
        )
        _inkStates = State(
            initialValue: inkFields.map { field in
                DocumentInkFieldState(
                    field: field,
                    image: nil,
                    placement: NormalizedSignaturePlacement(from: field.defaultPlacement)
                )
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .draw:
                    drawStep
                case .fields:
                    fieldsStep
                case .place:
                    if let signatureImage {
                        CompanyDocumentPlacementView(
                            fileURL: fileURL,
                            pageIndex: defaultPlacement.pageIndex,
                            signatureImage: signatureImage,
                            signaturePlacement: $placement,
                            fieldStates: $fieldStates,
                            inkStates: $inkStates
                        )
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(step == .draw ? "Abbrechen" : "Zurück") {
                        switch step {
                        case .draw:
                            onCancel()
                            dismiss()
                        case .fields:
                            step = .draw
                        case .place:
                            step = .fields
                        }
                    }
                    .disabled(isProcessing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    switch step {
                    case .draw:
                        Button("Weiter") {
                            step = hasDetailsStep ? .fields : .place
                        }
                        .fontWeight(.semibold)
                        .disabled(signatureImage == nil || isProcessing)
                    case .fields:
                        Button("Weiter") {
                            step = .place
                        }
                        .fontWeight(.semibold)
                        .disabled(isProcessing)
                    case .place:
                        Button("Übernehmen") {
                            guard let signatureImage else { return }
                            let overlays = fieldStates.compactMap { state -> PDFTextOverlay? in
                                let text = state.renderedText
                                guard !text.isEmpty else { return nil }
                                return PDFTextOverlay(
                                    text: text,
                                    placement: state.placement.pdfPlacement(
                                        pageIndex: state.field.defaultPlacement.pageIndex
                                    )
                                )
                            }
                            let inks = inkStates.compactMap { state -> PDFInkOverlay? in
                                guard let image = state.image else { return nil }
                                return PDFInkOverlay(
                                    image: image,
                                    placement: state.placement.pdfPlacement(
                                        pageIndex: state.field.defaultPlacement.pageIndex
                                    )
                                )
                            }
                            onApply(
                                signatureImage,
                                placement.pdfPlacement(pageIndex: defaultPlacement.pageIndex),
                                overlays,
                                inks
                            )
                        }
                        .fontWeight(.semibold)
                        .disabled(isProcessing)
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var navigationTitle: String {
        switch step {
        case .draw:
            return "Unterschreiben"
        case .fields:
            return "Angaben"
        case .place:
            return "Position wählen"
        }
    }

    private var drawStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unterschrift für „\(documentTitle)“")
                    .font(.title3.weight(.semibold))

                Text(drawStepFooter)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            SignaturePadView(
                signatureImage: $signatureImage,
                canvasHeight: 220,
                locksParentScrolling: true
            )

            if inkOnDrawStep, !inkStates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional zeichnen")
                        .font(.subheadline.weight(.semibold))

                    ForEach($inkStates) { $state in
                        SignaturePadView(
                            signatureImage: $state.image,
                            canvasHeight: 160,
                            locksParentScrolling: true,
                            prompt: "Mit dem Finger zeichnen – z. B. auf dem Formular.",
                            emptyLabel: "Noch leer",
                            capturedLabel: "Erfasst"
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }

    private var drawStepFooter: String {
        if inkOnDrawStep {
            return "Unterschreibe in schwarz. Optional kannst du darunter mit dem Stift zeichnen. Danach gibst du das Datum ein."
        }
        if !inkFields.isEmpty {
            return "Unterschreibe in schwarz. Danach kannst du weitere Einträge handschriftlich erfassen."
        }
        return "Unterschreibe in schwarz im Feld unten. Danach trägst du die Angaben für das PDF ein."
    }

    private var fieldsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !inkOnDrawStep, !inkStates.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Handschriftliche Einträge")
                            .font(.headline)

                        ForEach($inkStates) { $state in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(state.field.label)
                                    .font(.subheadline.weight(.semibold))

                                SignaturePadView(
                                    signatureImage: $state.image,
                                    canvasHeight: 140,
                                    locksParentScrolling: true,
                                    prompt: "Mit dem Finger schreiben oder zeichnen.",
                                    emptyLabel: "Noch leer",
                                    capturedLabel: "Erfasst"
                                )
                            }
                        }
                    }
                }

                if !fieldStates.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Eingetippte Angaben")
                            .font(.headline)

                        ForEach($fieldStates) { $state in
                            VStack(alignment: .leading, spacing: 8) {
                                if state.field.isDateField {
                                    DatePicker(
                                        state.field.label,
                                        selection: $state.date,
                                        displayedComponents: .date
                                    )
                                    .environment(\.locale, Locale(identifier: "de_DE"))
                                } else if state.field.isPartyPair {
                                    Text(state.field.label)
                                        .font(.subheadline.weight(.semibold))

                                    TextField(
                                        "Kunde",
                                        text: $state.customText,
                                        prompt: Text("Nachname des Kunden")
                                    )
                                    .textFieldStyle(.roundedBorder)

                                    TextField(
                                        "Gegner",
                                        text: $state.secondaryText,
                                        prompt: Text("Versicherung oder Kennzeichen")
                                    )
                                    .textFieldStyle(.roundedBorder)
                                } else {
                                    TextField(
                                        state.field.label,
                                        text: $state.customText,
                                        prompt: state.field.freeTextPlaceholder.map { Text($0) },
                                        axis: .vertical
                                    )
                                    .lineLimit(1...3)
                                    .textFieldStyle(.roundedBorder)
                                }

                                if !state.renderedText.isEmpty {
                                    Text(state.renderedText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if state.field.isPartyPair || state.field.freeTextPlaceholder != nil {
                                    Text("Optional – leer lassen, wenn nicht benötigt.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Text(fieldsStepFooter)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var fieldsStepFooter: String {
        if inkOnDrawStep {
            return "Das Datum wird im Format TT.MM.JJJJ auf das Dokument gesetzt. Im nächsten Schritt legst du alles auf dem PDF fest."
        }
        if !inkFields.isEmpty {
            return "Leere Zeichenfelder werden übersprungen. Im nächsten Schritt legst du alles auf dem PDF fest."
        }
        if textFields.contains(where: { $0.id == "case-matter" }) {
            return "„In Sachen“: Kunde und Gegner werden zu „Kunde ./. Gegner“ zusammengesetzt. Optional. Darunter Unfalldatum und Datum."
        }
        return "Das Datum wird im Format TT.MM.JJJJ auf das Dokument gesetzt. Bei Anwaltsvollmachten erscheint zusätzlich „Verkehrsunfall vom …“."
    }
}

private struct CompanyDocumentPlacementView: View {
    let fileURL: URL
    let pageIndex: Int
    let signatureImage: UIImage
    @Binding var signaturePlacement: NormalizedSignaturePlacement
    @Binding var fieldStates: [DocumentTextFieldState]
    @Binding var inkStates: [DocumentInkFieldState]

    @State private var pageImage: UIImage?
    @State private var signatureDragOffset: CGSize = .zero
    @State private var textDragOffsets: [String: CGSize] = [:]
    @State private var inkDragOffsets: [String: CGSize] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ziehe Unterschrift, Zeichnungen und Texte auf die richtige Stelle.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 8)

            GeometryReader { geometry in
                ZStack {
                    Color(.secondarySystemBackground)

                    if let pageImage,
                       let layout = pageLayout(in: geometry.size, imageSize: pageImage.size) {
                        Image(uiImage: pageImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: layout.size.width, height: layout.size.height)
                            .position(x: layout.midX, y: layout.midY)

                        ForEach($fieldStates) { $state in
                            textOverlay(state: $state, layout: layout)
                        }

                        ForEach($inkStates) { $state in
                            if state.image != nil {
                                inkOverlay(state: $state, layout: layout)
                            }
                        }

                        signatureOverlay(layout: layout)
                    } else {
                        ProgressView("PDF wird geladen …")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 18)
            }

            Text("Tipp: Alles erscheint schwarz auf dem PDF. Leere Zeichenfelder werden nicht übernommen.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            pageImage = PDFSignatureService.renderPageImage(
                sourceURL: fileURL,
                pageIndex: pageIndex
            )
        }
    }

    @ViewBuilder
    private func signatureOverlay(layout: PageLayout) -> some View {
        let box = overlayBox(
            placement: signaturePlacement.clamped(),
            in: layout,
            extraOffset: signatureDragOffset
        )

        Image(uiImage: signatureImage)
            .resizable()
            .scaledToFit()
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            .overlay {
                overlayFrame(box: box, color: .accentColor)
            }
            .gesture(
                DragGesture()
                    .onChanged { signatureDragOffset = $0.translation }
                    .onEnded { value in
                        signaturePlacement.x += value.translation.width / layout.size.width
                        signaturePlacement.y += value.translation.height / layout.size.height
                        signaturePlacement = signaturePlacement.clamped()
                        signatureDragOffset = .zero
                    }
            )
    }

    @ViewBuilder
    private func inkOverlay(state: Binding<DocumentInkFieldState>, layout: PageLayout) -> some View {
        if let image = state.wrappedValue.image {
        let fieldID = state.wrappedValue.id
        let dragOffset = inkDragOffsets[fieldID] ?? .zero
        let box = overlayBox(
            placement: state.wrappedValue.placement.clamped(),
            in: layout,
            extraOffset: dragOffset
        )

        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            .overlay {
                overlayFrame(box: box, color: .green)
            }
            .gesture(
                DragGesture()
                    .onChanged { inkDragOffsets[fieldID] = $0.translation }
                    .onEnded { value in
                        state.wrappedValue.placement.x += value.translation.width / layout.size.width
                        state.wrappedValue.placement.y += value.translation.height / layout.size.height
                        state.wrappedValue.placement = state.wrappedValue.placement.clamped()
                        inkDragOffsets[fieldID] = .zero
                    }
            )
        }
    }

    @ViewBuilder
    private func textOverlay(state: Binding<DocumentTextFieldState>, layout: PageLayout) -> some View {
        if !state.wrappedValue.renderedText.isEmpty {
        let fieldID = state.wrappedValue.id
        let dragOffset = textDragOffsets[fieldID] ?? .zero
        let box = overlayBox(
            placement: state.wrappedValue.placement.clamped(),
            in: layout,
            extraOffset: dragOffset
        )

        Text(state.wrappedValue.renderedText)
            .font(.system(size: max(5, min(box.height * 0.42, 10)), weight: .medium))
            .foregroundColor(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: box.width, height: box.height, alignment: .leading)
            .position(x: box.midX, y: box.midY)
            .overlay {
                overlayFrame(box: box, color: .orange)
            }
            .gesture(
                DragGesture()
                    .onChanged { textDragOffsets[fieldID] = $0.translation }
                    .onEnded { value in
                        state.wrappedValue.placement.x += value.translation.width / layout.size.width
                        state.wrappedValue.placement.y += value.translation.height / layout.size.height
                        state.wrappedValue.placement = state.wrappedValue.placement.clamped()
                        textDragOffsets[fieldID] = .zero
                    }
            )
        }
    }

    private func overlayFrame(box: CGRect, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
    }

    private func overlayBox(
        placement: NormalizedTextPlacement,
        in layout: PageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        overlayBox(x: placement.x, y: placement.y, width: placement.width, height: placement.height, in: layout, extraOffset: extraOffset)
    }

    private func overlayBox(
        placement: NormalizedSignaturePlacement,
        in layout: PageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        overlayBox(x: placement.x, y: placement.y, width: placement.width, height: placement.height, in: layout, extraOffset: extraOffset)
    }

    private func overlayBox(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        in layout: PageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        let boxWidth = layout.size.width * width
        let boxHeight = layout.size.height * height
        let originX = layout.origin.x + layout.size.width * x + extraOffset.width
        let originY = layout.origin.y + layout.size.height * y + extraOffset.height
        return CGRect(x: originX, y: originY, width: boxWidth, height: boxHeight)
    }

    private func pageLayout(in containerSize: CGSize, imageSize: CGSize) -> PageLayout? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2
        )

        return PageLayout(origin: origin, size: size)
    }
}

private struct PageLayout {
    let origin: CGPoint
    let size: CGSize

    var midX: CGFloat { origin.x + size.width / 2 }
    var midY: CGFloat { origin.y + size.height / 2 }
}

