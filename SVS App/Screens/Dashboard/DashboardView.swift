//
//  DashboardView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import WebKit

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            DashboardWebView(url: URL(string: "https://dashboard.sv-souleiman.de")!)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DashboardWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        if uiView.url != url {
            uiView.load(request)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

// Kleine Avatar-View mit Initialen
struct InitialsAvatarView: View {
    let name: String
    let color: Color

    private var initials: String {
        let components = name
            .split(separator: " ")
            .compactMap { $0.first.map(String.init) }
        let joined = components.prefix(2).joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(width: 32, height: 32)
    }
}
