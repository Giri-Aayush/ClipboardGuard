//
//  ClipboardApp.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI
import UserNotifications

@main
struct ClipboardApp: App {

    // MARK: - State Objects

    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    #if os(macOS)
    private let floatingIndicator = FloatingIndicatorWindow()
    private let blockedPasteAlert = BlockedPasteAlertWindow()
    private let protectionTimer = ProtectionTimerWindow()
    @StateObject private var pasteDetector = PasteDetector()
    private let pasteBlocker = PasteBlocker()
    #endif

    // Timer needs to be in a class wrapper for mutation
    #if os(macOS)
    private class TimerWrapper {
        var timer: Timer?
    }
    private let timerWrapper = TimerWrapper()
    #endif

    // MARK: - Initialization

    init() {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView(
                licenseManager: licenseManager,
                clipboardMonitor: clipboardMonitor
            )
            .onAppear {
                setupApp()
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }

    // MARK: - Setup

    private func setupApp() {
        let notificationManager = NotificationManager.shared

        // Request notification permission
        Task {
            await notificationManager.requestAuthorization()
        }

        // Setup COPY detector (Cmd+C)
        #if os(macOS)
        pasteDetector.onCopyDetected = { [self] in
            // Record timestamp for time-correlation
            clipboardMonitor.lastUserCopyTime = pasteDetector.lastUserCopyTimestamp
            print("⏱️  [Time-Correlation] Cmd+C detected at \(Date())")
        }

        // Setup PASTE detector (Cmd+V)
        pasteDetector.onPasteDetected = { [self] in
            // Check if we're actively protecting a crypto address
            guard clipboardMonitor.protectionActive,
                  let protectedAddress = clipboardMonitor.monitoredContent,
                  let type = clipboardMonitor.lastDetectedCryptoType else {
                print("ℹ️  Paste detected but no active protection")
                return
            }

            // Read current clipboard to verify it's actually a crypto address
            #if os(macOS)
            guard let currentClipboard = NSPasteboard.general.string(forType: .string) else {
                print("ℹ️  Paste detected but clipboard has no string (likely image/file)")
                return
            }
            #endif

            // Verify current clipboard matches the protected address
            if currentClipboard == protectedAddress {
                print("✅ PASTE VERIFIED - Protected \(type.rawValue) address pasted safely!")
                DispatchQueue.main.async {
                    floatingIndicator.showPaste(for: type)
                }

                // Update statistics
                DispatchQueue.main.async {
                    clipboardMonitor.pasteCount += 1
                }

                // Stop protection after successful paste
                clipboardMonitor.stopProtection()

                // Hide the protection timer
                hideProtectionTimer()
            } else {
                print("ℹ️  Paste detected but content doesn't match protected address")
                print("   Protected: \(String(protectedAddress.prefix(20)))...")
                print("   Current:   \(String(currentClipboard.prefix(20)))...")
            }
        }

        // Setup paste blocker
        pasteBlocker.shouldBlockPaste = { [self] in
            return clipboardMonitor.checkIfShouldBlockPaste()
        }

        pasteBlocker.onPasteBlocked = { [self] original, hijacked in
            print("🚨 PASTE BLOCKED - Showing red alert at cursor!")
            DispatchQueue.main.async {
                blockedPasteAlert.showBlocked(original: original, hijacked: hijacked)
            }

            // Also increment threats blocked counter
            clipboardMonitor.threatsBlocked += 1
        }
        #endif

        // Setup clipboard monitoring callbacks
        clipboardMonitor.onCryptoCopied = { [self] address, type in
            print("📋 COPY: \(type.rawValue) address copied")

            // Start 2-minute protection for this address
            clipboardMonitor.startProtection(for: address, type: type)

            // Show blue protection indicator (cursor position)
            #if os(macOS)
            DispatchQueue.main.async {
                floatingIndicator.showCopy(for: type)

                // Show persistent protection timer in top-right corner
                self.showProtectionTimer(for: type)
            }
            #endif
        }

        clipboardMonitor.onCryptoPasted = { [self] address, type in
            print("✅ PASTE: \(type.rawValue) address pasted & verified!")

            // Show green "verified" indicator
            #if os(macOS)
            DispatchQueue.main.async {
                floatingIndicator.showPaste(for: type)
            }
            #endif
        }

        clipboardMonitor.onHijackDetected = { original, attempted in
            print("🚨 Hijack detected!")
            // DISABLED: System notifications are too intrusive
            // User will see red alert when trying to paste instead
            // NotificationManager.shared.sendHijackAlert(
            //     originalAddress: original,
            //     attemptedAddress: attempted
            // )
        }

        clipboardMonitor.onNonCryptoContentCopied = { [self] in
            print("⚠️  Non-crypto content copied - showing warning and auto-hiding in 5s")
            #if os(macOS)
            DispatchQueue.main.async {
                // Stop the protection timer update loop
                self.timerWrapper.timer?.invalidate()
                self.timerWrapper.timer = nil

                // Show warning for 5 seconds
                self.protectionTimer.showWarning("Non-crypto content copied - Protection stopped")

                // Auto-hide widget after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    print("⏱️  Auto-hiding protection timer after 5s")
                    self.hideProtectionTimer()
                }
            }
            #endif
        }

        // Auto-start monitoring if licensed
        if licenseManager.isLicensed {
            clipboardMonitor.startMonitoring()
        }
    }

    // MARK: - Protection Timer Management

    #if os(macOS)
    private func showProtectionTimer(for type: CryptoType) {
        print("🎯 [ProtectionTimer] Showing notch widget for \(type.rawValue)")
        print("   Time remaining: \(clipboardMonitor.protectionTimeRemaining)s")

        // Show the timer window
        protectionTimer.showProtection(
            for: type,
            timeRemaining: clipboardMonitor.protectionTimeRemaining,
            onDismiss: { [weak timerWrapper, weak clipboardMonitor] in
                print("❌ [ProtectionTimer] User dismissed via × button")
                timerWrapper?.timer?.invalidate()
                timerWrapper?.timer = nil
                clipboardMonitor?.stopProtection()
            }
        )

        // Start updating the timer every 0.1 seconds for smooth countdown
        print("🔄 [ProtectionTimer] Starting update loop (every 0.1s)")
        timerWrapper.timer?.invalidate()

        var lastLoggedSecond = -1
        timerWrapper.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak timerWrapper, weak clipboardMonitor] _ in
            // Update timer display
            guard let monitor = clipboardMonitor else {
                print("⚠️  [ProtectionTimer] Monitor is nil")
                return
            }
            let timeRemaining = monitor.protectionTimeRemaining

            // Log every second to avoid spam
            let currentSecond = Int(timeRemaining)
            if currentSecond != lastLoggedSecond {
                print("🔄 [ProtectionTimer] Updating: \(currentSecond)s, active: \(monitor.protectionActive)")
                print("   Calling updateTime on protectionTimer...")
                lastLoggedSecond = currentSecond
            }

            if timeRemaining > 0 && monitor.protectionActive {
                // Use self here - don't capture weakly!
                self.protectionTimer.updateTime(timeRemaining)
            } else {
                // Protection expired or stopped
                print("⏹️  [ProtectionTimer] Stopping (time: \(timeRemaining)s, active: \(monitor.protectionActive))")
                timerWrapper?.timer?.invalidate()
                timerWrapper?.timer = nil
                self.protectionTimer.hideProtection()
            }
        }
    }

    private func hideProtectionTimer() {
        timerWrapper.timer?.invalidate()
        timerWrapper.timer = nil
        protectionTimer.hideProtection()
    }
    #endif
}
