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

/// Detects when user pastes content (Cmd+V or Edit > Paste)
#if os(macOS)
class PasteDetector: ObservableObject {

    // MARK: - Published Properties

    @Published var didPaste: Bool = false

    // MARK: - Private Properties

    private var eventMonitor: Any?
    private var lastPasteTime: Date = .distantPast

    // MARK: - Callbacks

    /// Called when paste is detected
    var onPasteDetected: (() -> Void)?

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
        // Check for Cmd+V (paste)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            handlePaste()
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
}
#endif
