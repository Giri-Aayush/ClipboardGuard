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

    // MARK: - User Copy Detection

    var lastUserCopyTime: Date?  // Set by PasteDetector callback
    private let userCopyWindow: TimeInterval = 0.5  // 500ms window

    /// Ultra-fast polling interval (5ms = 200 checks per second)
    private let pollingInterval: DispatchTimeInterval = .milliseconds(5)

    // MARK: - Callbacks

    /// Called when a crypto address is copied (detected)
    var onCryptoCopied: ((String, CryptoType) -> Void)?

    /// Called when a crypto address is pasted (verified)
    var onCryptoPasted: ((String, CryptoType) -> Void)?

    /// Called when clipboard hijacking is detected
    var onHijackDetected: ((String, String) -> Void)?

    /// Called when clipboard changes to non-crypto content during protection
    var onNonCryptoContentCopied: (() -> Void)?

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
        guard !isMonitoring else { return }

        // Update state ON MAIN THREAD
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = true
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

    // MARK: - Protection Management

    /// Starts protecting a specific address for 2 minutes
    func startProtection(for address: String, type: CryptoType) {
        // Cancel any existing protection timer
        DispatchQueue.main.async { [weak self] in
            self?.protectionExpiryTimer?.invalidate()
        }

        // Store what we're protecting
        monitoredContent = address
        monitoredContentHash = hashContent(address)
        protectionStartTime = Date()

        // Update UI state AND create timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.protectionActive = true
            self.protectionTimeRemaining = self.protectionDuration

            // CRITICAL: Timer MUST be created on main thread!
            self.protectionExpiryTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateProtectionTimer()
            }

            print("🛡️ [Protection] Timer created on main thread")
            print("   Timer valid: \(self.protectionExpiryTimer?.isValid ?? false)")
        }

        print("🛡️ [Protection] Started protecting \(type.rawValue) for 2 minutes")
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

        // PARANOID MODE: Always check for hijacking if we're monitoring content
        // This catches sophisticated malware that might not update changeCount
        if monitoredContent != nil {
            checkForHijacking()
        }

        // Check if clipboard content changed
        guard currentChangeCount != lastChangeCount else {
            return  // No new clipboard change
        }

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
        print("🔍 Detected \(type.rawValue) address")

        // Store content and hash for hijack detection
        monitoredContent = content
        monitoredContentHash = hashContent(content)

        // Update published properties ON MAIN THREAD
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastDetectedAddress = self.maskAddress(content)
            self.lastDetectedCryptoType = type
        }

        // Check if this was a paste event or copy event
        if isPasteEvent {
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
            print("   👁️  COPY EVENT - Showing monitoring indicator")
            onCryptoCopied?(content, type)

            // Update copy count ON MAIN THREAD
            DispatchQueue.main.async { [weak self] in
                self?.copyCount += 1
            }
        }
    }

    /// Checks if the monitored clipboard content has been hijacked
    /// Uses TIME-CORRELATION to distinguish user copies from malware
    private func checkForHijacking() {
        guard let originalContent = monitoredContent,
              let originalHash = monitoredContentHash else {
            return
        }

        // Read current clipboard content
        #if os(macOS)
        guard let currentContent = NSPasteboard.general.string(forType: .string) else { return }
        #elseif os(iOS)
        guard let currentContent = UIPasteboard.general.string else { return }
        #endif

        // Compare hashes
        let currentHash = hashContent(currentContent)

        if currentHash != originalHash {
            // Clipboard changed! But was it the USER or MALWARE?

            // TIME-CORRELATION CHECK:
            // If clipboard change happened within 500ms of Cmd+C, it was the user
            if let lastCopy = lastUserCopyTime,
               Date().timeIntervalSince(lastCopy) < userCopyWindow {
                // USER INTENTIONALLY COPIED NEW CONTENT
                print("🔄 [Smart Protection] User copied new content - switching protection")
                print("   Old: \(maskAddress(originalContent))")
                print("   New: \(maskAddress(currentContent))")

                // Check if it's another crypto address
                if let newType = patternMatcher.detectCryptoType(currentContent) {
                    // Switch protection to new address
                    print("   ✅ New address is \(newType.rawValue) - protecting it now")
                    startProtection(for: currentContent, type: newType)
                } else {
                    // Not a crypto address, stop protection and show warning
                    print("   ⚠️  Not a crypto address - stopping protection and showing warning")
                    stopProtection()

                    // Notify that non-crypto content was copied
                    onNonCryptoContentCopied?()
                }
            } else {
                // NO RECENT CMD+C EVENT - MALWARE HIJACKING!
                print("🚨 HIJACK DETECTED!")
                print("   Original:  \(maskAddress(originalContent))")
                print("   Hijacked:  \(maskAddress(currentContent))")
                print("   No Cmd+C detected - MALWARE changed clipboard!")
                print("   Will block on paste attempt")

                // Update statistics ON MAIN THREAD
                DispatchQueue.main.async { [weak self] in
                    self?.threatsBlocked += 1
                }

                // Notify callback (for UI notification)
                onHijackDetected?(originalContent, currentContent)
            }
        }
    }

    // REMOVED: No automatic clipboard restoration
    // User should be free to copy anything they want
    // Protection happens at PASTE time via PasteBlocker

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
