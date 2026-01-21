import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var didTimeout = false

    var body: some View {
        mainContent
            .overlay(alignment: .top) {
                if let toast = appState.toast {
                    ToastBanner(toast: toast)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.toast != nil)
            .onChange(of: appState.auth.user?.uid) { _ in
                // Auth changed → reset timeout state
                didTimeout = false
            }
            .onChange(of: appState.isProfileReady) { ready in
                // As soon as profile is ready, reset timeout
                if ready { didTimeout = false }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if appState.auth.user == nil {
            LoginView()
        } else if !appState.isProfileReady {
            VStack(spacing: 14) {
                ProgressView()
                Text("Profil wird geladen …")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                
                if didTimeout {
                    Button("Zurück zum Login") {
                        do {
                            try appState.auth.signOut()
                        } catch {
                            print("SignOut failed:", error)
                        }
                        didTimeout = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            // Timeout runs once per auth UID; no loops
            .task(id: appState.auth.user?.uid) {
                didTimeout = false
                // Timeout after 7 seconds to avoid infinite loading
                try? await _Concurrency.Task.sleep(nanoseconds: 7_000_000_000)
                if !appState.isProfileReady {
                    didTimeout = true
                }
            }
        } else {
            if appState.currentUser != nil {
                MainView()
            } else {
                // Defensive fallback if profile-ready flag is set but user is not yet populated
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Profil wird finalisiert …")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}
