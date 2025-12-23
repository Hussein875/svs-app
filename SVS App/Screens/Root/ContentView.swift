import SwiftUI
import Combine
import WebKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if appState.currentUser == nil {
                    LoginView()
                } else {
                    MainView()
                }
            }

            if let toast = appState.toast {
                ToastBanner(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toast)
    }
}
