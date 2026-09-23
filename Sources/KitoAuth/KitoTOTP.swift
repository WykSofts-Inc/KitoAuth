//
//  KitoTOTP.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CryptoKit
import Foundation

/// RFC 4648 base32, the encoding authenticator apps use for secrets.
public enum KitoBase32 {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// A random secret: 20 bytes (160 bits) by default, which encodes to 32 characters.
    public static func randomSecret(byteCount: Int = 20) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<max(1, byteCount)).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return encode(Data(bytes))
    }

    /// Encodes without padding.
    public static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output
    }

    /// Decodes, ignoring case, spaces, dashes and padding. Nil on any other character.
    public static func decode(_ string: String) -> Data? {
        var bytes: [UInt8] = []
        var buffer = 0
        var bits = 0
        for character in normalized(string) {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
            buffer &= (1 << bits) - 1
        }
        return Data(bytes)
    }

    /// Splits a secret into readable groups: "JBSW Y3DP EHPK 3PXP".
    public static func group(_ secret: String, size: Int = 4) -> [String] {
        let characters = Array(normalized(secret))
        let size = max(1, size)
        return stride(from: 0, to: characters.count, by: size).map {
            String(characters[$0 ..< min($0 + size, characters.count)])
        }
    }

    /// Uppercased, with spaces, dashes and "=" padding removed.
    public static func normalized(_ secret: String) -> String {
        secret.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "=" }
    }
}

/// The settings an authenticator app needs, and the otpauth:// URL that carries them.
public struct KitoOTPAuthURL: Equatable, Sendable {
    public enum Algorithm: String, Sendable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }

    public var issuer: String
    public var account: String
    public var secret: String
    public var digits: Int
    public var period: Int
    public var algorithm: Algorithm

    public init(issuer: String, account: String, secret: String, digits: Int = 6, period: Int = 30, algorithm: Algorithm = .sha1) {
        self.issuer = issuer
        self.account = account
        self.secret = secret
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
    }

    /// `otpauth://totp/Issuer:account?secret=…&issuer=…&algorithm=SHA1&digits=6&period=30`,
    /// strictly percent-encoded so spaces, "+" and "@" survive every scanner.
    public var string: String {
        let label = issuer.isEmpty ? Self.encode(account) : "\(Self.encode(issuer)):\(Self.encode(account))"
        var query = ["secret=\(KitoBase32.normalized(secret))"]
        if !issuer.isEmpty { query.append("issuer=\(Self.encode(issuer))") }
        query += ["algorithm=\(algorithm.rawValue)", "digits=\(digits)", "period=\(period)"]
        return "otpauth://totp/\(label)?\(query.joined(separator: "&"))"
    }

    public var url: URL? { URL(string: string) }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

/// Time-based one-time passwords (RFC 6238), for checking a code while setting up two-factor.
/// Your server should still be the one that verifies codes at sign-in.
public enum KitoTOTP {
    /// The code for `secret` (base32) at `date`, or nil if the secret doesn't decode.
    public static func code(secret: String, at date: Date = Date(), digits: Int = 6, period: Int = 30,
                            algorithm: KitoOTPAuthURL.Algorithm = .sha1) -> String? {
        guard let key = KitoBase32.decode(secret), !key.isEmpty, period > 0, (1...10).contains(digits) else { return nil }
        let counter = UInt64(max(0, date.timeIntervalSince1970) / Double(period))
        return code(key: key, counter: counter, digits: digits, algorithm: algorithm)
    }

    /// True when `code` matches the current period, or one either side to allow for clock drift.
    public static func isValid(_ code: String, secret: String, at date: Date = Date(), digits: Int = 6,
                               period: Int = 30, window: Int = 1) -> Bool {
        let code = KitoOTPCode.sanitize(code, length: digits)
        guard code.count == digits else { return false }
        return (-window...window).contains { step in
            Self.code(secret: secret, at: date.addingTimeInterval(TimeInterval(step * period)), digits: digits, period: period) == code
        }
    }

    static func code(key: Data, counter: UInt64, digits: Int, algorithm: KitoOTPAuthURL.Algorithm) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let symmetricKey = SymmetricKey(data: key)
        let mac: [UInt8]
        switch algorithm {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        }
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24) | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus = modulus &* 10 }
        let value = digits >= 10 ? binary : binary % modulus
        let text = String(value)
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }
}

/// One-time recovery codes such as "7KQ2-M9XD".
public enum KitoRecoveryCodes {
    /// `count` codes of two groups of `groupLength` characters, avoiding look-alikes (0/O, 1/I).
    public static func generate(count: Int = 10, groupLength: Int = 4) -> [String] {
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var generator = SystemRandomNumberGenerator()
        func group() -> String {
            String((0..<max(1, groupLength)).compactMap { _ in alphabet.randomElement(using: &generator) })
        }
        return (0..<max(0, count)).map { _ in "\(group())-\(group())" }
    }
}
