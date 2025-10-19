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
    @StateObject private var pasteDetector = PasteDetector()
    private let pasteBlocker = PasteBlocker()
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

        // Setup paste detector
        #if os(macOS)
        pasteDetector.onPasteDetected = { [self] in
            // INSTANTLY show paste verification if we're monitoring a crypto address
            if let address = clipboardMonitor.monitoredContent,
               let type = clipboardMonitor.lastDetectedCryptoType {

                // Verify clipboard hasn't been hijacked
                let checkResult = clipboardMonitor.checkIfShouldBlockPaste()

                if !checkResult.shouldBlock {
                    // Safe paste - show green verification IMMEDIATELY
                    print("✅ INSTANT PASTE VERIFICATION for \(type.rawValue)")
                    DispatchQueue.main.async {
                        floatingIndicator.showPaste(for: type)
                    }

                    // Update statistics
                    DispatchQueue.main.async {
                        clipboardMonitor.pasteCount += 1
                    }
                }
                // If hijacked, the PasteBlocker will show red alert
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

            // Show orange "watching" indicator
            #if os(macOS)
            DispatchQueue.main.async {
                floatingIndicator.showCopy(for: type)
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

        // Auto-start monitoring if licensed
        if licenseManager.isLicensed {
            clipboardMonitor.startMonitoring()
        }
    }
}
