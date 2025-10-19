//
//  FloatingIndicator.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

/// Type of floating indicator to show
enum IndicatorType {
    case copy    // When crypto address is copied (yellow/orange - watching)
    case paste   // When crypto address is pasted (green - verified)
}

/// Modern minimal floating indicator for copy detection
struct CopyIndicator: View {
    let cryptoType: CryptoType
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var checkmarkScale: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            // Checkmark (trust building, not spying!)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .scaleEffect(checkmarkScale)

            // Crypto name - full text with space
            Text(cryptoType.rawValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize()  // Don't truncate text
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.95))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 3)
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            // Pop in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                opacity = 1.0
                scale = 1.0
            }

            // Checkmark pop
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05)) {
                checkmarkScale = 1.0
            }

            // Fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                    scale = 0.9
                }
            }
        }
    }
}

/// Trust-building floating indicator for paste verification
struct PasteIndicator: View {
    let cryptoType: CryptoType
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.7
    @State private var checkmarkScale: CGFloat = 0
    @State private var shimmer: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            // Big checkmark with shimmer
            ZStack {
                // Outer glow
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.green.opacity(0.3))
                    .scaleEffect(1.3)
                    .blur(radius: 4)

                // Main checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)

                // Shimmer effect
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .offset(x: shimmer)
                    .mask(
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cryptoType.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize()  // Don't truncate

                Text("Verified ✓")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize()  // Don't truncate
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: .green.opacity(0.4), radius: 15, x: 0, y: 5)
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            // Confident pop-in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                opacity = 1.0
                scale = 1.0
            }

            // Checkmark pop
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
                checkmarkScale = 1.0
            }

            // Shimmer sweep
            withAnimation(.linear(duration: 0.8).delay(0.2)) {
                shimmer = 40
            }

            // Stay longer for confidence
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                    scale = 0.95
                }
            }
        }
    }
}

/// Floating indicator window for macOS
#if os(macOS)
class FloatingIndicatorWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        alphaValue = 1.0  // Ensure fully visible
    }

    /// Shows copy indicator near mouse cursor
    func showCopy(for cryptoType: CryptoType) {
        print("👁️  [FloatingIndicator] Showing COPY indicator for \(cryptoType.rawValue)")

        // Get mouse location
        let mouseLocation = NSEvent.mouseLocation

        // Position window near cursor (offset to right and down)
        setFrameOrigin(NSPoint(
            x: mouseLocation.x + 15,
            y: mouseLocation.y - 40
        ))

        // Set content
        contentView = NSHostingView(
            rootView: CopyIndicator(cryptoType: cryptoType)
        )

        // Make window visible
        alphaValue = 1.0
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()

        print("   [FloatingIndicator] Window shown at (\(frame.origin.x), \(frame.origin.y))")

        // Auto-hide after 2.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.orderOut(nil)
        }
    }

    /// Shows paste verification indicator near mouse cursor
    func showPaste(for cryptoType: CryptoType) {
        print("✅ [FloatingIndicator] Showing PASTE indicator for \(cryptoType.rawValue)")

        // Get mouse location
        let mouseLocation = NSEvent.mouseLocation

        // Position window near cursor (offset to right and down)
        setFrameOrigin(NSPoint(
            x: mouseLocation.x + 15,
            y: mouseLocation.y - 45
        ))

        // Set content
        contentView = NSHostingView(
            rootView: PasteIndicator(cryptoType: cryptoType)
        )

        // Make window visible
        alphaValue = 1.0
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()

        print("   [FloatingIndicator] Window shown at (\(frame.origin.x), \(frame.origin.y))")

        // Auto-hide after 3 seconds (longer for confidence)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.orderOut(nil)
        }
    }
}
#endif

// MARK: - Previews

#Preview("Copy Indicator") {
    CopyIndicator(cryptoType: .bitcoin)
        .frame(width: 200, height: 60)
        .background(Color.gray.opacity(0.3))
}

#Preview("Paste Indicator") {
    PasteIndicator(cryptoType: .ethereum)
        .frame(width: 200, height: 60)
        .background(Color.gray.opacity(0.3))
}
