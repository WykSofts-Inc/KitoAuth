//
//  KitoPasswordStrength.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// How hard a password is to guess, from nothing typed to strong.
public enum KitoPasswordStrength: Int, Comparable, CaseIterable, Sendable {
    case empty, weak, fair, good, strong

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// "Weak", "Fair", "Good" or "Strong".
    public var title: String {
        switch self {
        case .empty: return ""
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        }
    }

    /// How many of the meter's four segments are lit.
    public var filledSegments: Int { rawValue }
}

/// One requirement in the live checklist, such as "At least 8 characters".
public struct KitoPasswordRule: Identifiable, Sendable {
    public let id: String
    public let title: String
    private let test: @Sendable (String) -> Bool

    public init(id: String, title: String, test: @escaping @Sendable (String) -> Bool) {
        self.id = id
        self.title = title
        self.test = test
    }

    public func isSatisfied(by password: String) -> Bool { test(password) }

    public static func minimumLength(_ count: Int) -> KitoPasswordRule {
        KitoPasswordRule(id: "length", title: "At least \(count) characters") { $0.count >= count }
    }
    public static let uppercase = KitoPasswordRule(id: "upper", title: "An uppercase letter") { $0.contains(where: \.isUppercase) }
    public static let lowercase = KitoPasswordRule(id: "lower", title: "A lowercase letter") { $0.contains(where: \.isLowercase) }
    public static let number = KitoPasswordRule(id: "number", title: "A number") { $0.contains(where: \.isNumber) }
    public static let symbol = KitoPasswordRule(id: "symbol", title: "A symbol, like ! or #") { password in
        password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
    }
    public static let notCommon = KitoPasswordRule(id: "common", title: "Not a common password") { password in
        !password.isEmpty && !KitoPasswordPolicy.isCommon(password)
    }
}

/// The result of checking a password against a policy.
public struct KitoPasswordEvaluation: Equatable, Sendable {
    public let strength: KitoPasswordStrength
    /// Raw points before mapping to a strength: length and character variety.
    public let score: Int
    /// IDs of the rules the password meets.
    public let satisfiedRuleIDs: Set<String>
    /// True when every rule is met and the strength reaches the policy's minimum.
    public let isAcceptable: Bool
}

/// Rules plus a minimum strength. `.standard` asks for 8+ characters, mixed case, a number and
/// nothing from the common-password list.
public struct KitoPasswordPolicy: Sendable {
    public var rules: [KitoPasswordRule]
    public var minimumStrength: KitoPasswordStrength

    public init(rules: [KitoPasswordRule], minimumStrength: KitoPasswordStrength = .fair) {
        self.rules = rules
        self.minimumStrength = minimumStrength
    }

    public static let standard = KitoPasswordPolicy(rules: [.minimumLength(8), .uppercase, .lowercase, .number, .notCommon])
    public static let strict = KitoPasswordPolicy(rules: [.minimumLength(12), .uppercase, .lowercase, .number, .symbol, .notCommon],
                                                  minimumStrength: .good)
    public static let relaxed = KitoPasswordPolicy(rules: [.minimumLength(8), .notCommon], minimumStrength: .weak)

    /// Checks `password` against every rule and scores its strength.
    public func evaluate(_ password: String) -> KitoPasswordEvaluation {
        let satisfied = Set(rules.filter { $0.isSatisfied(by: password) }.map(\.id))
        let (score, strength) = Self.strength(of: password)
        let acceptable = satisfied.count == rules.count && strength >= minimumStrength
        return KitoPasswordEvaluation(strength: strength, score: score, satisfiedRuleIDs: satisfied, isAcceptable: acceptable)
    }

    /// Scores length (8, 12, 16) plus one point for each character class beyond the first.
    /// Common passwords, one repeated character and simple runs like "abcd1234" stay weak.
    static func strength(of password: String) -> (Int, KitoPasswordStrength) {
        guard !password.isEmpty else { return (0, .empty) }
        let length = password.count
        let lengthPoints = [8, 12, 16].filter { length >= $0 }.count
        let classes = [
            password.contains(where: \.isLowercase),
            password.contains(where: \.isUppercase),
            password.contains(where: \.isNumber),
            password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace },
        ].filter { $0 }.count
        let score = lengthPoints + max(0, classes - 1)

        var strength: KitoPasswordStrength
        switch score {
        case ...1: strength = .weak
        case 2: strength = .fair
        case 3...4: strength = .good
        default: strength = .strong
        }
        if length < 8 { strength = min(strength, .weak) }
        if isCommon(password) || isTrivial(password) { strength = .weak }
        else if isCommon(baseWord(of: password)) { strength = min(strength, .fair) }
        return (score, strength)
    }

    /// True when the password, ignoring case, is on the built-in common-password list.
    public static func isCommon(_ password: String) -> Bool {
        commonPasswords.contains(password.lowercased())
    }

    /// "Password123!" → "password": the word with trailing digits and symbols removed.
    static func baseWord(of password: String) -> String {
        var base = Substring(password.lowercased())
        while let last = base.last, !last.isLetter { base.removeLast() }
        return String(base)
    }

    /// One repeated character, or a straight run of letters or digits ("abcdefgh", "12345678").
    static func isTrivial(_ password: String) -> Bool {
        let scalars = password.lowercased().unicodeScalars.map(\.value)
        guard scalars.count > 1 else { return true }
        if Set(scalars).count == 1 { return true }
        let steps = zip(scalars.dropFirst(), scalars).map { Int($0) - Int($1) }
        return steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
    }

    static let commonPasswords: Set<String> = [
        "123456", "1234567", "12345678", "123456789", "1234567890", "111111", "000000", "123123",
        "password", "password1", "password12", "password123", "passw0rd", "p@ssw0rd", "p@ssword", "qwerty",
        "qwerty123", "qwertyuiop", "asdfgh", "asdfghjkl", "zxcvbnm", "abc123", "abcd1234", "iloveyou",
        "admin", "admin123", "welcome", "welcome1", "welcome123", "letmein", "monkey", "dragon",
        "football", "baseball", "sunshine", "princess", "shadow", "superman", "master", "michael",
        "trustno1", "whatever", "freedom", "starwars", "hello123", "login", "secret", "changeme",
        "1q2w3e4r", "1qaz2wsx", "q1w2e3r4", "zaq12wsx", "qazwsx", "google", "computer", "mustang",
        "football1", "charlie", "jordan23", "summer2026", "winter2026", "spring2026", "autumn2026",
    ]
}
