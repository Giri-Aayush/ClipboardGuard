//
//  LicenseData.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation

/// License product types
enum LicenseType: String, Codable {
    case annual = "clipboardguard_annual"
    case lifetime = "clipboardguard_lifetime"
}

/// License data structure
struct LicenseData: Codable {
    let emailHash: String
    let issuedAt: Date
    let expiresAt: Date?
    let product: LicenseType
    let licenseId: String
    let version: Int

    var isExpired: Bool {
        guard let expiresAt = expiresAt else {
            return false  // Lifetime license never expires
        }
        return Date() > expiresAt
    }

    var daysUntilExpiry: Int? {
        guard let expiresAt = expiresAt else {
            return nil  // Lifetime license
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day
        return days
    }
}
