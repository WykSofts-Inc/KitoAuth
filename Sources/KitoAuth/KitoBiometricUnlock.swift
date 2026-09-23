//
//  KitoBiometricUnlock.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import LocalAuthentication

/// Face ID, Touch ID or Optic ID through LocalAuthentication.
///
/// Face ID needs `NSFaceIDUsageDescription` in your Info.plist. Without it the system would
/// terminate the app, so `isAvailable` reports false instead and the lock screen offers the PIN only.
public enum KitoBiometricUnlock {
    public enum Kind: Sendable { case none, faceID, touchID, opticID }

    /// What this device offers, if enrolled.
    public static var kind: Kind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    /// True when biometrics are enrolled and, for Face ID, the usage description is present.
    public static var isAvailable: Bool {
        switch kind {
        case .none: return false
        case .faceID, .opticID: return hasUsageDescription
        case .touchID: return true
        }
    }

    static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") != nil
    }

    /// "Face ID", "Touch ID", "Optic ID" or nil.
    public static var name: String? {
        switch kind {
        case .none: return nil
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        }
    }

    static var systemImage: String {
        switch kind {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }

    /// Prompts for biometrics. Returns true on a match; throws `.cancelled` when the person
    /// backs out and `.biometricsUnavailable` when there's nothing to use.
    public static func authenticate(reason: String = "Unlock the app") async throws -> Bool {
        guard isAvailable else { throw KitoAuthError.biometricsUnavailable }
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: throw KitoAuthError.cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout: throw KitoAuthError.biometricsUnavailable
            default: throw KitoAuthError.failed(message: error.localizedDescription)
            }
        }
    }
}
