//
//  CryptoPattern.swift
//  Clipboard
//
//  Created by Aayush Giri on 18/10/25.
//

import Foundation

/// Represents different cryptocurrency types
enum CryptoType: String, CaseIterable {
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case litecoin = "Litecoin"
    case dogecoin = "Dogecoin"
    case monero = "Monero"
    case solana = "Solana"
    case unknown = "Unknown"
}

/// Pattern definition for cryptocurrency address detection
struct CryptoPattern {
    let type: CryptoType
    let pattern: String
    let description: String

    /// Compiled regex pattern
    var regex: NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [])
    }
}

/// Pre-defined cryptocurrency patterns based on technical specs
struct CryptoPatterns {
    static let bitcoin: [CryptoPattern] = [
        CryptoPattern(
            type: .bitcoin,
            pattern: "^[1][a-km-zA-HJ-NP-Z1-9]{25,34}$",
            description: "Bitcoin Legacy (P2PKH)"
        ),
        CryptoPattern(
            type: .bitcoin,
            pattern: "^[3][a-km-zA-HJ-NP-Z1-9]{25,34}$",
            description: "Bitcoin Legacy (P2SH)"
        ),
        CryptoPattern(
            type: .bitcoin,
            pattern: "^bc1[a-z0-9]{39,59}$",
            description: "Bitcoin SegWit (Bech32)"
        ),
        CryptoPattern(
            type: .bitcoin,
            pattern: "^bc1p[a-z0-9]{58}$",
            description: "Bitcoin Taproot (Bech32m)"
        )
    ]

    static let ethereum: [CryptoPattern] = [
        CryptoPattern(
            type: .ethereum,
            pattern: "^0x[a-fA-F0-9]{40}$",
            description: "Ethereum Standard"
        )
    ]

    static let litecoin: [CryptoPattern] = [
        CryptoPattern(
            type: .litecoin,
            pattern: "^[LM3][a-km-zA-HJ-NP-Z1-9]{26,33}$",
            description: "Litecoin Legacy"
        ),
        CryptoPattern(
            type: .litecoin,
            pattern: "^ltc1[a-z0-9]{39,59}$",
            description: "Litecoin SegWit"
        )
    ]

    static let dogecoin: [CryptoPattern] = [
        CryptoPattern(
            type: .dogecoin,
            pattern: "^D{1}[5-9A-HJ-NP-U]{1}[1-9A-HJ-NP-Za-km-z]{32}$",
            description: "Dogecoin Standard"
        )
    ]

    static let monero: [CryptoPattern] = [
        CryptoPattern(
            type: .monero,
            pattern: "^4[0-9AB][0-9a-zA-Z]{93}$",
            description: "Monero Standard"
        )
    ]

    static let solana: [CryptoPattern] = [
        CryptoPattern(
            type: .solana,
            pattern: "^[1-9A-HJ-NP-Za-km-z]{32,44}$",
            description: "Solana Standard"
        )
    ]

    /// All patterns combined (Bitcoin, Ethereum, Solana only for now)
    /// Order matters - most specific patterns first!
    static let all: [CryptoPattern] =
        ethereum + bitcoin + solana  // Ethereum first (most specific with 0x prefix)
}
