//
//  SVSWatchApp.swift
//  SVS Watch App
//

import SwiftUI
import WatchKit

@main
struct SVSWatchApp: App {
    @WKExtensionDelegateAdaptor(WatchExtensionDelegate.self) private var extensionDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

struct WatchRootView: View {
    @State private var snapshot = ScannerWidgetSnapshot.load()

    var body: some View {
        VStack(spacing: 8) {
            Text("Gutachten-Nr.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(snapshot.numberText)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(snapshot.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            snapshot = ScannerWidgetSnapshot.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scannerWidgetSnapshotDidChange)) { _ in
            snapshot = ScannerWidgetSnapshot.load()
        }
    }
}
