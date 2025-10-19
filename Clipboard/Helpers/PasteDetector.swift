//
//  PasteDetector.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation
#if os(macOS)
import AppKit
import Combine
#endif

/// Detects when user copies (Cmd+C) or pastes (Cmd+V) content
#if os(macOS)
class PasteDetector: ObservableObject {

    // MARK: - Published Properties

    @Published var didPaste: Bool = false
    @Published var didCopy: Bool = false

    // MARK: - Private Properties

    private var eventMonitor: Any?
    private var lastPasteTime: Date = .distantPast
    private var lastCopyTime: Date = .distantPast

    // MARK: - Callbacks

    /// Called when paste is detected
    var onPasteDetected: (() -> Void)?

    /// Called when copy is detected (Cmd+C)
    var onCopyDetected: (() -> Void)?

    // MARK: - Initialization

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    /// Starts monitoring for paste events
    func startMonitoring() {
        // Check if we have accessibility permissions
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️  [PasteDetector] No Accessibility permissions - paste detection disabled")
            print("   To enable: System Settings → Privacy & Security → Accessibility → Enable Clipboard")
            print("   Requesting permissions now...")

            // Request permissions
            requestAccessibilityPermissions()

            // Still monitor local events (works without permissions when app is focused)
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
                return event
            }
            return
        }

        print("✅ [PasteDetector] Accessibility permissions granted")

        // Monitor for Cmd+V keypresses globally
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Also monitor local events (when app is focused)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        print("📋 [PasteDetector] Started monitoring for paste events")
    }

    /// Requests accessibility permissions
    func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
    }

    /// Stops monitoring
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased()

        // Check for Cmd+V (paste)
        if cmd && key == "v" {
            handlePaste()
        }
        // Check for Cmd+C (copy)
        else if cmd && key == "c" {
            handleCopy()
        }
    }

    private func handlePaste() {
        // Debounce - ignore rapid pastes within 500ms
        let now = Date()
        guard now.timeIntervalSince(lastPasteTime) > 0.5 else {
            return
        }

        lastPasteTime = now

        print("📋 [PasteDetector] ⌘V detected - USER PASTED!")

        // Notify
        DispatchQueue.main.async { [weak self] in
            self?.didPaste = true
            self?.onPasteDetected?()

            // Reset after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.didPaste = false
            }
        }
    }

    private func handleCopy() {
        // Debounce - ignore rapid copies within 300ms
        let now = Date()
        guard now.timeIntervalSince(lastCopyTime) > 0.3 else {
            return
        }

        lastCopyTime = now

        print("📋 [PasteDetector] ⌘C detected - USER COPIED!")

        // Notify
        DispatchQueue.main.async { [weak self] in
            self?.didCopy = true
            self?.onCopyDetected?()

            // Reset after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.didCopy = false
            }
        }
    }

    // MARK: - Public API

    /// Returns the timestamp of the last user copy event
    var lastUserCopyTimestamp: Date {
        return lastCopyTime
    }
}
#endif
