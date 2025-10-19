//
//  FloatingCheckmark.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

/// Modern minimal floating indicator that appears near cursor
struct FloatingCheckmark: View {
    let cryptoType: CryptoType
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var yOffset: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            // Simple checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            // Crypto name
            Text(cryptoType.rawValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: yOffset)
        .onAppear {
            // Quick pop-in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                opacity = 1.0
                scale = 1.0
                yOffset = 0
            }

            // Float up gently
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                yOffset = -15
            }

            // Fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                    scale = 0.9
                }
            }
        }
    }
}

/// Manager for showing floating checkmarks
@MainActor
class FloatingCheckmarkManager: ObservableObject {
    static let shared = FloatingCheckmarkManager()

    @Published var isVisible: Bool = false
    @Published var currentCryptoType: CryptoType = .unknown

    private init() {}

    /// Shows floating checkmark for a crypto type
    func show(for cryptoType: CryptoType) {
        currentCryptoType = cryptoType
        isVisible = true

        // Auto-hide after 2.5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            isVisible = false
        }
    }
}

/// Floating checkmark window for macOS
#if os(macOS)
class FloatingCheckmarkWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 100),
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
    }

    /// Shows checkmark near mouse cursor
    func show(for cryptoType: CryptoType) {
        // Get mouse location
        let mouseLocation = NSEvent.mouseLocation

        // Position window near cursor (slightly offset)
        setFrameOrigin(NSPoint(
            x: mouseLocation.x + 20,
            y: mouseLocation.y - 50
        ))

        // Set content
        contentView = NSHostingView(
            rootView: FloatingCheckmark(cryptoType: cryptoType)
        )

        // Show window
        orderFrontRegardless()

        // Auto-hide after 2.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.orderOut(nil)
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    FloatingCheckmark(cryptoType: .bitcoin)
        .frame(width: 120, height: 100)
        .background(Color.black.opacity(0.3))
}
