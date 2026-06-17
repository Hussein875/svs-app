//
//  AccidentSketchGalleryView.swift
//  SVS App
//

import SwiftUI

struct AccidentSketchGalleryView: View {
    @State private var selectedTemplate: AccidentSketchTemplate?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Vorlage wählen, Fahrzeuge verschieben und mit Stift ergänzen. Links unten im Editor: ein Fahrzeug hinzufügen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 18)

                LazyVGrid(columns: columns, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 10) {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                Label(template.title, systemImage: template.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .labelStyle(.titleAndIcon)

                Text(template.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
