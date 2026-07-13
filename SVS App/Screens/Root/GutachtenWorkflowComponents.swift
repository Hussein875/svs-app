//
//  GutachtenWorkflowComponents.swift
//  SVS App
//

import SwiftUI

struct GutachtenWorkflowPicker: View {
    let accent: Color
    let onStartAbtretungserklaerung: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was möchtest du tun?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            HStack(spacing: 12) {
                GutachtenWorkflowCard(
                    title: "Abtretungserklärung",
                    subtitle: "Kunde erfassen, unterschreiben, Drive",
                    systemImage: "list.bullet.rectangle.portrait.fill",
                    tint: accent,
                    isFeatured: true,
                    action: onStartAbtretungserklaerung
                )

                GutachtenWorkflowCard(
                    title: "Dokument scannen",
                    subtitle: "Weiter unten mit der Kamera",
                    systemImage: "camera.fill",
                    tint: accent,
                    isFeatured: false,
                    action: {}
                )
                .allowsHitTesting(false)
            }
        }
    }
}

private struct GutachtenWorkflowCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isFeatured: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isFeatured ? .white : tint)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isFeatured ? .white.opacity(0.18) : tint.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isFeatured ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isFeatured ? .white.opacity(0.88) : .secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isFeatured {
                    HStack(spacing: 4) {
                        Text("Starten")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isFeatured
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [tint, tint.opacity(0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color(.secondarySystemBackground))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isFeatured ? tint.opacity(0.2) : Color.secondary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isFeatured ? tint.opacity(0.22) : Color.black.opacity(0.04),
                radius: isFeatured ? 10 : 6,
                x: 0,
                y: isFeatured ? 6 : 4
            )
        }
        .buttonStyle(.plain)
    }
}

struct AbtretungserklaerungLaunchButton<Label: View>: View {
    @ViewBuilder let label: () -> Label

    @State private var showFunnel = false
    @State private var missingPDFMessage: String?

    var body: some View {
        Button {
            if CompanyDocumentsCatalog.abtretungserklaerungPDFURL != nil {
                showFunnel = true
            } else {
                missingPDFMessage = "Die Abtretungserklärung konnte nicht geladen werden."
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showFunnel) {
            if let url = CompanyDocumentsCatalog.abtretungserklaerungPDFURL {
                AbtretungserklaerungFunnelView(sourcePDFURL: url)
            }
        }
        .alert("Abtretungserklärung", isPresented: isMissingPDFPresented) {
            Button("OK", role: .cancel) { missingPDFMessage = nil }
        } message: {
            Text(missingPDFMessage ?? "")
        }
    }

    private var isMissingPDFPresented: Binding<Bool> {
        Binding(
            get: { missingPDFMessage != nil },
            set: { if !$0 { missingPDFMessage = nil } }
        )
    }
}
