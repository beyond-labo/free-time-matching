import Foundation
import UIKit
import UserNotifications

enum SchedulingPushEnvironment {
    static func apiValue(_ entitlement: String?) throws -> String {
        switch entitlement {
        case "development": "sandbox"
        case "production": "production"
        default: throw SchedulingFailure.rejected
        }
    }
}

/// Only APNs lifecycle and local notification preference live here. Owner binding is in Composition.
@MainActor
final class SchedulingPushAdapter {
    static let shared = SchedulingPushAdapter()
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]
    private let defaults = UserDefaults.standard
    private let tokenKey = "automaticScheduling.apnsToken"
    private let enabledKey = "automaticScheduling.notificationsEnabled"
    var storedToken: String? { defaults.string(forKey: tokenKey) }
    var enabled: Bool { defaults.bool(forKey: enabledKey) }

    func requestPermission() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        defaults.set(granted, forKey: enabledKey)
        return granted
    }

    func allowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func disableLocally() { defaults.set(false, forKey: enabledKey) }

    func register() async throws -> String {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
            UIApplication.shared.registerForRemoteNotifications()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.waiters.removeValue(forKey: id)?.resume(throwing: SchedulingFailure.unavailable)
            }
        }
    }

    func registered(_ data: Data) {
        guard data.count == 32 else { failed(); return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: tokenKey)
        let pending = Array(waiters.values)
        waiters.removeAll()
        for continuation in pending { continuation.resume(returning: token) }
    }

    func failed() {
        let pending = Array(waiters.values)
        waiters.removeAll()
        for continuation in pending { continuation.resume(throwing: SchedulingFailure.unavailable) }
    }
}

final class SchedulingAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SchedulingPushAdapter.shared.registered(deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        SchedulingPushAdapter.shared.failed()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationCenter.default.post(name: .schedulingNotificationOpened, object: nil) }
    }
}

extension Notification.Name {
    static let schedulingNotificationOpened = Notification.Name("automaticScheduling.notificationOpened")
}

/// Preserve registration order across enable, logout and account switches.
actor SchedulingDeviceWriter {
    private var tail: Task<Void, Never>?
    func write(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let predecessor = tail
        let task = Task {
            await predecessor?.value
            try await operation()
        }
        tail = Task { _ = try? await task.value }
        try await task.value
    }
}
