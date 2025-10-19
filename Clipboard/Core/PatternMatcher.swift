//
//  PatternMatcher.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation

/// High-performance pattern matcher for cryptocurrency addresses
/// Target: <1ms per check, 99.9%+ accuracy
class PatternMatcher {

    // MARK: - Properties

    /// Cached compiled patterns for performance
    private let patterns: [CryptoPattern]

    // MARK: - Initialization

    init(patterns: [CryptoPattern] = CryptoPatterns.all) {
        self.patterns = patterns
    }

    // MARK: - Public Methods

    /// Detects if the given string is a cryptocurrency address
    /// - Parameter text: String to check
    /// - Returns: Detected crypto type or nil if not a crypto address
    func detectCryptoType(_ text: String) -> CryptoType? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        print("🔍 [PatternMatcher] Testing: \"\(trimmed)\"")
        print("   Length: \(trimmed.count)")

        // Quick length check for performance
        guard trimmed.count >= 26 && trimmed.count <= 95 else {
            print("   ❌ Length check failed (need 26-95 chars)")
            return nil
        }

        // Check against all patterns
        // Note: Order matters - more specific patterns first
        for pattern in patterns {
            print("   🧪 Testing pattern: \(pattern.description)")
            if matches(trimmed, pattern: pattern) {
                print("   ✅ MATCH! Type: \(pattern.type.rawValue)")
                return pattern.type
            }
        }

        print("   ❌ No patterns matched")
        return nil
    }

    /// Check if text is a Bitcoin address (any format)
    func isBitcoin(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CryptoPatterns.bitcoin.contains { matches(trimmed, pattern: $0) }
    }

    /// Check if text is an Ethereum address
    func isEthereum(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic pattern check
        guard CryptoPatterns.ethereum.contains(where: { matches(trimmed, pattern: $0) }) else {
            return false
        }

        // TODO: Add EIP-55 checksum validation for enhanced security
        return true
    }

    /// Check if text is a Litecoin address
    func isLitecoin(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CryptoPatterns.litecoin.contains { matches(trimmed, pattern: $0) }
    }

    /// Check if text is a Dogecoin address
    func isDogecoin(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CryptoPatterns.dogecoin.contains { matches(trimmed, pattern: $0) }
    }

    /// Check if text is a Monero address
    func isMonero(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CryptoPatterns.monero.contains { matches(trimmed, pattern: $0) }
    }

    /// Check if text is a Solana address
    func isSolana(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CryptoPatterns.solana.contains { matches(trimmed, pattern: $0) }
    }

    // MARK: - Private Methods

    /// Efficiently matches text against a pattern
    private func matches(_ text: String, pattern: CryptoPattern) -> Bool {
        guard let regex = pattern.regex else { return false }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
