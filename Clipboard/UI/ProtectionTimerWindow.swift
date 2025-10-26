//
//  ProtectionTimerWindow.swift
//  Clipboard
//
//  Created by Aayush Giri on 19/10/25.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit

/// View model for the protection timer
class ProtectionTimerViewModel: ObservableObject {
    @Published var cryptoType: CryptoType
    @Published var timeRemaining: TimeInterval
    @Published var warningMessage: String?
    @Published var showWarning: Bool = false
    var onDismiss: (() -> Void)?

    init(cryptoType: CryptoType, timeRemaining: TimeInterval, onDismiss: @escaping () -> Void) {
        self.cryptoType = cryptoType
        self.timeRemaining = timeRemaining
        self.onDismiss = onDismiss
    }

    func updateTime(_ time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let oldTime = self.timeRemaining

            // Manually trigger objectWillChange before updating
            self.objectWillChange.send()
            self.timeRemaining = time

            // Only log every second to avoid spam
            if Int(oldTime) != Int(time) {
                print("⏱️  [ViewModel] Timer updated: \(Int(time))s → UI should refresh")
            }
        }
    }

    func showWarning(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.warningMessage = message
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.showWarning = true
            }

            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.hideWarning()
            }
        }
    }

    func hideWarning() {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self?.showWarning = false
            }
            // Notify window to collapse
            self?.onWarningDismissed?()
        }
    }

    var onWarningDismissed: (() -> Void)?
}

/// Notchnook-style protection timer window - seamlessly integrated with MacBook notch
class ProtectionTimerWindow: NSWindow {

    private var hostingView: NSView?  // Generic to support both ProtectionTimerView and ConfirmationWidgetView
    private var viewModel: ProtectionTimerViewModel?

    // Notchnook-style dimensions
    private let notchHeight: CGFloat = 32  // Actual MacBook notch height
    private let timerExpandedHeight: CGFloat = 70  // Minimal compact timer height
    private let timerExpandedHeightWithWarning: CGFloat = 70  // Same height when expanded
    private let confirmationExpandedHeight: CGFloat = 190  // Confirmation widget height (compact modern design)
    private let timerWidgetWidth: CGFloat = 100  // Ultra-compact shield design
    private let timerWidgetWidthExpanded: CGFloat = 280  // Expanded with warning
    private let confirmationWidgetWidth: CGFloat = 320  // Narrower for minimal design

    // CRITICAL: Override to prevent window from becoming key (prevents focus and desktop switching)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        // Get screen bounds
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        // CRITICAL: Window must extend INTO notch area
        // Start with window ABOVE visible screen, extending into notch
        let windowRect = NSRect(
            x: (screenFrame.width - confirmationWidgetWidth) / 2,  // Center horizontally
            y: screenFrame.maxY - notchHeight,         // Top edge extends into notch
            width: confirmationWidgetWidth,
            height: notchHeight  // Start collapsed (only notch visible)
        )

        super.init(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 1  // Above menu bar to access notch area
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false  // No shadow initially
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // CRITICAL: Prevent this window from activating the app and switching desktops
        self.hidesOnDeactivate = false
        self.styleMask.insert(.nonactivatingPanel)

        // Start invisible
        self.alphaValue = 0
    }

    /// Shows confirmation widget (opt-in flow) - asks user to enable protection
    /// Auto-dismisses after 6 seconds if no action taken
    func showConfirmation(address: String, type: CryptoType, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        print("🔐 [ConfirmationWidget] Showing opt-in widget (6s timeout)")

        var userResponded = false  // Track if user clicked button

        // Create confirmation view with auto-dismiss
        let confirmationView = ConfirmationWidgetView(
            address: address,
            type: type,
            onConfirm: { [weak self] in
                userResponded = true
                print("✅ [ConfirmationWidget] User confirmed - hiding widget then showing timer")

                // Hide confirmation first, THEN trigger protection flow
                self?.hideConfirmation {
                    // After hide animation completes, trigger protection
                    onConfirm()
                }
            },
            onDismiss: { [weak self] in
                userResponded = true
                onDismiss()
                self?.hideConfirmation()
            }
        )

        let hosting = NSHostingView(rootView: confirmationView)
        // CRITICAL: Remove ALL backgrounds to prevent translucent square artifact
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        hostingView = hosting
        self.contentView = hostingView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = .clear

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let centerX = (screenFrame.width - confirmationWidgetWidth) / 2

        // Start collapsed in notch
        let startY = screenFrame.maxY - notchHeight
        self.setFrame(NSRect(x: centerX, y: startY, width: confirmationWidgetWidth, height: notchHeight), display: true)

        // CRITICAL: Use orderFrontRegardless() instead of orderFront(nil)
        // This shows the window WITHOUT activating the app (no dashboard popup)
        self.orderFrontRegardless()
        self.alphaValue = 1.0

        // Animate expansion - smooth ease-out like native macOS notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5  // Slightly faster for snappier feel
                // Smooth ease-out curve (no bounce) - feels more native
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true

                let finalY = screenFrame.maxY - (self.notchHeight + self.confirmationExpandedHeight)
                let finalFrame = NSRect(
                    x: centerX,
                    y: finalY,
                    width: self.confirmationWidgetWidth,
                    height: self.notchHeight + self.confirmationExpandedHeight
                )

                self.animator().setFrame(finalFrame, display: true)
                self.hasShadow = true
            }
        }

        // Auto-dismiss after 6 seconds ONLY if user didn't respond
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self = self, self.isVisible, !userResponded else { return }
            print("⏱️  [ConfirmationWidget] 6s timeout - auto-dismissing")
            onDismiss()
            self.hideConfirmation()
        }
    }

    /// Hides the confirmation widget
    private func hideConfirmation(completion: (() -> Void)? = nil) {
        guard let screen = NSScreen.main else {
            completion?()
            return
        }
        let screenFrame = screen.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35  // Faster collapse feels more responsive
            // Smooth ease-in for collapse
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            // Collapse back into notch
            let centerX = (screenFrame.width - confirmationWidgetWidth) / 2
            let collapsedY = screenFrame.maxY - notchHeight
            let collapsedFrame = NSRect(
                x: centerX,
                y: collapsedY,
                width: confirmationWidgetWidth,
                height: notchHeight
            )

            self.animator().setFrame(collapsedFrame, display: true)
            self.animator().alphaValue = 0
            self.hasShadow = false
        } completionHandler: {
            self.orderOut(nil)
            // Call completion after hiding
            completion?()
        }
    }

    /// Shows critical alert when malware detected during confirmation
    func showHijackDuringConfirmation(original: String, hijacked: String) {
        print("🚨 [HijackAlert] Malware detected during confirmation!")
        print("   Original: \(original.prefix(20))...")
        print("   Hijacked: \(hijacked.prefix(20))...")
        // TODO: Will implement alert UI in next iteration
    }

    /// Shows "Protection Enabled" toast for Option+Cmd+C instant protection
    func showProtectionEnabledToast(for type: CryptoType) {
        let toastView = ProtectionEnabledToast(cryptoType: type)
        let hosting = NSHostingView(rootView: toastView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        hostingView = hosting
        self.contentView = hostingView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = .clear

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let toastWidth: CGFloat = 260
        let toastHeight: CGFloat = 70
        let centerX = (screenFrame.width - toastWidth) / 2
        let centerY = screenFrame.maxY - 120  // Below notch

        self.setFrame(NSRect(x: centerX, y: centerY, width: toastWidth, height: toastHeight), display: true)
        // Use orderFrontRegardless() to avoid activating the app
        self.orderFrontRegardless()
        self.alphaValue = 0

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 1.0
        }

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.animator().alphaValue = 0
            } completionHandler: {
                self?.orderOut(nil)
            }
        }
    }

    /// Shows volume-style thread timer for 2-minute protection
    func showProtection(for type: CryptoType, timeRemaining: TimeInterval, onDismiss: @escaping () -> Void) {
        print("🪟 [ProtectionTimerWindow] showProtection() called (Volume-style)")
        print("   Type: \(type.rawValue)")
        print("   Time: \(timeRemaining)s")

        // If already showing, hide first then show new one
        if isVisible && viewModel != nil {
            print("🔄 [ProtectionTimerWindow] Already showing - hiding first")
            hideProtection()

            // Wait for hide animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.displayProtection(for: type, timeRemaining: timeRemaining, onDismiss: onDismiss)
            }
            return
        }

        displayProtection(for: type, timeRemaining: timeRemaining, onDismiss: onDismiss)
    }

    /// Helper to actually display the protection timer
    private func displayProtection(for type: CryptoType, timeRemaining: TimeInterval, onDismiss: @escaping () -> Void) {
        // Create view model
        viewModel = ProtectionTimerViewModel(
            cryptoType: type,
            timeRemaining: timeRemaining,
            onDismiss: onDismiss
        )

        // Set callback to collapse when warning dismissed
        viewModel?.onWarningDismissed = { [weak self] in
            self?.collapseToCompactSize()
        }

        let timerView = ProtectionTimerView(viewModel: viewModel!)
        let hosting = NSHostingView(rootView: timerView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        hostingView = hosting
        self.contentView = hostingView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = .clear

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Position window to extend into notch (narrow volume-style)
        let centerX = (screenFrame.width - timerWidgetWidth) / 2

        // Start: Window top edge in notch area, only notch height visible
        let startY = screenFrame.maxY - notchHeight
        self.setFrame(NSRect(x: centerX, y: startY, width: timerWidgetWidth, height: notchHeight), display: true)

        print("🪟 [ProtectionTimerWindow] Ordering window front...")
        // Use orderFrontRegardless() to avoid activating the app
        self.orderFrontRegardless()
        self.alphaValue = 1.0  // Fade in immediately

        // CRITICAL: Animate expansion downward (like notch extending)
        // Keep top edge fixed, increase height downward
        print("🪟 [ProtectionTimerWindow] Animating notch expansion...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5  // Snappier timing
                // Smooth ease-out like native macOS (no bounce)
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true

                // Expand DOWN from notch - keep top fixed, grow height
                let finalY = screenFrame.maxY - (self.notchHeight + self.timerExpandedHeight)
                let finalFrame = NSRect(
                    x: centerX,
                    y: finalY,
                    width: self.timerWidgetWidth,
                    height: self.notchHeight + self.timerExpandedHeight
                )

                print("🪟 [ProtectionTimerWindow] Expanding to: \(finalFrame)")
                self.animator().setFrame(finalFrame, display: true)

                // Add shadow when expanded
                self.hasShadow = true
            } completionHandler: {
                print("🪟 [ProtectionTimerWindow] Expansion complete!")
            }
        }
    }

    /// Updates the countdown timer
    func updateTime(_ timeRemaining: TimeInterval) {
        print("🪟 [ProtectionTimerWindow] updateTime called with \(Int(timeRemaining))s")
        print("   ViewModel exists: \(viewModel != nil)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let vm = self.viewModel else {
                print("⚠️  [ProtectionTimerWindow] Self or ViewModel is nil!")
                return
            }
            print("🪟 [ProtectionTimerWindow] Calling ViewModel.updateTime(\(Int(timeRemaining)))")
            vm.updateTime(timeRemaining)
        }
    }

    /// Shows warning message when clipboard changes - expands widget
    func showWarning(_ message: String) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Show warning in view model
            self.viewModel?.showWarning(message)

            // Animate width expansion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                // Smooth ease-out for expansion
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true

                let centerX = (screenFrame.width - self.timerWidgetWidthExpanded) / 2
                let currentY = self.frame.origin.y
                let expandedFrame = NSRect(
                    x: centerX,
                    y: currentY,
                    width: self.timerWidgetWidthExpanded,
                    height: self.frame.height
                )

                self.animator().setFrame(expandedFrame, display: true)
            }
        }
    }

    /// Collapses widget back to compact size after warning dismissed
    private func collapseToCompactSize() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            // Smooth ease-in for collapse
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            let centerX = (screenFrame.width - self.timerWidgetWidth) / 2
            let currentY = self.frame.origin.y
            let compactFrame = NSRect(
                x: centerX,
                y: currentY,
                width: self.timerWidgetWidth,
                height: self.frame.height
            )

            self.animator().setFrame(compactFrame, display: true)
        }
    }

    /// Hides the protection timer - collapses back into notch seamlessly
    func hideProtection() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4  // Faster collapse
            // Smooth ease-in for natural collapse
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            // Collapse back into notch - shrink height upward
            let centerX = (screenFrame.width - timerWidgetWidth) / 2
            let collapsedY = screenFrame.maxY - notchHeight
            let collapsedFrame = NSRect(
                x: centerX,
                y: collapsedY,
                width: timerWidgetWidth,
                height: notchHeight
            )

            self.animator().setFrame(collapsedFrame, display: true)
            self.animator().alphaValue = 0
            self.hasShadow = false
        } completionHandler: {
            self.orderOut(nil)
            self.viewModel = nil
        }
    }
}

// MARK: - Protection Timer View (Minimal Progress Design)

struct ProtectionTimerView: View {
    @ObservedObject var viewModel: ProtectionTimerViewModel

    // Calculate progress (0.0 to 1.0) based on time remaining
    private var progress: CGFloat {
        CGFloat(viewModel.timeRemaining / 120.0)
    }

    // Dynamic width based on warning state
    private var widgetWidth: CGFloat {
        viewModel.showWarning ? 280 : 100
    }

    var body: some View {
        VStack(spacing: 0) {
            // Invisible notch area
            Color.clear
                .frame(height: 32)

            // Main content - ultra minimal
            HStack(spacing: 0) {
                // Compact shield indicator
                ZStack {
                    // Subtle glow background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.green.opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)

                    // Shield icon
                    Image(systemName: "shield.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))

                    // Minimal circular progress
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.green.opacity(0.6),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .frame(width: 60)
                .padding(.horizontal, 20)

                // Warning message (slides in from right)
                if viewModel.showWarning {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clipboard Locked")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Protection active")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.trailing, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .frame(height: 70)
        }
        .frame(width: widgetWidth)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 35,
                bottomTrailingRadius: 35,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.92))
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 35,
                bottomTrailingRadius: 35,
                topTrailingRadius: 0,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: widgetWidth)
    }
}

// MARK: - Confirmation Widget View

struct ConfirmationWidgetView: View {
    let address: String
    let type: CryptoType
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @State private var countdown: CGFloat = 1.0  // 1.0 to 0.0 (6 seconds)
    @State private var hasResponded: Bool = false  // Prevent double-clicks

    var body: some View {
        VStack(spacing: 0) {
            // Invisible notch area
            Color.clear
                .frame(height: 32)

            // Main content - ultra minimal
            VStack(spacing: 14) {
                // Crypto icon - small and minimal
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)

                    Text(cryptoEmoji(for: type))
                        .font(.system(size: 18))
                }

                // Title - clean and simple
                Text("Protect \(type.rawValue) Address?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                // Address - subtle monospace
                Text(maskAddress(address))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                // Buttons - minimal modern style with pill-shaped corners
                HStack(spacing: 10) {
                    // Dismiss - ghost button
                    Button(action: {
                        guard !hasResponded else { return }
                        hasResponded = true
                        onDismiss()
                    }) {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(hasResponded)

                    // Confirm - accent button
                    Button(action: {
                        guard !hasResponded else { return }
                        hasResponded = true
                        onConfirm()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 11, weight: .semibold))

                            Text("Protect")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.2, green: 0.78, blue: 0.35), Color(red: 0.18, green: 0.7, blue: 0.32)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(hasResponded)
                }
                .padding(.top, 2)

                // Minimal progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 2)

                        // Progress
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: geometry.size.width * countdown, height: 2)
                    }
                }
                .frame(height: 2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .padding(.bottom, 6)
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 36,
                bottomTrailingRadius: 36,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.95))
        )
        .overlay(
            // Subtle border
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 36,
                bottomTrailingRadius: 36,
                topTrailingRadius: 0,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
        .onAppear {
            withAnimation(.linear(duration: 6.0)) {
                countdown = 0.0
            }
        }
    }

    private func maskAddress(_ address: String) -> String {
        guard address.count > 10 else { return "***" }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    private func cryptoEmoji(for type: CryptoType) -> String {
        switch type {
        case .bitcoin: return "₿"
        case .ethereum: return "Ξ"
        case .solana: return "◎"
        case .litecoin: return "Ł"
        case .dogecoin: return "Ð"
        case .monero: return "ɱ"
        case .unknown: return "🔐"
        }
    }
}


// MARK: - Protection Enabled Toast

/// Simple toast shown when user presses Option+Cmd+C for instant protection
struct ProtectionEnabledToast: View {
    let cryptoType: CryptoType

    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // Shield icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Protection Enabled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("\(cryptoType.rawValue) • 2 minutes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

#Preview {
    let viewModel = ProtectionTimerViewModel(
        cryptoType: .ethereum,
        timeRemaining: 95,
        onDismiss: {}
    )
    ProtectionTimerView(viewModel: viewModel)
        .frame(width: 320, height: 100)
}
#endif
