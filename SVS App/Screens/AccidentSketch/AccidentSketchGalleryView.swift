//
//  AccidentSketchGalleryView.swift
//  SVS App
//

import SwiftUI

struct AccidentSketchGalleryView: View {
    @State private var selectedTemplate: AccidentSketchTemplate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Straße wählen, Autos platzieren (ziehen & drehen). Weißer Pfeil = Fahrtrichtung.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 18)

                VStack(spacing: 12) {
                    ForEach(AccidentSketchTemplate.allCases) { template in
                        Button {
                            selectedTemplate = template
                        } label: {
                            AccidentSketchTemplateCard(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Schadenhergang")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $selectedTemplate) { template in
            AccidentSketchEditorView(
                template: template,
                onDismiss: { selectedTemplate = nil }
            )
        }
    }
}

private struct AccidentSketchTemplateCard: View {
    let template: AccidentSketchTemplate

    private var previewImage: UIImage {
        AccidentSketchRenderer.render(template)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 6) {
                Label(template.title, systemImage: template.systemImage)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .labelStyle(.titleAndIcon)

                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                Text("Autos verschieben · direkt zeichnen")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
    }
}
