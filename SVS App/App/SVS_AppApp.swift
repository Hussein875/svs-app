import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import FirebaseFirestore
// optional, falls du FirebaseAuth nutzt:
import FirebaseAuth

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    private lazy var db = Firestore.firestore()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        requestPushAuthorization()

        return true
    }

    private func requestPushAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Push permission error:", error)
                return
            }
            guard granted else {
                print("Push permission not granted")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // APNs Token an Firebase Messaging binden
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        print("FCM Token:", fcmToken)

        // WICHTIG: Nur speichern, wenn du den eingeloggten User kennst
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No logged in user yet – token will be saved after login.")
            return
        }
        saveDeviceToken(userId: userId, fcmToken: fcmToken)
    }

    private func saveDeviceToken(userId: String, fcmToken: String) {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        let data: [String: Any] = [
            "fcmToken": fcmToken,
            "platform": "ios",
            "deviceId": deviceId,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        db.collection("users")
            .document(userId)
            .collection("devices")
            .document(deviceId)
            .setData(data, merge: true)
    }

    // Push im Vordergrund anzeigen
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

@main
struct SVS_AppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
