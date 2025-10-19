//
//  LicenseManager.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation
import Combine
import CryptoKit

/// Manages license validation and storage
/// Target: <10ms validation time, offline operation
class LicenseManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isLicensed: Bool = false
    @Published var licenseData: LicenseData?
    @Published var email: String?

    // MARK: - Private Properties

    private let keychainKey = "com.clipboardguard.license"

    // MARK: - Initialization

    init() {
        loadLicenseFromKeychain()
    }

    // MARK: - Public Methods

    /// Validates and activates a license key
    /// - Parameters:
    ///   - email: User's email address
    ///   - licenseKey: License key in format CGRD-XXXX-XXXX-XXXX-XXXX
    /// - Returns: True if license is valid and activated
    func validateAndActivate(email: String, licenseKey: String) -> Bool {
        // Validate format
        guard isValidLicenseFormat(licenseKey) else {
            print("❌ Invalid license format")
            return false
        }

        // TODO: Implement full RSA-2048 signature verification
        // For now, we'll use a simplified validation for development

        // Parse license key (simplified version)
        guard let licenseData = parseLicenseKey(licenseKey, email: email) else {
            print("❌ Failed to parse license key")
            return false
        }

        // Check expiration
        if licenseData.isExpired {
            print("❌ License has expired")
            return false
        }

        // Verify email hash
        let emailHash = hashEmail(email)
        guard licenseData.emailHash == emailHash else {
            print("❌ Email does not match license")
            return false
        }

        // Save to keychain
        guard saveLicenseToKeychain(email: email, licenseKey: licenseKey, data: licenseData) else {
            print("❌ Failed to save license to keychain")
            return false
        }

        // Update state
        self.isLicensed = true
        self.licenseData = licenseData
        self.email = email

        print("✅ License activated successfully")
        return true
    }

    /// Deactivates current license
    func deactivate() {
        deleteLicenseFromKeychain()
        isLicensed = false
        licenseData = nil
        email = nil
        print("🔓 License deactivated")
    }

    /// Checks if license needs renewal reminder
    func shouldShowRenewalReminder() -> Bool {
        guard let data = licenseData,
              let daysRemaining = data.daysUntilExpiry else {
            return false
        }

        // Show reminder at 30, 14, 7, and 1 days
        return [30, 14, 7, 1].contains(daysRemaining)
    }

    // MARK: - Private Methods

    /// Validates license key format: CGRD-XXXX-XXXX-XXXX-XXXX
    private func isValidLicenseFormat(_ key: String) -> Bool {
        let pattern = "^CGRD-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }

    /// Creates SHA-256 hash of email (lowercase)
    private func hashEmail(_ email: String) -> String {
        let lowercased = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(lowercased.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Parses license key into LicenseData
    /// TODO: Implement full JWT-like parsing with RSA verification
    private func parseLicenseKey(_ key: String, email: String) -> LicenseData? {
        // Simplified version for development
        // In production, this would decode the Base64 JWT structure and verify RSA signature

        // For now, create a demo license
        let emailHash = hashEmail(email)
        let issuedAt = Date()

        // Check if it's an annual or lifetime license (based on key pattern)
        let isLifetime = key.contains("LIFE") || key.contains("PERM")
        let product: LicenseType = isLifetime ? .lifetime : .annual

        let expiresAt: Date? = isLifetime ? nil : Calendar.current.date(byAdding: .year, value: 1, to: issuedAt)

        return LicenseData(
            emailHash: emailHash,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            product: product,
            licenseId: UUID().uuidString,
            version: 1
        )
    }

    // MARK: - Keychain Methods

    /// Saves license to Keychain
    private func saveLicenseToKeychain(email: String, licenseKey: String, data: LicenseData) -> Bool {
        // Encode license data
        guard let encodedData = try? JSONEncoder().encode(data) else {
            return false
        }

        // Create dictionary with license info (convert Data to base64 string for JSON)
        let licenseInfo: [String: Any] = [
            "email": email,
            "licenseKey": licenseKey,
            "data": encodedData.base64EncodedString()
        ]

        // Serialize to data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: licenseInfo) else {
            return false
        }

        // Save to keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: jsonData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads license from Keychain
    private func loadLicenseFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let licenseInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = licenseInfo["email"] as? String,
              let dataBase64 = licenseInfo["data"] as? String,
              let dataEncoded = Data(base64Encoded: dataBase64),
              let licenseData = try? JSONDecoder().decode(LicenseData.self, from: dataEncoded) else {
            return
        }

        // Check if expired
        guard !licenseData.isExpired else {
            print("⚠️ License has expired")
            return
        }

        // Update state
        self.isLicensed = true
        self.licenseData = licenseData
        self.email = email

        print("✅ License loaded from keychain")
    }

    /// Deletes license from Keychain
    private func deleteLicenseFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]

        SecItemDelete(query as CFDictionary)
    }
}
