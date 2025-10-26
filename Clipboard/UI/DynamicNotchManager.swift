//
//  DynamicNotchManager.swift
//  Clipboard
//
//  Created by Aayush Giri on 23/10/25.
//

import SwiftUI
import DynamicNotchKit

/// Manager for all Dynamic Island/Notch interactions using DynamicNotchKit
@MainActor
class DynamicNotchManager {

    private var currentNotch: DynamicNotch<AnyView, EmptyView, EmptyView>?
    private var confirmationNotch: DynamicNotch<AnyView, EmptyView, EmptyView>?
    private var toastNotch: DynamicNotch<AnyView, EmptyView, EmptyView>?

    var currentViewModel: ProtectionTimerViewModel?

    // MARK: - Confirmation Widget (Opt-in Flow)

    /// Shows the confirmation widget asking user to enable protection
    func showConfirmation(address: String, type: CryptoType, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void) async {
        print("🔐 [DynamicNotch] Showing confirmation widget")

        let view = ConfirmationWidgetView(
            address: address,
            type: type,
            onConfirm: {
                Task { @MainActor in
                    await self.hideConfirmation()
                    onConfirm()
                }
            },
            onDismiss: {
                Task { @MainActor in
                    await self.hideConfirmation()
                    onDismiss()
                }
            }
        )

        confirmationNotch = DynamicNotch(
            hoverBehavior: [.keepVisible],
            style: .notch(topCornerRadius: 20, bottomCornerRadius: 25)
        ) {
            AnyView(view)
        } compactLeading: {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        }
        await confirmationNotch?.expand()

        // CRITICAL: Make window accept clicks/keyboard input
        confirmationNotch?.windowController?.window?.makeKey()

        // Auto-dismiss after 6 seconds
        Task {
            try? await Task.sleep(for: .seconds(6))
            await hideConfirmation()
            onDismiss()
        }
    }

    /// Hides the confirmation widget
    func hideConfirmation() async {
        await confirmationNotch?.hide()
        confirmationNotch = nil
    }

    // MARK: - Protection Timer Widget

    /// Shows the protection timer with countdown
    func showProtectionTimer(for type: CryptoType, timeRemaining: TimeInterval, onDismiss: @escaping () -> Void) async {
        print("🛡️  [DynamicNotch] Showing protection timer")

        let viewModel = ProtectionTimerViewModel(
            cryptoType: type,
            timeRemaining: timeRemaining,
            onDismiss: onDismiss
        )

        // Store the viewModel so we can update it
        currentViewModel = viewModel

        let view = ProtectionTimerView(viewModel: viewModel)

        currentNotch = DynamicNotch(
            hoverBehavior: [.keepVisible, .hapticFeedback],
            style: .notch(topCornerRadius: 20, bottomCornerRadius: 25)
        ) {
            AnyView(view)
        } compactLeading: {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        }
        await currentNotch?.expand()
    }

    /// Updates the timer countdown
    func updateTimer(_ timeRemaining: TimeInterval) {
        currentViewModel?.updateTime(timeRemaining)
    }

    /// Shows a warning message in the timer widget
    func showWarning(_ message: String) async {
        print("⚠️  [DynamicNotch] Showing warning: \(message)")
        currentViewModel?.showWarning(message)
    }

    /// Hides the protection timer
    func hideProtectionTimer() async {
        await currentNotch?.hide()
        currentNotch = nil
        currentViewModel = nil
    }

    // MARK: - Toast Notifications

    /// Shows "Protection Enabled" toast
    func showProtectionEnabledToast(for type: CryptoType) async {
        print("✅ [DynamicNotch] Showing protection enabled toast")

        let view = ProtectionEnabledToast(cryptoType: type)

        toastNotch = DynamicNotch(
            hoverBehavior: [],
            style: .notch(topCornerRadius: 20, bottomCornerRadius: 25)
        ) {
            AnyView(view)
        } compactLeading: {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        }
        await toastNotch?.expand()

        // Auto-hide after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            await hideToast()
        }
    }

    /// Hides the toast
    func hideToast() async {
        await toastNotch?.hide()
        toastNotch = nil
    }
}
