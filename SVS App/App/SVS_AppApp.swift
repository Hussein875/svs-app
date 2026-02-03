import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import FirebaseFirestore
// optional, falls du FirebaseAuth nutzt:
import FirebaseAuth

/// Zentrale AppDelegate-Klasse für:
/// - Firebase Initialisierung
/// - Push-Notification-Setup (APNs + FCM)
/// - Empfang & Verarbeitung von Push-Notifications
/// - Verwaltung von FCM-Device-Tokens pro User
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    private lazy var db = Firestore.firestore()

    /// Wird beim App-Start aufgerufen.
    /// - Initialisiert Firebase
    /// - Setzt die Delegates für Push Notifications und Firebase Messaging
    /// - Fragt die Push-Berechtigung beim Nutzer an
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

    /// Fragt den Nutzer nach Erlaubnis für Push Notifications.
    /// - Aktiviert Alerts, Badges und Sounds
    /// - Registriert die App bei APNs, wenn die Erlaubnis erteilt wurde
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

    /// Wird aufgerufen, sobald APNs der App ein Device-Token zuweist.
    /// - Verknüpft das APNs-Token mit Firebase Cloud Messaging
    /// - Notwendig, damit FCM Pushes über APNs zugestellt werden kann
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // APNs Token an Firebase Messaging binden
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Wird aufgerufen, wenn Firebase ein (neues) FCM-Token erzeugt.
    /// - Passiert beim ersten Start, Reinstall oder Token-Refresh
    /// - Speichert das Token in Firestore unter dem eingeloggten User
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

    /// Speichert das FCM-Token des Geräts in Firestore.
    /// - Jedes Gerät wird eindeutig über eine deviceId identifiziert
    /// - Ermöglicht Multi-Device-Pushes pro User
    /// - Wird von Cloud Functions für gezielte Pushes genutzt
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

    /// Wird aufgerufen, wenn eine Push Notification eingeht,
    /// während die App im Vordergrund aktiv ist.
    /// - Steuert, wie die Notification angezeigt wird
    /// - Rückgabe von Banner + Sound + Badge
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Wird aufgerufen, wenn der User aktiv auf eine Push Notification tippt.
    /// - Enthält alle Informationen der Notification
    /// - Zentraler Einstiegspunkt für DeepLinks / Routing
    /// - Aktuell: Logging des Inhalts
    /// - Später: Navigation (z. B. Antrag öffnen)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {

        let content = response.notification.request.content

        // Text-Inhalt der Notification
        let title = content.title
        let subtitle = content.subtitle
        let body = content.body

        // Meta
        let identifier = response.notification.request.identifier
        let actionId = response.actionIdentifier
        let categoryId = content.categoryIdentifier

        print("[PushTap] id=\(identifier) action=\(actionId) category=\(categoryId)")
        print("[PushTap] title=\(title)")
        if !subtitle.isEmpty { print("[PushTap] subtitle=\(subtitle)") }
        print("[PushTap] body=\(body)")

        // Payload (data)
        let userInfo = content.userInfo
        // Route push taps into the app (SwiftUI can observe NotificationCenter).
        PushNotificationRouter.handlePushTap(userInfo: userInfo)
        if userInfo.isEmpty {
            print("[PushTap] userInfo: <empty>")
        } else {
            print("[PushTap] userInfo:")
            if userInfo.isEmpty {
                print("[PushTap] userInfo: <empty>")
            } else {
                print("[PushTap] userInfo:")
                let keys = userInfo.keys
                    .map { String(describing: $0) }
                    .sorted()

                for k in keys {
                    let v = userInfo[k] ?? "<nil>"
                    print("  - \(k): \(v)")
                }
            }
        }
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
