//
//  ClipboardApp.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI
import UserNotifications

#if os(macOS)
import AppKit

// CRITICAL: AppDelegate to prevent automatic window opening and desktop switching
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy to accessory to prevent dock icon and app switching
        NSApp.setActivationPolicy(.accessory)

        // Add menu bar icon so users can still access the app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Modern minimal icon: doc.on.clipboard.fill (clipboard with protection indicator)
            button.image = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "ClipboardGuard")
            button.action = #selector(showMainWindow)
            button.target = self
        }
    }

    @objc func showMainWindow() {
        // Temporarily switch to regular app to show window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find and show the main window
        for window in NSApp.windows {
            if window.title.isEmpty || window.contentView is NSHostingView<ContentView> {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }

        // Switch back to accessory after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
#endif

@main
struct ClipboardApp: App {

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    // MARK: - State Objects

    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    #if os(macOS)
    private let floatingIndicator = FloatingIndicatorWindow()
    private let blockedPasteAlert = BlockedPasteAlertWindow()
    private let notchManager = DynamicNotchManager()
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
        // CRITICAL: Don't auto-show window when app activates
        .defaultSize(width: 800, height: 600)
        .commandsRemoved()
        #endif
    }

    // MARK: - Setup

    private func setupApp() {
        let notificationManager = NotificationManager.shared

        // Request notification permission
        Task {
            await notificationManager.requestAuthorization()
        }

        // Setup COPY detector (Cmd+C) - Regular copy
        #if os(macOS)
        pasteDetector.onCopyDetected = { [self] in
            // Record timestamp for time-correlation
            clipboardMonitor.lastUserCopyTime = pasteDetector.lastUserCopyTimestamp
            print("⏱️  [Copy] Cmd+C detected at \(Date())")
        }

        // Setup INTENTIONAL COPY detector (Option+Cmd+C) - Instant protection
        pasteDetector.onIntentionalCopyDetected = { [self] in
            print("🔐 [IntentionalCopy] Option+Cmd+C detected - INSTANT PROTECTION")

            // CHECK: If protection is already active, show warning instead
            if self.clipboardMonitor.protectionActive {
                print("⚠️  [IntentionalCopy] Protection already active - showing locked warning")

                // Play beep for audio feedback
                #if os(macOS)
                NSSound.beep()
                #endif

                // Show warning in notch
                Task { @MainActor in
                    await self.notchManager.showWarning("🔒 Clipboard is locked - protection active!")
                }
                return
            }

            // CRITICAL: Wait for clipboard to update (copy event happens AFTER keypress)
            // Option+Cmd+C means user is ABOUT to copy - clipboard updates ~50ms later
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Read clipboard to check if it's a crypto address
                #if os(macOS)
                guard let clipboardContent = NSPasteboard.general.string(forType: .string) else {
                    print("⚠️  No string in clipboard")
                    return
                }
                #endif

                // Detect crypto type using pattern matcher
                let patternMatcher = PatternMatcher()
                guard let detectedType = patternMatcher.detectCryptoType(clipboardContent) else {
                    print("ℹ️  Not a crypto address - ignoring Option+Cmd+C")
                    return
                }

                print("✅ Crypto address detected: \(detectedType.rawValue)")

                // Show toast notification first
                Task { @MainActor in
                    await self.notchManager.showProtectionEnabledToast(for: detectedType)

                    // Wait for toast to auto-hide (2 seconds) plus animation time
                    try? await Task.sleep(for: .seconds(2.8))

                    // Ensure toast is fully hidden before showing timer
                    await self.notchManager.hideToast()

                    // Now enable protection (this will trigger onProtectionConfirmed callback which shows timer)
                    self.clipboardMonitor.enableInstantProtection(address: clipboardContent, type: detectedType)
                }
            }
        }

        // Setup ESCAPE key detector - dismiss protection
        pasteDetector.onEscapePressed = { [self] in
            guard clipboardMonitor.protectionActive else {
                print("ℹ️  Escape pressed but no active protection")
                return
            }

            print("🔓 [Escape] User manually dismissed protection")

            // Stop protection
            clipboardMonitor.stopProtection()

            // Hide the timer widget
            Task { @MainActor in
                await notchManager.hideProtectionTimer()
            }

            // Stop timer update loop
            timerWrapper.timer?.invalidate()
            timerWrapper.timer = nil
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

        // Setup clipboard monitoring callbacks - NEW OPT-IN FLOW
        clipboardMonitor.onCryptoDetected = { [self] address, type in
            print("📋 CRYPTO DETECTED: \(type.rawValue) address")
            print("   🔒 Hash captured immediately")

            // Show confirmation widget in notch
            #if os(macOS)
            DispatchQueue.main.async {
                // Show blue copy indicator at cursor
                floatingIndicator.showCopy(for: type)

                // Show confirmation widget (asks user to enable protection)
                self.showConfirmationWidget(address: address, type: type)
            }
            #endif
        }

        clipboardMonitor.onProtectionConfirmed = { [self] type, address in
            print("🛡️ PROTECTION CONFIRMED by user")

            // Show protection timer widget
            #if os(macOS)
            DispatchQueue.main.async {
                self.showProtectionTimer(for: type)
            }
            #endif
        }

        clipboardMonitor.onMalwareDetectedDuringConfirmation = { [self] original, hijacked in
            print("🚨 MALWARE DETECTED DURING CONFIRMATION!")

            // Show critical alert
            #if os(macOS)
            DispatchQueue.main.async {
                self.blockedPasteAlert.showHijackDuringConfirmation(
                    original: original,
                    hijacked: hijacked
                )
            }
            #endif
        }

        clipboardMonitor.onClipboardLockWarning = { [self] message in
            print("🔒 [CLIPBOARD LOCKED] \(message)")

            // Show warning in notch
            #if os(macOS)
            Task { @MainActor in
                await self.notchManager.showWarning("⚠️ Clipboard is locked during protection")
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

        // Hijack detected during protection (when paste is attempted)
        clipboardMonitor.onHijackDetected = { original, attempted in
            print("🚨 Hijack detected on paste attempt!")
            // Paste blocker will show red alert at cursor
        }

        // Auto-start monitoring if licensed
        print("🔍 [Setup] Checking license status...")
        print("   Licensed: \(licenseManager.isLicensed)")

        if licenseManager.isLicensed {
            print("✅ [Setup] License valid - starting clipboard monitoring")
            clipboardMonitor.startMonitoring()
        } else {
            print("❌ [Setup] No valid license - monitoring NOT started")
        }
    }

    // MARK: - Protection Flow Management

    #if os(macOS)
    private func showConfirmationWidget(address: String, type: CryptoType) {
        print("🔐 [Confirmation] Showing opt-in widget for \(type.rawValue)")

        // Show confirmation widget in notch
        Task { @MainActor in
            await notchManager.showConfirmation(
                address: address,
                type: type,
                onConfirm: { [weak clipboardMonitor, weak notchManager] in
                    print("✅ [Confirmation] User clicked 'Enable Protection'")

                    // Hide confirmation widget immediately
                    Task { @MainActor in
                        await notchManager?.hideConfirmation()

                        // Small delay for smooth transition (just animation time)
                        try? await Task.sleep(for: .milliseconds(100))

                        // Confirm protection (this triggers onProtectionConfirmed which shows timer)
                        clipboardMonitor?.confirmProtection()
                    }
                },
                onDismiss: { [weak clipboardMonitor] in
                    print("❌ [Confirmation] User dismissed")
                    clipboardMonitor?.dismissPendingProtection()
                }
            )
        }
    }

    private func showProtectionTimer(for type: CryptoType) {
        print("🎯 [ProtectionTimer] Showing notch widget for \(type.rawValue)")
        print("   Time remaining: \(clipboardMonitor.protectionTimeRemaining)s")

        // Stop any existing timer update loop
        timerWrapper.timer?.invalidate()
        timerWrapper.timer = nil

        // Show the timer in the notch
        Task { @MainActor in
            await notchManager.showProtectionTimer(
                for: type,
                timeRemaining: clipboardMonitor.protectionTimeRemaining,
                onDismiss: { [weak timerWrapper, weak clipboardMonitor] in
                    print("❌ [ProtectionTimer] User dismissed via × button")
                    timerWrapper?.timer?.invalidate()
                    timerWrapper?.timer = nil
                    clipboardMonitor?.stopProtection()
                }
            )
        }

        // Start updating the timer every 0.1 seconds for smooth countdown
        print("🔄 [ProtectionTimer] Starting update loop (every 0.1s)")

        var lastLoggedSecond = -1
        timerWrapper.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak timerWrapper, weak clipboardMonitor, weak notchManager] _ in
            guard let monitor = clipboardMonitor else { return }
            let timeRemaining = monitor.protectionTimeRemaining

            // Log every second to avoid spam
            let currentSecond = Int(timeRemaining)
            if currentSecond != lastLoggedSecond {
                print("🔄 [ProtectionTimer] Updating: \(currentSecond)s, active: \(monitor.protectionActive)")
                lastLoggedSecond = currentSecond
            }

            if timeRemaining > 0 && monitor.protectionActive {
                // Update the view model time
                DispatchQueue.main.async {
                    notchManager?.updateTimer(timeRemaining)
                }
            } else {
                // Protection expired or stopped
                print("⏹️  [ProtectionTimer] Stopping (time: \(timeRemaining)s, active: \(monitor.protectionActive))")
                timerWrapper?.timer?.invalidate()
                timerWrapper?.timer = nil
                Task { @MainActor in
                    await notchManager?.hideProtectionTimer()
                }
            }
        }
    }

    private func hideProtectionTimer() {
        timerWrapper.timer?.invalidate()
        timerWrapper.timer = nil
        Task { @MainActor in
            await notchManager.hideProtectionTimer()
        }
    }
    #endif
}
