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

            // Auto-dismiss after 8 seconds (longer duration for visibility)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
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
    private let collapsedHeight: CGFloat = 32  // Matches notch height
    private let expandedHeight: CGFloat = 110  // Expanded state
    private let widgetWidth: CGFloat = 340

    init() {
        // Get screen bounds
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        // Start collapsed into notch (FLUSH with top of screen)
        let windowRect = NSRect(
            x: (screenFrame.width - widgetWidth) / 2,  // Center horizontally
            y: screenFrame.maxY - collapsedHeight,      // FLUSH with screen top
            width: widgetWidth,
            height: collapsedHeight
        )

        super.init(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar  // Above everything
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Initially hidden (collapsed into notch)
        self.alphaValue = 0
    }

    /// Shows protection timer with Notchnook-style animation
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

        print("🪟 [ProtectionTimerWindow] Ordering window front...")
        self.orderFront(nil)

        // Notchnook-style: Spring bounce animation expanding down from notch
        print("🪟 [ProtectionTimerWindow] Starting animation...")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)  // Spring bounce
            context.allowsImplicitAnimation = true

            if let screen = NSScreen.main {
                // Use FULL screen frame (not visibleFrame) to access notch area
                let screenFrame = screen.frame
                print("🪟 [ProtectionTimerWindow] Full screen frame: \(screenFrame)")
                print("   Visible frame: \(screen.visibleFrame)")

                // Calculate position: window should be AT THE VERY TOP
                // macOS coordinates: (0,0) is bottom-left, Y increases upward
                // Window frame origin is the BOTTOM-LEFT corner of the window
                // So to position top edge at screen top: Y = screenHeight - windowHeight

                let targetY = screenFrame.maxY - expandedHeight
                let targetX = (screenFrame.width - widgetWidth) / 2

                var newFrame = self.frame
                newFrame.origin.x = targetX
                newFrame.origin.y = targetY
                newFrame.size.width = widgetWidth
                newFrame.size.height = expandedHeight

                print("🪟 [ProtectionTimerWindow] Target position:")
                print("   X: \(targetX) (centered)")
                print("   Y: \(targetY) (top edge at \(targetY + expandedHeight))")
                print("   Screen height: \(screenFrame.maxY)")

                self.setFrame(newFrame, display: true, animate: true)
                self.animator().alphaValue = 1.0
            }
        } completionHandler: {
            print("🪟 [ProtectionTimerWindow] Animation complete! Alpha: \(self.alphaValue)")
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

    /// Hides the protection timer with spring animation back into notch
    func hideProtection() {
        // Spring bounce animation collapsing back into notch
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.5, 1)  // Ease in-out
            context.allowsImplicitAnimation = true

            if let screen = NSScreen.main {
                let screenFrame = screen.frame
                var newFrame = self.frame
                // Collapse back into notch
                newFrame.origin.y = screenFrame.maxY - collapsedHeight
                newFrame.size.height = collapsedHeight
                self.setFrame(newFrame, display: true, animate: true)
                self.animator().alphaValue = 0
            }
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
        VStack(spacing: 0) {
            // Main timer content - Notchnook style
            VStack(spacing: 10) {
                // Warning banner (appears above main content)
                if viewModel.showWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.yellow)

                        Text(viewModel.warningMessage ?? "")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.9))
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Main protection status
                HStack(spacing: 12) {
                    // Crypto icon with subtle glow
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 44, height: 44)

                        Text(cryptoEmoji(for: viewModel.cryptoType))
                            .font(.system(size: 22))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        // Crypto type
                        Text(viewModel.cryptoType.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize()

                        // Live countdown timer
                        HStack(spacing: 6) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                                .scaleEffect(pulseScale)

                            Text(formatTime(viewModel.timeRemaining))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                                .fixedSize()
                                .id(viewModel.timeRemaining)  // Force SwiftUI to update
                        }
                    }

                    Spacer()

                    // Dismiss button
                    Button(action: {
                        viewModel.onDismiss?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Stop protection")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                // Notchnook-style: Black background with rounded bottom corners only
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0
                )
                .fill(Color.black.opacity(0.95))
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 0
                    )
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 25, x: 0, y: 15)
            )
        }
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
