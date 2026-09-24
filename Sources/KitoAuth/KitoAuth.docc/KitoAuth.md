# ``KitoAuth``

Sign in with Apple, passkeys, one-time codes, password reset, magic links, app lock, and two-factor setup for SwiftUI.

## Overview

KitoAuth covers everything around sign-in: the system sign-in methods, code
verification, account recovery, locking the app, welcome screens, and enrolling
in two-factor authentication. The basic sign-in, sign-up, and edit-profile forms
live in KitoScreens.

Every server call is an `async throws` closure that returns a
``KitoAuthResult``. Return `.success` to play the success animation, or
`.failure(message:)` to shake the screen and show the message inline. A thrown
error is shown as a failure, and a cancelled system sheet resets quietly.

```swift
KitoOTPScreen(destination: "+254 712 345 678") { code in
    try await api.verify(code) ? .success : .failure(message: "That code isn't right")
}
.channels([.sms, .whatsApp, .email])
.resend(after: 30) { channel in
    try await api.sendCode(via: channel)
    return .success
}
.onVerified { router.push(.home) }
```

To protect the whole app, apply `kitoAppLock(isLocked:timeout:configuration:verifyPIN:)`
to the root view. It offers Face ID or Touch ID first, then a PIN pad with a
lockout after too many wrong attempts, and blurs the app in the app switcher.

Some features need project setup: Sign in with Apple needs its capability,
passkeys need a `webcredentials:` Associated Domain, and Face ID needs
`NSFaceIDUsageDescription` in the Info.plist. Every view reads
`@Environment(\.kitoTheme)` from KitoCore and accepts an optional `tint`.

## Topics

### Essentials

- ``KitoAuthResult``
- ``KitoAuthError``

### Sign in with Apple

- ``KitoAppleSignInButton``
- ``KitoAppleSignIn``
- ``KitoAppleCredential``
- ``KitoAppleButtonStyle``
- ``KitoAppleButtonLabel``

### Passkeys

- ``KitoPasskeys``
- ``KitoPasskeyButton``
- ``KitoPasskeyRegistration``
- ``KitoPasskeyAssertion``

### One-Time Codes and Magic Links

- ``KitoOTPScreen``
- ``KitoOTPChannel``
- ``KitoCodeField``
- ``KitoCodeFieldState``
- ``KitoOTPCode``
- ``KitoCountdownFormat``
- ``KitoMagicLinkScreen``

### Password Reset

- ``KitoForgotPasswordFlow``
- ``KitoForgotPasswordStep``
- ``KitoPasswordReset``
- ``KitoPasswordStrengthMeter``
- ``KitoPasswordPolicy``
- ``KitoPasswordEvaluation``
- ``KitoPasswordRule``
- ``KitoAuthPasswordStrength``

### App Lock

- ``KitoAppLockScreen``
- ``KitoAppLockConfiguration``
- ``KitoBiometricUnlock``
- ``KitoLockoutPolicy``
- ``KitoLockoutState``

### Welcome Screens

- ``KitoWelcomeScreen``
- ``KitoWelcomeStyle``
- ``KitoWelcomePage``
- ``KitoAuthProvider``
- ``KitoProviderButton``

### Two-Factor Setup

- ``KitoTwoFactorSetup``
- ``KitoTwoFactorStep``
- ``KitoRecoveryCodesView``
- ``KitoOTPAuthURL``
- ``KitoTOTP``
- ``KitoBase32``
- ``KitoQRCode``
- ``KitoRecoveryCodes``

### Flow Support

- ``KitoStepFlow``
