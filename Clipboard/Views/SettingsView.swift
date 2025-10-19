//
//  SettingsView.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI

struct SettingsView: View {

    // MARK: - Observed Objects

    @ObservedObject var licenseManager: LicenseManager
    @ObservedObject var clipboardMonitor: ClipboardMonitor

    // MARK: - State

    @State private var selectedSection: Section = .general
    @State private var showingDeactivateAlert = false

    // MARK: - Body

    var body: some View {
        #if os(macOS)
        macOSLayout
        #elseif os(iOS)
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        HSplitView {
            // Sidebar
            List(Section.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .frame(minWidth: 150, maxWidth: 200)

            // Content
            sectionContent
                .frame(minWidth: 400)
                .padding()
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        NavigationView {
            List {
                ForEach(Section.allCases, id: \.self) { section in
                    NavigationLink {
                        sectionContent(for: section)
                    } label: {
                        Label(section.title, systemImage: section.icon)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private func sectionContent(for section: Section) -> some View {
        switch section {
        case .general: generalSection
        case .license: licenseSection
        case .privacy: privacySection
        case .about: aboutSection
        }
    }
    #endif

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general: generalSection
        case .license: licenseSection
        case .privacy: privacySection
        case .about: aboutSection
        }
    }

    private var generalSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("General")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 16) {
                    // Protection Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clipboard Protection")
                                .fontWeight(.medium)
                            Text("Continuously monitor clipboard for crypto addresses")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { clipboardMonitor.isMonitoring },
                            set: { enabled in
                                if enabled {
                                    clipboardMonitor.startMonitoring()
                                } else {
                                    clipboardMonitor.stopMonitoring()
                                }
                            }
                        ))
                    }

                    Divider()

                    // Launch at Login (placeholder)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Launch at Login")
                                .fontWeight(.medium)
                            Text("Start ClipboardGuard when you log in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(false))
                            .disabled(true)  // TODO: Implement
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var licenseSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("License")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 16) {
                    // Email
                    HStack {
                        Text("Email")
                            .fontWeight(.medium)
                        Spacer()
                        Text(licenseManager.email ?? "Unknown")
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // License Type
                    HStack {
                        Text("License Type")
                            .fontWeight(.medium)
                        Spacer()
                        Text(licenseManager.licenseData?.product.rawValue.replacingOccurrences(of: "clipboardguard_", with: "").capitalized ?? "Unknown")
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Expiry Date
                    if let expiryDate = licenseManager.licenseData?.expiresAt {
                        HStack {
                            Text("Expires")
                                .fontWeight(.medium)
                            Spacer()
                            Text(expiryDate, style: .date)
                                .foregroundColor(.secondary)
                        }

                        if let daysRemaining = licenseManager.licenseData?.daysUntilExpiry {
                            if daysRemaining <= 30 {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("\(daysRemaining) days remaining")
                                        .font(.caption)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    } else {
                        HStack {
                            Text("Expires")
                                .fontWeight(.medium)
                            Spacer()
                            Text("Never (Lifetime)")
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Deactivate Button
                Button(role: .destructive, action: {
                    showingDeactivateAlert = true
                }) {
                    Text("Deactivate License")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .alert("Deactivate License?", isPresented: $showingDeactivateAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Deactivate", role: .destructive) {
                        clipboardMonitor.stopMonitoring()
                        licenseManager.deactivate()
                    }
                } message: {
                    Text("This will stop clipboard protection and remove your license from this device.")
                }
            }
        }
    }

    private var privacySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 16) {
                    PrivacyRow(
                        icon: "network.slash",
                        title: "Zero Network Activity",
                        description: "No data leaves your device after activation"
                    )

                    Divider()

                    PrivacyRow(
                        icon: "eye.slash",
                        title: "No Analytics",
                        description: "We don't track your usage or behavior"
                    )

                    Divider()

                    PrivacyRow(
                        icon: "lock.shield",
                        title: "Local Processing Only",
                        description: "All pattern matching happens on your device"
                    )

                    Divider()

                    PrivacyRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Optional Logging",
                        description: "Security logs are stored locally and never shared"
                    )
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Your clipboard content is never stored or transmitted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }

    private var aboutSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("About")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(spacing: 16) {
                    Image(systemName: "shield.checkered")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundStyle(.blue.gradient)

                    Text("ClipboardGuard")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Protecting your crypto transactions from clipboard hijacking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    Button("Website") {
                        openURL("https://clipboardguard.app")
                    }

                    Button("Support") {
                        openURL("mailto:support@clipboardguard.app")
                    }

                    Button("Privacy Policy") {
                        openURL("https://clipboardguard.app/privacy")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helper Methods

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

    // MARK: - Section Enum

    enum Section: CaseIterable {
        case general
        case license
        case privacy
        case about

        var title: String {
            switch self {
            case .general: return "General"
            case .license: return "License"
            case .privacy: return "Privacy"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .license: return "key.fill"
            case .privacy: return "lock.shield"
            case .about: return "info.circle"
            }
        }
    }
}

// MARK: - Privacy Row Component

struct PrivacyRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let licenseManager = LicenseManager()
    let clipboardMonitor = ClipboardMonitor()
    licenseManager.isLicensed = true
    licenseManager.email = "test@example.com"

    return SettingsView(
        licenseManager: licenseManager,
        clipboardMonitor: clipboardMonitor
    )
}
