//
//  NotificationManager.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation
import Combine
import UserNotifications
#if os(macOS)
import AppKit
#endif

/// Manages user notifications for clipboard events
class NotificationManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationManager()

    // MARK: - Published Properties

    @Published var isAuthorized: Bool = false

    // MARK: - Initialization

    private override init() {
        super.init()
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Requests notification permission from user
    func requestAuthorization() async -> Bool {
        do {
            // Request with all options including critical alerts
            let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: options)

            await MainActor.run {
                isAuthorized = granted
            }

            if granted {
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied")
            }

            return granted
        } catch {
            print("❌ Error requesting notification permission: \(error)")
            return false
        }
    }

    /// Checks current notification authorization status
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Notification Methods

    /// Sends critical alert for hijack detection (REQ-006)
    func sendHijackAlert(originalAddress: String, attemptedAddress: String) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Clipboard Hijack Blocked!"
        content.body = "Malicious software tried to replace your crypto address"
        content.sound = .defaultCritical
        content.categoryIdentifier = "HIJACK_ALERT"
        content.interruptionLevel = .critical

        // Add user info for custom actions
        content.userInfo = [
            "type": "hijack",
            "original": maskAddress(originalAddress),
            "attempted": maskAddress(attemptedAddress)
        ]

        // Create request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Immediate
        )

        // Send notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending hijack notification: \(error)")
            } else {
                print("📬 Hijack notification sent")
            }
        }

        // Also show modal alert on macOS
        #if os(macOS)
        showMacOSAlert(originalAddress: originalAddress, attemptedAddress: attemptedAddress)
        #endif
    }

    /// Sends success notification when crypto address is detected and verified
    func sendCryptoDetectedNotification(type: CryptoType, address: String) {
        let content = UNMutableNotificationContent()

        // Emoji based on crypto type
        let emoji = cryptoEmoji(for: type)

        content.title = "\(emoji) \(type.rawValue) Address Verified"
        content.body = "✓ Your clipboard is protected • \(maskAddress(address))"
        content.sound = .default  // Play sound for confirmation
        content.categoryIdentifier = "CRYPTO_DETECTED"

        // Add user info
        content.userInfo = [
            "type": "crypto_detected",
            "crypto_type": type.rawValue
        ]

        // Create request with auto-dismiss after 3 seconds
        let request = UNNotificationRequest(
            identifier: "crypto_detected_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        // Send notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending crypto detection notification: \(error)")
            } else {
                print("📬 Success notification sent for \(type.rawValue)")
            }
        }

        // Auto-remove after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [request.identifier]
            )
        }
    }

    /// Returns emoji for crypto type
    private func cryptoEmoji(for type: CryptoType) -> String {
        switch type {
        case .bitcoin: return "₿"
        case .ethereum: return "Ξ"
        case .litecoin: return "Ł"
        case .dogecoin: return "Ð"
        case .monero: return "ɱ"
        case .solana: return "◎"
        case .unknown: return "🔐"
        }
    }

    /// Sends license expiration warning
    func sendLicenseExpiryWarning(daysRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "License Expires in \(daysRemaining) Days"
        content.body = "Renew now to continue protection"
        content.sound = .default
        content.categoryIdentifier = "LICENSE_EXPIRY"

        // Add action button
        let renewAction = UNNotificationAction(
            identifier: "RENEW_LICENSE",
            title: "Renew License",
            options: .foreground
        )

        let category = UNNotificationCategory(
            identifier: "LICENSE_EXPIRY",
            actions: [renewAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Create request
        let request = UNNotificationRequest(
            identifier: "license_expiry_\(daysRemaining)",
            content: content,
            trigger: nil
        )

        // Send notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending license expiry notification: \(error)")
            }
        }
    }

    // MARK: - macOS Modal Alert

    #if os(macOS)
    /// Shows modal alert dialog on macOS (REQ-006)
    private func showMacOSAlert(originalAddress: String, attemptedAddress: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "⚠️ Clipboard Hijack Attempt Blocked"
            alert.informativeText = """
            ClipboardGuard detected and blocked malicious software attempting to replace your cryptocurrency address.

            Original:    \(self.maskAddress(originalAddress))
            Attempted:   \(self.maskAddress(attemptedAddress))

            Your original address has been restored.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "View Security Log")

            let response = alert.runModal()

            if response == .alertSecondButtonReturn {
                // TODO: Open security log view
                print("User wants to view security log")
            }
        }
    }
    #endif

    // MARK: - Helper Methods

    /// Masks address for display (shows first 6 and last 4 characters)
    private func maskAddress(_ address: String) -> String {
        guard address.count > 10 else { return "***" }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    /// Clears all delivered notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Called when notification is received while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when user interacts with notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "RENEW_LICENSE":
            // TODO: Open renewal page
            print("User tapped Renew License")

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification body
            if let type = userInfo["type"] as? String, type == "hijack" {
                // TODO: Open security log
                print("User tapped hijack notification")
            }

        default:
            break
        }

        completionHandler()
    }
}
