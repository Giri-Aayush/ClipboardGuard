//
//  DashboardView.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import SwiftUI

struct DashboardView: View {

    // MARK: - Environment

    @ObservedObject var clipboardMonitor: ClipboardMonitor

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Header
                statusHeader

                Divider()

                // Statistics
                statisticsSection

                // Activity Graph Placeholder
                activityGraphSection

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Components

    private var statusHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(clipboardMonitor.isMonitoring ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                Text(clipboardMonitor.isMonitoring ? "Protection Active" : "Protection Inactive")
                    .font(.headline)
            }

            Spacer()

            Button(action: {
                // TODO: Open settings
            }) {
                Image(systemName: "gear")
                    .font(.title3)
            }
        }
    }

    private var statisticsSection: some View {
        VStack(spacing: 16) {
            // Checks Today
            StatRow(
                icon: "magnifyingglass",
                label: "Checks Today",
                value: "\(clipboardMonitor.checksToday)",
                iconColor: .blue
            )

            // Threats Blocked
            StatRow(
                icon: "shield.checkered",
                label: "Threats Blocked",
                value: "\(clipboardMonitor.threatsBlocked)",
                iconColor: clipboardMonitor.threatsBlocked > 0 ? .red : .green
            )

            // Last Check
            StatRow(
                icon: "clock",
                label: "Last Check",
                value: clipboardMonitor.isMonitoring ? "Just now" : "Not active",
                iconColor: .orange
            )

            // Last Detected Address
            if let address = clipboardMonitor.lastDetectedAddress,
               let cryptoType = clipboardMonitor.lastDetectedCryptoType {
                Divider()

                HStack {
                    Image(systemName: cryptoTypeIcon(cryptoType))
                        .font(.title2)
                        .foregroundColor(.purple)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(cryptoType.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }
        }
    }

    private var activityGraphSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24-Hour Activity")
                .font(.headline)

            // Placeholder for activity graph
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 120)
                .overlay(
                    VStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Activity graph")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
        }
    }

    // MARK: - Helper Methods

    private func cryptoTypeIcon(_ type: CryptoType) -> String {
        switch type {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .dogecoin: return "d.circle.fill"
        case .monero: return "m.circle.fill"
        case .solana: return "s.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Stat Row Component

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let iconColor: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    let monitor = ClipboardMonitor()
    monitor.checksToday = 247
    monitor.threatsBlocked = 2
    monitor.lastDetectedAddress = "bc1qxy2...4a9c"
    monitor.lastDetectedCryptoType = .bitcoin
    monitor.isMonitoring = true

    return DashboardView(clipboardMonitor: monitor)
}
