//
//  ClipboardMonitor.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation
import Combine
import CommonCrypto
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Monitors system clipboard for cryptocurrency addresses
/// Target: <1% CPU usage, <100ms detection latency
class ClipboardMonitor: ObservableObject {

    // MARK: - Published Properties

    @Published var isMonitoring: Bool = false
    @Published var lastDetectedAddress: String?
    @Published var lastDetectedCryptoType: CryptoType?
    @Published var checksToday: Int = 0
    @Published var threatsBlocked: Int = 0
    @Published var pasteCount: Int = 0
    @Published var copyCount: Int = 0
    @Published var protectionActive: Bool = false
    @Published var protectionTimeRemaining: TimeInterval = 0

    // MARK: - Private Properties

    private var timer: DispatchSourceTimer?
    private let monitorQueue = DispatchQueue(label: "com.clipboardguard.monitor", qos: .userInteractive)
    private let patternMatcher = PatternMatcher()
    private var lastChangeCount: Int = 0
    internal var monitoredContent: String?  // Accessible for instant paste verification
    private var monitoredContentHash: String?

    // MARK: - Protection Timer

    private var protectionStartTime: Date?
    private var protectionExpiryTimer: Timer?
    private let protectionDuration: TimeInterval = 120 // 2 minutes (like Opera)

    // MARK: - Pending Protection (Opt-In Flow)

    /// Temporary storage during confirmation period - captured IMMEDIATELY on copy
    private var pendingAddress: String?
    private var pendingHash: String?
    private var pendingType: CryptoType?
    private var pendingCaptureTime: Date?
    private var pendingMonitorTimer: Timer?

    // MARK: - User Copy Detection

    var lastUserCopyTime: Date?  // Set by PasteDetector callback
    private let userCopyWindow: TimeInterval = 0.5  // 500ms window

    /// Ultra-fast polling interval (5ms = 200 checks per second)
    private let pollingInterval: DispatchTimeInterval = .milliseconds(5)

    // MARK: - Callbacks

    /// Called when a crypto address is detected - shows confirmation widget
    var onCryptoDetected: ((String, CryptoType) -> Void)?

    /// Called when a crypto address is pasted (verified)
    var onCryptoPasted: ((String, CryptoType) -> Void)?

    /// Called when clipboard hijacking is detected
    var onHijackDetected: ((String, String) -> Void)?

    /// Called when malware detected during confirmation period
    var onMalwareDetectedDuringConfirmation: ((String, String) -> Void)?

    /// Called when clipboard changes to non-crypto content during protection
    var onNonCryptoContentCopied: (() -> Void)?

    /// Called when user confirms protection - shows timer widget
    var onProtectionConfirmed: ((CryptoType, String) -> Void)?

    /// Called when clipboard is locked (user tried to copy during protection)
    var onClipboardLockWarning: ((String) -> Void)?

    // MARK: - Paste Detection

    var isPasteEvent: Bool = false

    // MARK: - Paste Blocking

    /// Checks if current clipboard content has been hijacked
    /// Returns (shouldBlock, original, hijacked) tuple
    func checkIfShouldBlockPaste() -> (shouldBlock: Bool, original: String, hijacked: String) {
        guard let originalContent = monitoredContent,
              let originalHash = monitoredContentHash else {
            // Not monitoring any crypto address
            return (false, "", "")
        }

        // Read current clipboard content
        #if os(macOS)
        guard let currentContent = NSPasteboard.general.string(forType: .string) else {
            return (false, "", "")
        }
        #elseif os(iOS)
        guard let currentContent = UIPasteboard.general.string else {
            return (false, "", "")
        }
        #endif

        // Compare hashes
        let currentHash = hashContent(currentContent)

        if currentHash != originalHash {
            // HIJACK DETECTED - should block paste
            return (true, originalContent, currentContent)
        } else {
            // Safe to paste
            return (false, originalContent, currentContent)
        }
    }

    // MARK: - Initialization

    init() {
        #if os(macOS)
        lastChangeCount = NSPasteboard.general.changeCount
        #elseif os(iOS)
        lastChangeCount = UIPasteboard.general.changeCount
        #endif
    }

    // MARK: - Public Methods

    /// Starts ULTRA-FAST continuous clipboard monitoring (5ms intervals)
    func startMonitoring() {
        print("🎬 [ClipboardMonitor] startMonitoring() called")
        print("   Currently monitoring: \(isMonitoring)")

        guard !isMonitoring else {
            print("   ⚠️ Already monitoring - skipping")
            return
        }

        print("   ✅ Starting new monitoring session...")

        // Update state ON MAIN THREAD
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = true
            print("   📊 [Main] isMonitoring set to TRUE")
        }

        // Create high-priority dispatch timer for ultra-fast polling
        timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer?.schedule(deadline: .now(), repeating: pollingInterval, leeway: .milliseconds(1))

        timer?.setEventHandler { [weak self] in
            self?.ultraFastCheck()
        }

        timer?.resume()

        print("⚡️ ClipboardMonitor: Started ULTRA-FAST monitoring (5ms = 200 checks/second)")
    }

    /// Stops clipboard monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }

        timer?.cancel()
        timer = nil

        // Update state ON MAIN THREAD
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = false
        }

        // Clear stored data
        monitoredContent = nil
        monitoredContentHash = nil

        print("📋 ClipboardMonitor: Stopped monitoring")
    }

    // MARK: - Protection Management (Opt-In Flow)

    /// User clicked "Enable Protection" - verify and activate
    func confirmProtection() {
        guard let originalAddress = pendingAddress,
              let originalHash = pendingHash,
              let type = pendingType else {
            print("⚠️  [Security] No pending protection to confirm")
            return
        }

        print("✅ [Security] User confirmed protection")

        // CRITICAL: Verify clipboard hasn't changed since capture
        #if os(macOS)
        guard let currentClipboard = NSPasteboard.general.string(forType: .string) else {
            print("⚠️  [Security] Clipboard is empty now - cannot enable protection")
            clearPendingProtection()
            return
        }
        #elseif os(iOS)
        guard let currentClipboard = UIPasteboard.general.string else {
            print("⚠️  [Security] Clipboard is empty now - cannot enable protection")
            clearPendingProtection()
            return
        }
        #endif

        let currentHash = hashContent(currentClipboard)
        let elapsed = Date().timeIntervalSince(pendingCaptureTime ?? Date())

        // VERIFICATION CHECK
        if currentHash != originalHash {
            // 🚨 CLIPBOARD WAS HIJACKED DURING CONFIRMATION!
            print("🚨 [CRITICAL] HIJACKING DETECTED AT CONFIRMATION!")
            print("   Original: \(maskAddress(originalAddress))")
            print("   Current:  \(maskAddress(currentClipboard))")
            print("   Duration: \(String(format: "%.3f", elapsed))s")

            // Increment threats blocked
            DispatchQueue.main.async { [weak self] in
                self?.threatsBlocked += 1
            }

            // Show critical alert
            onMalwareDetectedDuringConfirmation?(originalAddress, currentClipboard)

            clearPendingProtection()
            return
        }

        // ✅ VERIFICATION PASSED - Safe to enable protection
        print("✅ [Security] Verification passed - clipboard unchanged")
        print("   Elapsed: \(String(format: "%.3f", elapsed))s")
        print("   Using original hash captured at copy time")

        // Enable protection with ORIGINAL hash
        monitoredContent = originalAddress
        monitoredContentHash = originalHash  // Use hash captured IMMEDIATELY on copy
        protectionActive = true
        protectionStartTime = Date()

        // Create timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.protectionTimeRemaining = self.protectionDuration

            // Timer for auto-expiry
            self.protectionExpiryTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateProtectionTimer()
            }

            print("🛡️ [Protection] Timer created on main thread")
            print("   Timer valid: \(self.protectionExpiryTimer?.isValid ?? false)")
        }

        // Notify callback to show protection timer widget
        onProtectionConfirmed?(type, originalAddress)

        // Clear pending data
        clearPendingProtection()

        print("🛡️ [Protection] ACTIVATED for \(type.rawValue)")
    }

    /// User clicked "Dismiss" or timeout
    func dismissPendingProtection() {
        print("ℹ️  [Security] User dismissed protection confirmation")
        clearPendingProtection()
    }

    /// Instantly enable protection (for Option+Cmd+C shortcut)
    func enableInstantProtection(address: String, type: CryptoType) {
        print("⚡ [InstantProtection] Enabling protection immediately")

        let capturedHash = hashContent(address)

        monitoredContent = address
        monitoredContentHash = capturedHash
        lastDetectedCryptoType = type
        protectionActive = true
        protectionStartTime = Date()

        // Create timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.protectionTimeRemaining = self.protectionDuration

            // Invalidate old timer if exists
            self.protectionExpiryTimer?.invalidate()

            // Timer for auto-expiry
            self.protectionExpiryTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateProtectionTimer()
            }

            print("⏱️  [InstantProtection] Timer created")
        }

        // Notify callback to show protection timer widget
        onProtectionConfirmed?(type, address)

        print("✅ [InstantProtection] Active for \(type.rawValue)")
    }

    /// Clears pending protection data
    private func clearPendingProtection() {
        pendingMonitorTimer?.invalidate()
        pendingMonitorTimer = nil
        pendingAddress = nil
        pendingHash = nil
        pendingType = nil
        pendingCaptureTime = nil

        print("🗑️  [Security] Pending protection cleared")
    }

    /// Stops protection (user clicked × or paste completed)
    func stopProtection() {
        protectionExpiryTimer?.invalidate()
        protectionExpiryTimer = nil
        protectionStartTime = nil
        monitoredContent = nil
        monitoredContentHash = nil

        DispatchQueue.main.async { [weak self] in
            self?.protectionActive = false
            self?.protectionTimeRemaining = 0
        }

        print("🛡️ [Protection] Stopped")
    }

    /// Updates protection timer countdown
    private func updateProtectionTimer() {
        guard let startTime = protectionStartTime else {
            print("⚠️  [ClipboardMonitor] updateProtectionTimer: startTime is nil")
            stopProtection()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = max(0, protectionDuration - elapsed)

        // Log every second
        let currentSecond = Int(remaining)
        if currentSecond != Int(protectionTimeRemaining) {
            print("⏱️  [ClipboardMonitor] protectionTimeRemaining: \(currentSecond)s (elapsed: \(Int(elapsed))s)")
        }

        DispatchQueue.main.async { [weak self] in
            self?.protectionTimeRemaining = remaining
        }

        // Auto-expire after 2 minutes
        if remaining <= 0 {
            print("🛡️ [Protection] Auto-expired after 2 minutes")
            stopProtection()
        }
    }

    // MARK: - Private Methods

    /// ULTRA-FAST monitoring check - called every 5ms (200 times per second)
    /// Optimized for <1ms execution time
    private func ultraFastCheck() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        #elseif os(iOS)
        let pasteboard = UIPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        #endif

        // Check if clipboard content changed
        guard currentChangeCount != lastChangeCount else {
            return  // No new clipboard change
        }

        print("📋 [ClipboardMonitor] Clipboard change detected!")
        print("   Previous count: \(lastChangeCount)")
        print("   Current count: \(currentChangeCount)")

        // Update change count
        lastChangeCount = currentChangeCount

        // Update statistics on main thread
        DispatchQueue.main.async { [weak self] in
            self?.checksToday += 1
        }

        // Read clipboard content
        #if os(macOS)
        guard let content = pasteboard.string(forType: .string) else {
            print("📋 [DEBUG] Clipboard changed but no string content")
            return
        }
        #elseif os(iOS)
        guard let content = pasteboard.string else {
            print("📋 [DEBUG] Clipboard changed but no string content")
            return
        }
        #endif

        // Trim whitespace
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        print("📋 [DEBUG] Clipboard changed!")
        print("   📝 Content: \"\(trimmedContent.prefix(100))\(trimmedContent.count > 100 ? "..." : "")\"")
        print("   📏 Length: \(trimmedContent.count) characters")

        // CRITICAL: If protection is active, LOCK the clipboard - restore protected address
        if protectionActive, let protectedAddress = monitoredContent {
            let newHash = hashContent(trimmedContent)

            // If clipboard changed to something else during protection
            if newHash != monitoredContentHash {
                print("🚨 [CLIPBOARD LOCKED] User tried to copy something else during protection!")
                print("   ❌ Blocked: \"\(trimmedContent.prefix(30))...\"")
                print("   ✅ Restoring protected address")

                // RESTORE the protected address immediately
                #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(protectedAddress, forType: .string)
                lastChangeCount = pasteboard.changeCount  // Update to prevent re-trigger

                // Play system beep sound for audio feedback
                NSSound.beep()
                #endif

                // Show warning in protection timer
                DispatchQueue.main.async { [weak self] in
                    self?.onClipboardLockWarning?("Clipboard locked during protection")
                }

                return  // Don't process this change
            }
        }

        // Check if it's a crypto address
        if let cryptoType = patternMatcher.detectCryptoType(trimmedContent) {
            print("   ✅ MATCHED: \(cryptoType.rawValue)")
            handleCryptoAddressDetected(content: trimmedContent, type: cryptoType)
        } else {
            print("   ❌ Not a crypto address")
            // Not a crypto address, stop monitoring this content
            monitoredContent = nil
            monitoredContentHash = nil
        }
    }

    /// Handles detection of a cryptocurrency address
    private func handleCryptoAddressDetected(content: String, type: CryptoType) {
        print("🔍 [handleCryptoAddressDetected] Detected \(type.rawValue) address")
        print("   Address: \(maskAddress(content))")
        print("   isPasteEvent: \(isPasteEvent)")
        print("   protectionActive: \(protectionActive)")

        // Update published properties ON MAIN THREAD
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastDetectedAddress = self.maskAddress(content)
            self.lastDetectedCryptoType = type
            print("   ✅ Updated lastDetectedAddress and type on main thread")
        }

        // Check if this was a paste event or copy event
        print("   🔀 Checking if paste or copy event...")
        if isPasteEvent {
            print("   ✅ This is a PASTE event")
            // Only show verification if pasting the PROTECTED address
            if protectionActive && monitoredContent == content {
                print("   ✅ PASTE EVENT - Protected address verified!")
                onCryptoPasted?(content, type)

                // Update paste count ON MAIN THREAD
                DispatchQueue.main.async { [weak self] in
                    self?.pasteCount += 1
                }
            } else {
                print("   ℹ️  PASTE EVENT - Different content (not the protected address)")
            }
            isPasteEvent = false  // Reset
        } else {
            // COPY EVENT - Start opt-in protection flow
            print("   👁️  COPY EVENT - Starting opt-in protection flow")

            // CRITICAL: Capture hash IMMEDIATELY (before malware can act)
            capturePendingProtection(address: content, type: type)

            // Update copy count ON MAIN THREAD
            DispatchQueue.main.async { [weak self] in
                self?.copyCount += 1
            }
        }
    }

    /// SECURITY: Captures hash immediately on copy detection
    private func capturePendingProtection(address: String, type: CryptoType) {
        let captureTime = Date()
        let capturedHash = hashContent(address)

        print("🔒 [Security] IMMEDIATE HASH CAPTURE")
        print("   Address: \(maskAddress(address))")
        print("   Hash: \(capturedHash.prefix(16))...")
        print("   Time: \(captureTime)")

        // Store immediately in RAM
        pendingAddress = address
        pendingHash = capturedHash
        pendingType = type
        pendingCaptureTime = captureTime

        // Show confirmation widget to user (async, safe)
        DispatchQueue.main.async { [weak self] in
            self?.onCryptoDetected?(address, type)
        }

        // Start monitoring for clipboard changes during confirmation
        startPendingProtectionMonitoring()

        // Auto-dismiss after 10 seconds if user doesn't respond
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            if self?.pendingHash != nil {
                print("⏱️  [Security] Confirmation timeout - auto-dismissing")
                self?.dismissPendingProtection()
            }
        }
    }

    /// Monitors clipboard during confirmation period (detects hijacking attempts)
    private func startPendingProtectionMonitoring() {
        // Invalidate any existing monitor
        pendingMonitorTimer?.invalidate()

        // Check every 100ms if clipboard changed during confirmation
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.pendingMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self,
                      let originalHash = self.pendingHash,
                      let originalAddress = self.pendingAddress else {
                    timer.invalidate()
                    return
                }

                // Get current clipboard
                #if os(macOS)
                guard let currentClipboard = NSPasteboard.general.string(forType: .string) else {
                    return
                }
                #elseif os(iOS)
                guard let currentClipboard = UIPasteboard.general.string else {
                    return
                }
                #endif

                let currentHash = self.hashContent(currentClipboard)

                // DETECT CHANGE DURING CONFIRMATION!
                if currentHash != originalHash {
                    let elapsed = Date().timeIntervalSince(self.pendingCaptureTime ?? Date())

                    print("🚨 [CRITICAL] CLIPBOARD HIJACKED DURING CONFIRMATION!")
                    print("   Original: \(originalAddress)")
                    print("   Current:  \(currentClipboard)")
                    print("   Original Hash: \(originalHash.prefix(16))...")
                    print("   Current Hash:  \(currentHash.prefix(16))...")
                    print("   Elapsed: \(String(format: "%.3f", elapsed))s")

                    timer.invalidate()

                    // Increment threats blocked
                    DispatchQueue.main.async {
                        self.threatsBlocked += 1
                    }

                    // Alert user immediately
                    self.onMalwareDetectedDuringConfirmation?(originalAddress, currentClipboard)

                    // Clear pending protection
                    self.clearPendingProtection()
                }
            }
        }
    }

    // REMOVED: Old time-correlation logic (replaced with opt-in confirmation)
    // New security model: User explicitly confirms protection, eliminating timing attacks

    // MARK: - Helper Methods

    /// Creates SHA-256 hash of content
    private func hashContent(_ content: String) -> String {
        guard let data = content.data(using: .utf8) else { return "" }
        return data.sha256Hash
    }

    /// Masks address for logging (shows first 6 and last 4 characters)
    private func maskAddress(_ address: String) -> String {
        guard address.count > 10 else { return "***" }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
}

// MARK: - Data Extension for SHA-256

extension Data {
    var sha256Hash: String {
        let hash = withUnsafeBytes { bytes -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes.baseAddress, CC_LONG(count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
