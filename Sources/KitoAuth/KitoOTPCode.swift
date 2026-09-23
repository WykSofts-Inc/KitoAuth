//
//  KitoOTPCode.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Cleans up what lands in a code field: typing, paste and SMS autofill.
public enum KitoOTPCode {
    /// The digits in `text`, in order, capped at `length`. Full-width and other Unicode digits
    /// become ASCII; everything else is dropped.
    public static func sanitize(_ text: String, length: Int) -> String {
        var digits = ""
        for character in text {
            guard let value = character.wholeNumberValue, (0...9).contains(value), character.isNumber else { continue }
            digits.append(Character(String(value)))
            if digits.count == max(0, length) { break }
        }
        return digits
    }

    /// Finds a code of exactly `length` digits in a pasted message, such as
    /// "Your code is 123-456." or "G-482913". Digits may be split by one space, dash or dot.
    /// Returns nil when there is no run of the right size.
    public static func extract(from text: String, length: Int) -> String? {
        guard length > 0 else { return nil }
        // Each run is a list of digit groups joined by single separators: "123-456" → ["123", "456"].
        var runs: [[String]] = []
        var groups: [String] = []
        var current = ""
        var pendingSeparator = false
        func closeRun() {
            if !current.isEmpty { groups.append(current) }
            if !groups.isEmpty { runs.append(groups) }
            groups = []
            current = ""
            pendingSeparator = false
        }
        for character in text {
            if let value = character.wholeNumberValue, (0...9).contains(value), character.isNumber {
                current.append(Character(String(value)))
                pendingSeparator = false
            } else if !current.isEmpty, !pendingSeparator, separators.contains(character) {
                groups.append(current)
                current = ""
                pendingSeparator = true
            } else {
                closeRun()
            }
        }
        closeRun()
        for run in runs {
            let joined = run.joined()
            if joined.count == length { return joined }
            if let group = run.first(where: { $0.count == length }) { return group }
        }
        return nil
    }

    /// What a code field should hold after `input` arrives: an extracted code when a whole
    /// message was pasted, otherwise the sanitised digits.
    public static func normalize(_ input: String, length: Int) -> String {
        extract(from: input, length: length) ?? sanitize(input, length: length)
    }

    private static let separators: Set<Character> = [" ", "-", "–", ".", "·", "\u{00A0}"]
}

/// Formats seconds for countdowns such as "Resend in 0:29".
public enum KitoCountdownFormat {
    /// "0:09", "1:30" or "1:02:03". Negative values read as "0:00".
    public static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "Resend in 0:29" while counting, "Resend code" at zero.
    public static func resendTitle(_ seconds: Int) -> String {
        seconds > 0 ? "Resend in \(clock(seconds))" : "Resend code"
    }

    /// Whole seconds left until `date`, rounded up so a countdown never shows 0:00 early.
    public static func secondsRemaining(until date: Date, from now: Date = Date()) -> Int {
        max(0, Int((date.timeIntervalSince(now)).rounded(.up)))
    }
}
