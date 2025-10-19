//
//  ActivationView.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI

struct ActivationView: View {

    // MARK: - Environment

    @ObservedObject var licenseManager: LicenseManager

    // MARK: - State

    @State private var email: String = ""
    @State private var licenseKey: String = ""
    @State private var isActivating: Bool = false
    @State private var errorMessage: String?
    @State private var showingError: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            // App Icon
            Image(systemName: "shield.checkered")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue.gradient)

            // Title
            VStack(spacing: 8) {
                Text("Activate ClipboardGuard")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enter your license to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Form
            VStack(spacing: 16) {
                // Email Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif
                        .disableAutocorrection(true)
                }

                // License Key Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("License Key")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("CGRD-XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.none)
                        #if os(iOS)
                        .autocapitalization(.allCharacters)
                        #endif
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .padding(.horizontal)

            // Activate Button
            Button(action: activateLicense) {
                HStack {
                    if isActivating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                    Text(isActivating ? "Activating..." : "Activate License")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canActivate ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!canActivate || isActivating)
            .padding(.horizontal)

            // Links
            HStack(spacing: 20) {
                Button("Buy License") {
                    openURL("https://clipboardguard.app/pricing")
                }

                Text("·")
                    .foregroundColor(.secondary)

                Button("Lost License?") {
                    openURL("https://clipboardguard.app/recover")
                }
            }
            .font(.footnote)

            Spacer()

            // Privacy Statement
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                Text("No data leaves your device")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: 400)
        .alert("Activation Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
    }

    // MARK: - Computed Properties

    private var canActivate: Bool {
        !email.isEmpty && isValidEmail(email) && !licenseKey.isEmpty && isValidLicenseFormat(licenseKey)
    }

    // MARK: - Methods

    private func activateLicense() {
        isActivating = true
        errorMessage = nil

        // Simulate network delay for activation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let success = licenseManager.validateAndActivate(
                email: email.trimmingCharacters(in: .whitespaces),
                licenseKey: licenseKey.uppercased().trimmingCharacters(in: .whitespaces)
            )

            isActivating = false

            if !success {
                errorMessage = "Invalid license key or email. Please check and try again."
                showingError = true
            }
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return predicate.evaluate(with: email)
    }

    private func isValidLicenseFormat(_ key: String) -> Bool {
        let pattern = "^CGRD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        return key.uppercased().range(of: pattern, options: .regularExpression) != nil
    }

    private func openURL(_ urlString: String) {
        #if os(macOS)
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        #elseif os(iOS)
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    ActivationView(licenseManager: LicenseManager())
}
