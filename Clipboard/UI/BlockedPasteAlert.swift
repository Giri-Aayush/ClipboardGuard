//
//  BlockedPasteAlert.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI
#if os(macOS)
import AppKit

/// Floating red alert window that appears at cursor when paste is blocked
class BlockedPasteAlertWindow: NSWindow {

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false  // Allow user to dismiss by clicking
        self.isReleasedWhenClosed = false

        // Initially hidden
        self.alphaValue = 0
    }

    // MARK: - Show Alert

    func showBlocked(original: String, hijacked: String) {
        // Get cursor position
        let mouseLocation = NSEvent.mouseLocation

        // Position window near cursor (slightly below and to the right)
        let windowOrigin = NSPoint(
            x: mouseLocation.x + 20,
            y: mouseLocation.y - 120  // Below cursor
        )

        self.setFrameOrigin(windowOrigin)

        // Set content
        let alertView = BlockedPasteAlertView(
            originalAddress: original,
            hijackedAddress: hijacked,
            onDismiss: { [weak self] in
                self?.hideAlert()
            }
        )

        self.contentView = NSHostingView(rootView: alertView)

        // Show with animation
        self.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1.0
        }

        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.hideAlert()
        }

        // Shake animation
        shake()
    }

    private func hideAlert() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
        }
    }

    // MARK: - Shake Animation

    private func shake() {
        let numberOfShakes = 3
        let durationOfShake = 0.3
        let vigourOfShake: CGFloat = 0.03

        let frame = self.frame
        let shakeAnimation = CAKeyframeAnimation(keyPath: "frameOrigin")

        let shakePath = CGMutablePath()
        shakePath.move(to: frame.origin)

        for _ in 0..<numberOfShakes {
            shakePath.addLine(to: CGPoint(x: frame.origin.x - frame.width * vigourOfShake, y: frame.origin.y))
            shakePath.addLine(to: CGPoint(x: frame.origin.x + frame.width * vigourOfShake, y: frame.origin.y))
        }

        shakePath.closeSubpath()

        shakeAnimation.path = shakePath
        shakeAnimation.duration = durationOfShake

        self.animations = ["frameOrigin": shakeAnimation]
        self.animator().setFrameOrigin(frame.origin)
    }
}

// MARK: - Alert View

struct BlockedPasteAlertView: View {

    let originalAddress: String
    let hijackedAddress: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.8
    @State private var iconScale: CGFloat = 0

    var body: some View {
        VStack(spacing: 12) {
            // Red X icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.red)
                    .scaleEffect(iconScale)
            }

            // Title
            Text("🛑 Paste Blocked!")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            // Message
            VStack(alignment: .leading, spacing: 6) {
                Text("Clipboard hijack detected!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                HStack(spacing: 4) {
                    Text("Original:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(maskAddress(originalAddress))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.green)
                }

                HStack(spacing: 4) {
                    Text("Blocked:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(maskAddress(hijackedAddress))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            // Dismiss button
            Button(action: onDismiss) {
                Text("Got it")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.95),
                            Color.red.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .red.opacity(0.5), radius: 20, x: 0, y: 10)
        )
        .scaleEffect(scale)
        .onAppear {
            // Animate entrance
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
                iconScale = 1.0
            }
        }
    }

    // MARK: - Helpers

    private func maskAddress(_ address: String) -> String {
        guard address.count > 10 else { return "***" }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
}

#Preview {
    BlockedPasteAlertView(
        originalAddress: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
        hijackedAddress: "1HackerStoleYourBitcoin123456789XYZ",
        onDismiss: {}
    )
    .frame(width: 320, height: 200)
}
#endif
