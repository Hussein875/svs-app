//
//  AbtretungserklaerungPlacementAdjustView.swift
//  SVS App
//

import SwiftUI
import UIKit

struct AEPlacementFieldState: Identifiable, Equatable {
    let field: AbtretungserklaerungField
    var placement: NormalizedTextPlacement
    var previewText: String

    var id: String { field.rawValue }
}

struct AbtretungserklaerungPlacementAdjustView: View {
    let sourcePDFURL: URL
    let form: AbtretungserklaerungForm

    @Binding var fieldStates: [AEPlacementFieldState]
    @Binding var signaturePlacement: NormalizedSignaturePlacement

    @State private var pageImage: UIImage?
    @State private var textDragOffsets: [String: CGSize] = [:]
    @State private var signatureDragOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ziehe die orangen Felder, das Datum und den Unterschriftsrahmen auf die richtige Stelle.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
                            if !state.previewText.isEmpty {
                                textOverlay(state: $state, layout: layout)
                            }
                        }

                        signaturePlaceholder(layout: layout)
                    } else {
                        ProgressView("PDF wird geladen …")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(minHeight: 420)

            Button("Standardpositionen wiederherstellen", role: .destructive) {
                resetToDefaults()
            }
            .font(.caption)
        }
        .onAppear {
            pageImage = PDFSignatureService.renderPageImage(sourceURL: sourcePDFURL, pageIndex: 0)
            if fieldStates.isEmpty {
                fieldStates = Self.makeFieldStates(form: form)
            }
            if signaturePlacement.width == 0 {
                signaturePlacement = NormalizedSignaturePlacement(
                    from: AbtretungserklaerungPlacementStore.placement(for: .signatureImage)
                )
            }
        }
    }

    static func makeFieldStates(form: AbtretungserklaerungForm) -> [AEPlacementFieldState] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"

        func text(for field: AbtretungserklaerungField) -> String {
            switch field {
            case .clientName: return form.clientName
            case .streetAndNumber: return form.streetAndNumber
            case .postalCodeAndCity: return form.postalCodeAndCity
            case .phoneOrEmail: return form.phoneOrEmail
            case .licensePlate: return form.licensePlate
            case .opponentName: return form.opponentName
            case .insuranceCompany: return form.insuranceCompany
            case .claimOrPolicyNumber: return form.claimOrPolicyNumber
            case .opponentLicensePlate: return form.opponentLicensePlate
            case .damageDate: return formatter.string(from: form.damageDate)
            case .damageLocation: return form.damageLocation
            case .gutachtenNumber: return form.gutachtenNumber
            case .vatYes: return form.isVatDeductible == true ? "X" : ""
            case .vatNo: return form.isVatDeductible == false ? "X" : ""
            case .signingDate: return formatter.string(from: form.signingDate)
            case .signatureImage: return ""
            }
        }

        return AbtretungserklaerungField.adjustableFields.map { field in
            AEPlacementFieldState(
                field: field,
                placement: NormalizedTextPlacement(from: AbtretungserklaerungPlacementStore.placement(for: field)),
                previewText: text(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func persistPlacements(
        fieldStates: [AEPlacementFieldState],
        signaturePlacement: NormalizedSignaturePlacement
    ) {
        for state in fieldStates where !state.previewText.isEmpty || state.field == .signingDate {
            AbtretungserklaerungPlacementStore.save(
                state.placement.pdfPlacement(pageIndex: 0),
                for: state.field
            )
        }
        if let vatYes = fieldStates.first(where: { $0.field == .vatYes }), !vatYes.previewText.isEmpty {
            AbtretungserklaerungPlacementStore.save(vatYes.placement.pdfPlacement(pageIndex: 0), for: .vatYes)
        }
        if let vatNo = fieldStates.first(where: { $0.field == .vatNo }), !vatNo.previewText.isEmpty {
            AbtretungserklaerungPlacementStore.save(vatNo.placement.pdfPlacement(pageIndex: 0), for: .vatNo)
        }
        AbtretungserklaerungPlacementStore.save(
            signaturePlacement.pdfPlacement(pageIndex: 0),
            for: .signatureImage
        )
    }

    private func resetToDefaults() {
        AbtretungserklaerungPlacementStore.resetToDefaults()
        fieldStates = Self.makeFieldStates(form: form)
        signaturePlacement = NormalizedSignaturePlacement(
            from: AbtretungserklaerungField.signatureImage.defaultPlacement
        )
    }

    @ViewBuilder
    private func textOverlay(state: Binding<AEPlacementFieldState>, layout: AEPageLayout) -> some View {
        let fieldID = state.wrappedValue.id
        let dragOffset = textDragOffsets[fieldID] ?? .zero
        let box = overlayBox(
            placement: state.wrappedValue.placement.clamped(),
            in: layout,
            extraOffset: dragOffset
        )

        Text(state.wrappedValue.previewText)
            .font(.system(size: max(6, min(box.height * 0.55, 11)), weight: .medium))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: box.width, height: box.height, alignment: .leading)
            .position(x: box.midX, y: box.midY)
            .overlay {
                overlayFrame(box: box, color: state.wrappedValue.field == .signingDate ? .blue : .orange)
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

    @ViewBuilder
    private func signaturePlaceholder(layout: AEPageLayout) -> some View {
        let box = overlayBox(
            placement: signaturePlacement.clamped(),
            in: layout,
            extraOffset: signatureDragOffset
        )

        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: box.width, height: box.height)
            .overlay {
                Text("Unterschrift")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .position(x: box.midX, y: box.midY)
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

    private func overlayFrame(box: CGRect, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
    }

    private func overlayBox(
        placement: NormalizedTextPlacement,
        in layout: AEPageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        overlayBox(x: placement.x, y: placement.y, width: placement.width, height: placement.height, in: layout, extraOffset: extraOffset)
    }

    private func overlayBox(
        placement: NormalizedSignaturePlacement,
        in layout: AEPageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        overlayBox(x: placement.x, y: placement.y, width: placement.width, height: placement.height, in: layout, extraOffset: extraOffset)
    }

    private func overlayBox(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        in layout: AEPageLayout,
        extraOffset: CGSize
    ) -> CGRect {
        let boxWidth = layout.size.width * width
        let boxHeight = layout.size.height * height
        let originX = layout.origin.x + layout.size.width * x + extraOffset.width
        let originY = layout.origin.y + layout.size.height * y + extraOffset.height
        return CGRect(x: originX, y: originY, width: boxWidth, height: boxHeight)
    }

    private func pageLayout(in containerSize: CGSize, imageSize: CGSize) -> AEPageLayout? {
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

        return AEPageLayout(origin: origin, size: size)
    }
}

private struct AEPageLayout {
    let origin: CGPoint
    let size: CGSize

    var midX: CGFloat { origin.x + size.width / 2 }
    var midY: CGFloat { origin.y + size.height / 2 }
}
