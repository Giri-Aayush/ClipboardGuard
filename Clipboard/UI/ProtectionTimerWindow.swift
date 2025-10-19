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
        }
    }
}

/// Notchnook-style protection timer window - seamlessly integrated with MacBook notch
class ProtectionTimerWindow: NSWindow {

    private var hostingView: NSHostingView<ProtectionTimerView>?
    private var viewModel: ProtectionTimerViewModel?

    // Notchnook-style dimensions
    private let notchHeight: CGFloat = 32  // Actual MacBook notch height
    private let expandedHeight: CGFloat = 100  // Content height when expanded
    private let widgetWidth: CGFloat = 360

    init() {
        // Get screen bounds
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        // CRITICAL: Window must extend INTO notch area
        // Start with window ABOVE visible screen, extending into notch
        let windowRect = NSRect(
            x: (screenFrame.width - widgetWidth) / 2,  // Center horizontally
            y: screenFrame.maxY - notchHeight,         // Top edge extends into notch
            width: widgetWidth,
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

        // Start invisible
        self.alphaValue = 0
    }

    /// Shows protection timer with Notchnook-style animation - expands down from notch
    func showProtection(for type: CryptoType, timeRemaining: TimeInterval, onDismiss: @escaping () -> Void) {
        print("🪟 [ProtectionTimerWindow] showProtection() called")
        print("   Type: \(type.rawValue)")
        print("   Time: \(timeRemaining)s")

        // Create view model
        viewModel = ProtectionTimerViewModel(
            cryptoType: type,
            timeRemaining: timeRemaining,
            onDismiss: onDismiss
        )

        let timerView = ProtectionTimerView(viewModel: viewModel!)
        hostingView = NSHostingView(rootView: timerView)
        self.contentView = hostingView

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Position window to extend into notch
        let centerX = (screenFrame.width - widgetWidth) / 2

        // Start: Window top edge in notch area, only notch height visible
        let startY = screenFrame.maxY - notchHeight
        self.setFrame(NSRect(x: centerX, y: startY, width: widgetWidth, height: notchHeight), display: true)

        print("🪟 [ProtectionTimerWindow] Ordering window front...")
        self.orderFront(nil)
        self.alphaValue = 1.0  // Fade in immediately

        // CRITICAL: Animate expansion downward (like notch extending)
        // Keep top edge fixed, increase height downward
        print("🪟 [ProtectionTimerWindow] Animating notch expansion...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                // Notchnook bounce: spring with overshoot
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.15, 0.5, 1.0)
                context.allowsImplicitAnimation = true

                // Expand DOWN from notch - keep top fixed, grow height
                let finalY = screenFrame.maxY - (self.notchHeight + self.expandedHeight)
                let finalFrame = NSRect(
                    x: centerX,
                    y: finalY,
                    width: self.widgetWidth,
                    height: self.notchHeight + self.expandedHeight
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

    /// Shows warning message when clipboard changes
    func showWarning(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel?.showWarning(message)
        }
    }

    /// Hides the protection timer - collapses back into notch seamlessly
    func hideProtection() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.5, 1)
            context.allowsImplicitAnimation = true

            // Collapse back into notch - shrink height upward
            let centerX = (screenFrame.width - widgetWidth) / 2
            let collapsedY = screenFrame.maxY - notchHeight
            let collapsedFrame = NSRect(
                x: centerX,
                y: collapsedY,
                width: widgetWidth,
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

// MARK: - Protection Timer View

struct ProtectionTimerView: View {
    @ObservedObject var viewModel: ProtectionTimerViewModel

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        // Full widget with rounded corners matching notch curvature
        VStack(spacing: 0) {
            // Warning banner (if active)
            if viewModel.showWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.yellow)

                    Text(viewModel.warningMessage ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .padding(.top, 32)  // Account for notch height
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.15))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main protection status
            HStack(spacing: 14) {
                // Crypto icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)

                    Text(cryptoEmoji(for: viewModel.cryptoType))
                        .font(.system(size: 24))
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Crypto type
                    Text(viewModel.cryptoType.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize()

                    // Live countdown timer with shield
                    HStack(spacing: 7) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.green)
                            .scaleEffect(pulseScale)

                        Text(formatTime(viewModel.timeRemaining))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .fixedSize()
                            .id(viewModel.timeRemaining)
                    }
                }

                Spacer()

                // Dismiss button
                Button(action: {
                    viewModel.onDismiss?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.top, viewModel.showWarning ? 0 : 32)  // Notch spacer when no warning
        }
        .background(
            // CRITICAL: Rounded corners ALL AROUND to match notch curve
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)  // Pure black to blend with notch
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            // Pulse animation for shield icon
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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

#Preview {
    let viewModel = ProtectionTimerViewModel(
        cryptoType: .ethereum,
        timeRemaining: 95,
        onDismiss: {}
    )
    return ProtectionTimerView(viewModel: viewModel)
        .frame(width: 320, height: 100)
}
#endif
