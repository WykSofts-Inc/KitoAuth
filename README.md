# KitoAuth

Everything around sign-in for SwiftUI: Sign in with Apple, passkeys, one-time codes, password
reset, magic links, an app lock with Face ID and a PIN pad, welcome screens and two-factor setup.
Every screen springs, shakes on errors, morphs into a tick on success, plays haptics, and respects
Reduce Motion, VoiceOver and dark mode. Part of the [Kito](https://github.com/WykSofts-Inc/KitoDevKit)
ecosystem.

The basic sign-in, sign-up and edit-profile forms live in
[KitoScreens](https://github.com/wykeenjenga/KitoScreens). KitoAuth covers everything around them.

Every server call is an `async throws` closure returning `KitoAuthResult`: `.success`, or
`.failure(message:)` to shake and show the message. A throw is shown as a failure, and a cancelled
system sheet resets quietly.

## Sign in with Apple

```swift
KitoAppleSignInButton(.black) { credential in           // .black, .white, .outline
    try await api.signIn(appleToken: credential.identityToken, name: credential.name)
    return .success
}

// Or without the button:
let credential = try await KitoAppleSignIn.signIn()      // throws KitoAuthError.cancelled on dismiss
```

`KitoAppleCredential` carries `userID`, `email`, `name`, `identityToken` and `authorizationCode`.
Apple only shares the email and name the first time someone signs in, so save them then.

## Passkeys

```swift
let passkeys = KitoPasskeys(relyingParty: "example.com")

KitoPasskeyButton {
    let assertion = try await passkeys.signIn(challenge: try await api.challenge())
    return try await api.verify(assertion) ? .success : .failure(message: "Passkey not recognised")
}

KitoPasskeyButton(.create) {
    let registration = try await passkeys.register(challenge: challenge, userID: user.handle, userName: user.email)
    try await api.store(registration)
    return .success
}
```

If the `webcredentials:` Associated Domain isn't set up, the button explains what to add instead of
showing a raw system error.

## One-time codes

```swift
KitoOTPScreen(destination: "+254 712 345 678") { code in
    try await api.verify(code) ? .success : .failure(message: "That code isn’t right")
}
.channels([.sms, .whatsApp, .email])                     // chips to switch channel
.resend(after: 30) { channel in try await api.sendCode(via: channel); return .success }
.changeDestination { dismiss() }                         // "Change number" / "Change email"
.onVerified { router.push(.home) }
```

4 to 8 digits in animated boxes, SMS autofill (`.oneTimeCode`), paste of a whole message ("Your
code is 123-456"), auto-submit, and a countdown ring on resend. The field is also available alone:

```swift
KitoCodeField(code: $code, length: 6, state: state) { code in submit(code) }
```

## Forgot password

```swift
KitoForgotPasswordFlow(email: typedEmail) { email in
    try await api.sendResetCode(to: email); return .success
} verifyCode: { email, code in
    try await api.checkResetCode(code, for: email) ? .success : .failure(message: "Wrong code")
} resetPassword: { reset in
    try await api.resetPassword(reset.newPassword, code: reset.code, email: reset.email)
    return .success
}
.onFinish { dismiss() }
```

Email, code, new password, done, with a step indicator and sliding transitions. The password step
has a live strength meter and a requirement checklist. Both are available alone:

```swift
KitoPasswordStrengthMeter(password: password, policy: .standard)   // .relaxed, .standard, .strict

let evaluation = KitoPasswordPolicy.standard.evaluate(password)
evaluation.strength        // .empty, .weak, .fair, .good, .strong
evaluation.isAcceptable
```

Scoring counts length and character variety, and keeps common passwords, repeats and simple runs
("abcd1234") weak.

## Magic link

```swift
KitoMagicLinkScreen(email: "wycliff@example.com") {
    try await api.sendMagicLink(to: email); return .success
}
.resendCooldown(60)
.changeEmail { dismiss() }
```

## App lock

```swift
ContentView()
    .kitoAppLock(isLocked: $isLocked, timeout: 30,
                 configuration: .init(userName: "Wycliff N", pinLength: 4)) { pin in
        pin == keychain.pin ? .success : .failure(message: "Wrong passcode")
    }
```

Face ID or Touch ID first, then a PIN pad with a shake on a wrong PIN and a lockout after too many
attempts (5 by default, then 30 s, 1 min, 5 min, 15 min). It locks when the app has been in the
background for `timeout` seconds and blurs the app in the app switcher. Wrong attempts are kept in
`UserDefaults` so relaunching doesn't reset a lockout. `KitoAppLockScreen` is available on its own
too.

## Welcome screens

```swift
KitoWelcomeScreen(title: "Kito", subtitle: "Plan trips with friends.", style: .gradient,
                  providers: [.apple, .google, .email, .phone], logo: Image("logo")) { provider in
    signIn(with: provider)
} onSignIn: { showSignIn = true }
```

Styles: `.gradient` (a drifting mesh), `.gradient([colors])`, `.photo(Image)`, `.carousel([pages])`
and `.minimal`. The Google button is styled only: call your own Google Sign-In code from the
callback. `KitoProviderButton(.google) { … }` gives you any single button.

## Two-factor setup

```swift
KitoTwoFactorSetup(issuer: "Kito", account: "wycliff@example.com",
                   secret: server.secret, recoveryCodes: server.recoveryCodes) { code in
    try await api.confirmTwoFactor(code) ? .success : .failure(message: "That code didn’t match")
}
.onFinish { dismiss() }
```

A QR code (from an `otpauth://` URL), the key in readable groups with copy, a code check, then
recovery codes with Copy all and Share. The pieces are public too:

```swift
KitoOTPAuthURL(issuer: "Kito", account: email, secret: secret).url
KitoQRCode.image(for: string)
KitoTOTP.code(secret: secret)                 // RFC 6238
KitoBase32.group(secret)                      // ["JBSW", "Y3DP", "EHPK", "3PXP"]
KitoRecoveryCodes.generate(count: 10)
```

## What your app needs

| Feature | Setup |
| --- | --- |
| Sign in with Apple | The **Sign in with Apple** capability |
| Passkeys | **Associated Domains** with `webcredentials:yourdomain.com`, and an `apple-app-site-association` file on that domain listing your app |
| Face ID | `NSFaceIDUsageDescription` in Info.plist. Without it the lock screen offers the PIN only |
| Open Mail | Nothing for Mail. Other clients need their scheme in `LSApplicationQueriesSchemes` |

## Theming

Everything reads `@Environment(\.kitoTheme)` from KitoCore. The accent is the theme's ink (black in
light mode, white in dark), or pass `tint:` to any view.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoAuth.git", from: "0.1.0")
```

iOS 17 or later. Depends only on [KitoCore](https://github.com/WykSofts-Inc/KitoCore).

## License

MIT — see [LICENSE](LICENSE).
