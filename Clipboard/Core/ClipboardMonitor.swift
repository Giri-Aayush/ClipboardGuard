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

    // MARK: - Private Properties

    private var timer: DispatchSourceTimer?
    private let monitorQueue = DispatchQueue(label: "com.clipboardguard.monitor", qos: .userInteractive)
    private let patternMatcher = PatternMatcher()
    private var lastChangeCount: Int = 0
    internal var monitoredContent: String?  // Accessible for instant paste verification
    private var monitoredContentHash: String?

    /// Ultra-fast polling interval (5ms = 200 checks per second)
    private let pollingInterval: DispatchTimeInterval = .milliseconds(5)

    // MARK: - Callbacks

    /// Called when a crypto address is copied (detected)
    var onCryptoCopied: ((String, CryptoType) -> Void)?

    /// Called when a crypto address is pasted (verified)
    var onCryptoPasted: ((String, CryptoType) -> Void)?

    /// Called when clipboard hijacking is detected
    var onHijackDetected: ((String, String) -> Void)?

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
            print("   ✅ PASTE EVENT - Showing verification indicator")
            onCryptoPasted?(content, type)
            isPasteEvent = false  // Reset

            // Update paste count ON MAIN THREAD
            DispatchQueue.main.async { [weak self] in
                self?.pasteCount += 1
            }
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
            // HIJACK DETECTED!
            // Only log it, DON'T auto-restore (let user copy other things freely)
            // Restoration will happen via paste blocker instead
            print("⚠️ HIJACK DETECTED!")
            print("   Original:  \(maskAddress(originalContent))")
            print("   Attempted: \(maskAddress(currentContent))")
            print("   Will block on paste attempt, not restoring clipboard now")

            // Update statistics ON MAIN THREAD
            DispatchQueue.main.async { [weak self] in
                self?.threatsBlocked += 1
            }

            // Notify callback (for UI notification, but don't restore)
            onHijackDetected?(originalContent, currentContent)
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
