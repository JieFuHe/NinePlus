import Foundation
import UIKit
import UserNotifications

enum NinebotPushError: LocalizedError {
    case denied
    case missingToken
    case missingBundleID
    case missingServer

    var errorDescription: String? {
        switch self {
        case .denied:
            return "系统通知权限未开启"
        case .missingToken:
            return "还没有拿到 APNs 设备 Token，请稍后再试"
        case .missingBundleID:
            return "无法读取 App Bundle ID"
        case .missingServer:
            return "请先填写 NinePlus 平台地址和 Token"
        }
    }
}

final class NinebotPushManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = NinebotPushManager()

    private let store = NinebotSharedStore()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await requestAuthorizationOnLaunchAndRegister() }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        store.savePushDeviceToken(token)
        Task {
            try? await registerStoredTokenWithServer()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Registration can fail on simulator or when signing lacks Push Notifications.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func requestAuthorizationAndRegister() async throws {
        let granted = try await requestAuthorization()
        guard granted else { throw NinebotPushError.denied }
        await registerForRemoteNotifications()
    }

    func requestAuthorizationRegisterAndWaitForToken() async throws -> String? {
        let granted = try await requestAuthorization()
        guard granted else { throw NinebotPushError.denied }
        await registerForRemoteNotifications()
        return await waitForStoredToken()
    }

    func registerStoredTokenWithServer() async throws {
        guard let token = store.loadPushDeviceToken() else {
            throw NinebotPushError.missingToken
        }
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            throw NinebotPushError.missingBundleID
        }
        guard let configuration = store.loadConfiguration(), configuration.isUsable else {
            throw NinebotPushError.missingServer
        }
        try await NinebotProxyClient(configuration: configuration).registerPushDevice(
            token: token,
            bundleID: bundleID,
            environment: Self.apnsEnvironment
        )
    }

    private func requestAuthorizationOnLaunchAndRegister() async {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard ((try? await requestAuthorization()) ?? false) else { return }
            await registerForRemoteNotifications()
        case .authorized, .provisional, .ephemeral:
            await registerForRemoteNotifications()
        default:
            break
        }
    }

    @MainActor
    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func waitForStoredToken() async -> String? {
        if let token = store.loadPushDeviceToken() {
            return token
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let token = store.loadPushDeviceToken() {
                return token
            }
        }

        return store.loadPushDeviceToken()
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}
