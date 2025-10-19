//
//  PasteBlocker.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation
#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// Intercepts paste events and blocks them if clipboard has been hijacked
class PasteBlocker {

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Callback when paste should be blocked (shows red alert)
    var onPasteBlocked: ((String, String) -> Void)?

    /// Function to check if current clipboard is safe to paste
    var shouldBlockPaste: (() -> (shouldBlock: Bool, original: String, hijacked: String))?

    // MARK: - Initialization

    init() {
        setupEventTap()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Setup

    private func setupEventTap() {
        // Check for accessibility permissions
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️  [PasteBlocker] No Accessibility permissions - paste blocking disabled")
            print("   To enable: System Settings → Privacy & Security → Accessibility → Enable Clipboard")
            requestAccessibilityPermissions()
            return
        }

        print("✅ [PasteBlocker] Accessibility permissions granted")

        // Create event tap to intercept Command+V
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let blocker = Unmanaged<PasteBlocker>.fromOpaque(refcon!).takeUnretainedValue()
                return blocker.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ [PasteBlocker] Failed to create event tap")
            return
        }

        eventTap = tap

        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        print("⚡️ [PasteBlocker] Started paste event interception")
    }

    /// Requests accessibility permissions
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Only process key down events
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // Check if it's Command+V
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // keyCode 9 = V key
        let isCommandPressed = flags.contains(.maskCommand)
        let isVKey = (keyCode == 9)

        guard isCommandPressed && isVKey else {
            return Unmanaged.passUnretained(event)  // Not a paste event
        }

        print("🚨 [PasteBlocker] Command+V intercepted - checking if safe to paste...")

        // Check if we should block this paste
        guard let checkResult = shouldBlockPaste?() else {
            print("   ✅ No hijack check configured - allowing paste")
            return Unmanaged.passUnretained(event)
        }

        if checkResult.shouldBlock {
            print("   🛑 BLOCKING PASTE - Clipboard has been hijacked!")
            print("      Original:  \(maskAddress(checkResult.original))")
            print("      Hijacked:  \(maskAddress(checkResult.hijacked))")

            // Notify callback to show red alert
            DispatchQueue.main.async { [weak self] in
                self?.onPasteBlocked?(checkResult.original, checkResult.hijacked)
            }

            // Block the event by returning nil
            return nil
        } else {
            print("   ✅ Safe to paste - allowing")
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Control

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        print("📋 [PasteBlocker] Stopped paste interception")
    }

    // MARK: - Helpers

    private func maskAddress(_ address: String) -> String {
        guard address.count > 10 else { return "***" }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
}
#endif
