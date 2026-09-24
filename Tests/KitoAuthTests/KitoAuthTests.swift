//
//  KitoAuthTests.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import AuthenticationServices
import XCTest
@testable import KitoAuth

final class PasswordStrengthTests: XCTestCase {
    private let policy = KitoPasswordPolicy.standard

    func testEmptyPasswordIsEmpty() {
        let result = policy.evaluate("")
        XCTAssertEqual(result.strength, .empty)
        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.satisfiedRuleIDs.isEmpty)
    }

    func testShortPasswordsStayWeak() {
        XCTAssertEqual(policy.evaluate("Ab1!").strength, .weak)
        XCTAssertEqual(policy.evaluate("xY7#qL2").strength, .weak)
    }

    func testCommonPasswordsAreWeakWhateverTheirVariety() {
        XCTAssertEqual(policy.evaluate("Password123").strength, .weak)
        XCTAssertEqual(policy.evaluate("P@ssw0rd").strength, .weak)
        XCTAssertEqual(policy.evaluate("qwertyuiop").strength, .weak)
        XCTAssertTrue(KitoPasswordPolicy.isCommon("LetMeIn"))
    }

    func testCommonBaseWordIsCappedAtFair() {
        // "sunshine" is common; digits and symbols bolted on don't make it good.
        let result = policy.evaluate("Sunshine2026!!")
        XCTAssertEqual(result.strength, .fair)
        XCTAssertEqual(KitoPasswordPolicy.baseWord(of: "Sunshine2026!!"), "sunshine")
    }

    func testTrivialPatternsAreWeak() {
        XCTAssertTrue(KitoPasswordPolicy.isTrivial("aaaaaaaaaaaa"))
        XCTAssertTrue(KitoPasswordPolicy.isTrivial("abcdefghijkl"))
        XCTAssertTrue(KitoPasswordPolicy.isTrivial("987654321"))
        XCTAssertFalse(KitoPasswordPolicy.isTrivial("abcdefgh1"))
        XCTAssertEqual(policy.evaluate("zzzzzzzzzzzzzzzz").strength, .weak)
    }

    func testStrengthGrowsWithLengthAndVariety() {
        XCTAssertEqual(policy.evaluate("kitoridge").strength, .weak)      // 9, one class
        XCTAssertEqual(policy.evaluate("kitoridge7").strength, .fair)     // 10, two classes
        XCTAssertEqual(policy.evaluate("Kitoridge7").strength, .good)     // 10, three classes
        XCTAssertEqual(policy.evaluate("Kitoridge7!mango").strength, .strong)
    }

    func testStrengthsAreOrdered() {
        XCTAssertLessThan(KitoAuthPasswordStrength.weak, .fair)
        XCTAssertLessThan(KitoAuthPasswordStrength.good, .strong)
        XCTAssertEqual(KitoAuthPasswordStrength.strong.filledSegments, 4)
        XCTAssertEqual(KitoAuthPasswordStrength.fair.title, "Fair")
    }

    func testChecklistTicksLive() {
        XCTAssertEqual(policy.evaluate("k").satisfiedRuleIDs, ["lower", "common"])
        XCTAssertEqual(policy.evaluate("Kitoridge").satisfiedRuleIDs, ["length", "upper", "lower", "common"])
        XCTAssertEqual(policy.evaluate("Kitoridge7").satisfiedRuleIDs, ["length", "upper", "lower", "number", "common"])
    }

    func testAcceptableNeedsEveryRuleAndMinimumStrength() {
        XCTAssertTrue(policy.evaluate("Kitoridge7").isAcceptable)
        XCTAssertFalse(policy.evaluate("kitoridge7").isAcceptable)           // no uppercase
        XCTAssertFalse(policy.evaluate("Password1").isAcceptable)            // common
        XCTAssertFalse(KitoPasswordPolicy.strict.evaluate("Kitoridge7").isAcceptable)   // too short, no symbol
        XCTAssertTrue(KitoPasswordPolicy.strict.evaluate("Kitoridge7!mango").isAcceptable)
        XCTAssertTrue(KitoPasswordPolicy.relaxed.evaluate("kitoridge").isAcceptable)
    }

    func testSymbolRule() {
        XCTAssertTrue(KitoPasswordRule.symbol.isSatisfied(by: "a#b"))
        XCTAssertFalse(KitoPasswordRule.symbol.isSatisfied(by: "a b"))
        XCTAssertEqual(KitoPasswordRule.minimumLength(10).title, "At least 10 characters")
    }
}

final class OTPCodeTests: XCTestCase {
    func testSanitizeKeepsDigitsInOrderUpToLength() {
        XCTAssertEqual(KitoOTPCode.sanitize("12a3-4 5", length: 6), "12345")
        XCTAssertEqual(KitoOTPCode.sanitize("1234567890", length: 6), "123456")
        XCTAssertEqual(KitoOTPCode.sanitize("", length: 6), "")
        XCTAssertEqual(KitoOTPCode.sanitize("abc", length: 4), "")
    }

    func testSanitizeConvertsUnicodeDigits() {
        XCTAssertEqual(KitoOTPCode.sanitize("１２３４", length: 4), "1234")      // full-width
        XCTAssertEqual(KitoOTPCode.sanitize("٤٥٦٧", length: 4), "4567")        // Arabic-Indic
        XCTAssertEqual(KitoOTPCode.sanitize("½7", length: 4), "7")             // not a digit
    }

    func testExtractFindsCodeInMessages() {
        XCTAssertEqual(KitoOTPCode.extract(from: "Your Kito code is 482913. It expires in 10 minutes.", length: 6), "482913")
        XCTAssertEqual(KitoOTPCode.extract(from: "Code: 123-456", length: 6), "123456")
        XCTAssertEqual(KitoOTPCode.extract(from: "123 456", length: 6), "123456")
        XCTAssertEqual(KitoOTPCode.extract(from: "G-482913 is your code", length: 6), "482913")
        XCTAssertEqual(KitoOTPCode.extract(from: "Use 4821 to sign in", length: 4), "4821")
    }

    func testExtractPrefersTheRightSizedGroup() {
        XCTAssertEqual(KitoOTPCode.extract(from: "Ref 99, code 123456 10", length: 6), "123456")
        XCTAssertEqual(KitoOTPCode.extract(from: "482913 10", length: 6), "482913")
        XCTAssertNil(KitoOTPCode.extract(from: "Call 0712345678", length: 6))
        XCTAssertNil(KitoOTPCode.extract(from: "12", length: 6))
        XCTAssertNil(KitoOTPCode.extract(from: "123456", length: 0))
    }

    func testNormalizeHandlesTypingAndPaste() {
        XCTAssertEqual(KitoOTPCode.normalize("12", length: 6), "12")
        XCTAssertEqual(KitoOTPCode.normalize("Your code is 654 321", length: 6), "654321")
        XCTAssertEqual(KitoOTPCode.normalize("1234567", length: 6), "123456")
    }
}

final class CountdownTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(KitoCountdownFormat.clock(0), "0:00")
        XCTAssertEqual(KitoCountdownFormat.clock(9), "0:09")
        XCTAssertEqual(KitoCountdownFormat.clock(29), "0:29")
        XCTAssertEqual(KitoCountdownFormat.clock(90), "1:30")
        XCTAssertEqual(KitoCountdownFormat.clock(3723), "1:02:03")
        XCTAssertEqual(KitoCountdownFormat.clock(-5), "0:00")
    }

    func testResendTitle() {
        XCTAssertEqual(KitoCountdownFormat.resendTitle(29), "Resend in 0:29")
        XCTAssertEqual(KitoCountdownFormat.resendTitle(0), "Resend code")
    }

    func testSecondsRemainingRoundsUp() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(KitoCountdownFormat.secondsRemaining(until: now.addingTimeInterval(29.2), from: now), 30)
        XCTAssertEqual(KitoCountdownFormat.secondsRemaining(until: now.addingTimeInterval(30), from: now), 30)
        XCTAssertEqual(KitoCountdownFormat.secondsRemaining(until: now.addingTimeInterval(-3), from: now), 0)
    }
}

final class LockoutTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testLocksAfterMaxAttempts() {
        var state = KitoLockoutState(policy: KitoLockoutPolicy(maxAttempts: 3, lockoutDurations: [30, 60]))
        XCTAssertFalse(state.recordFailure(at: start))
        XCTAssertFalse(state.recordFailure(at: start))
        XCTAssertEqual(state.attemptsRemaining, 1)
        XCTAssertTrue(state.recordFailure(at: start))
        XCTAssertTrue(state.isLocked(at: start.addingTimeInterval(29)))
        XCTAssertEqual(state.remaining(at: start.addingTimeInterval(10)), 20, accuracy: 0.001)
        XCTAssertFalse(state.isLocked(at: start.addingTimeInterval(30)))
        XCTAssertEqual(state.attemptsRemaining, 3)
    }

    func testAttemptsWhileLockedAreIgnored() {
        var state = KitoLockoutState(policy: KitoLockoutPolicy(maxAttempts: 1, lockoutDurations: [30]))
        XCTAssertTrue(state.recordFailure(at: start))
        XCTAssertFalse(state.recordFailure(at: start.addingTimeInterval(5)))
        XCTAssertEqual(state.lockedUntil, start.addingTimeInterval(30))
    }

    func testLockoutsEscalateAndStayOnTheLastDuration() {
        var state = KitoLockoutState(policy: KitoLockoutPolicy(maxAttempts: 1, lockoutDurations: [30, 60]))
        var clock = start
        state.recordFailure(at: clock)
        XCTAssertEqual(state.remaining(at: clock), 30)
        clock = clock.addingTimeInterval(31)
        state.recordFailure(at: clock)
        XCTAssertEqual(state.remaining(at: clock), 60)
        clock = clock.addingTimeInterval(61)
        state.recordFailure(at: clock)
        XCTAssertEqual(state.remaining(at: clock), 60)
        XCTAssertEqual(state.lockoutCount, 3)
    }

    func testSuccessResets() {
        var state = KitoLockoutState(policy: KitoLockoutPolicy(maxAttempts: 2))
        state.recordFailure(at: start)
        state.recordSuccess()
        XCTAssertEqual(state.failedAttempts, 0)
        XCTAssertEqual(state.lockoutCount, 0)
        XCTAssertNil(state.lockedUntil)
        XCTAssertEqual(state.remaining(at: start), 0)
    }

    func testPolicyClampsInput() {
        let policy = KitoLockoutPolicy(maxAttempts: 0, lockoutDurations: [])
        XCTAssertEqual(policy.maxAttempts, 1)
        XCTAssertEqual(policy.duration(forLockout: 7), 30)
    }

    func testStateRoundTripsThroughCoding() throws {
        var state = KitoLockoutState(policy: KitoLockoutPolicy(maxAttempts: 2))
        state.recordFailure(at: start)
        state.recordFailure(at: start)
        let decoded = try JSONDecoder().decode(KitoLockoutState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.isLocked(at: start.addingTimeInterval(1)))
    }

    func testStorageKeyIsNamespacedByBundle() {
        let key = KitoAppLockConfiguration.defaultStorageKey
        XCTAssertNotEqual(key, "kito.appLock.lockout")
        XCTAssertTrue(key.hasSuffix(".kito.appLock.lockout"))
        XCTAssertEqual(KitoAppLockConfiguration().storageKey, key)
        XCTAssertNil(KitoAppLockConfiguration(storageKey: nil).storageKey)
    }

    func testScopedStorageKeys() {
        let payments = KitoAppLockConfiguration.storageKey(scope: "payments")
        XCTAssertTrue(payments.hasSuffix(".kito.appLock.payments.lockout"))
        XCTAssertNotEqual(payments, KitoAppLockConfiguration.storageKey(scope: "vault"))
        XCTAssertEqual(KitoAppLockConfiguration.storageKey(scope: "  "), KitoAppLockConfiguration.defaultStorageKey)
    }
}

final class TOTPTests: XCTestCase {
    func testBase32RoundTrip() {
        let data = Data("Hello!".utf8)
        let encoded = KitoBase32.encode(data)
        XCTAssertEqual(encoded, "JBSWY3DPEE")
        XCTAssertEqual(KitoBase32.decode(encoded), data)
        XCTAssertEqual(KitoBase32.decode("jbsw y3dp-ee======"), data)
        XCTAssertNil(KitoBase32.decode("JBSW1"))     // 1 isn't in the alphabet
    }

    func testRandomSecretIsBase32OfTheRightLength() {
        let secret = KitoBase32.randomSecret()
        XCTAssertEqual(secret.count, 32)
        XCTAssertTrue(secret.allSatisfy { KitoBase32.alphabet.contains($0) })
        XCTAssertNotEqual(secret, KitoBase32.randomSecret())
        XCTAssertEqual(KitoBase32.decode(secret)?.count, 20)
    }

    func testGrouping() {
        XCTAssertEqual(KitoBase32.group("jbswy3dpehpk3pxp"), ["JBSW", "Y3DP", "EHPK", "3PXP"])
        XCTAssertEqual(KitoBase32.group("JBSW Y3DP EH", size: 4), ["JBSW", "Y3DP", "EH"])
        XCTAssertEqual(KitoBase32.group("ABCDEF", size: 3), ["ABC", "DEF"])
        XCTAssertEqual(KitoBase32.group(""), [])
    }

    func testRFC6238Vectors() {
        let secret = KitoBase32.encode(Data("12345678901234567890".utf8))
        XCTAssertEqual(secret, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        XCTAssertEqual(KitoTOTP.code(secret: secret, at: Date(timeIntervalSince1970: 59), digits: 8), "94287082")
        XCTAssertEqual(KitoTOTP.code(secret: secret, at: Date(timeIntervalSince1970: 1_111_111_109), digits: 8), "07081804")
        XCTAssertEqual(KitoTOTP.code(secret: secret, at: Date(timeIntervalSince1970: 1_234_567_890), digits: 8), "89005924")
        XCTAssertEqual(KitoTOTP.code(secret: secret, at: Date(timeIntervalSince1970: 59)), "287082")
    }

    func testSHA256Vector() {
        let secret = KitoBase32.encode(Data("12345678901234567890123456789012".utf8))
        XCTAssertEqual(KitoTOTP.code(secret: secret, at: Date(timeIntervalSince1970: 59), digits: 8, algorithm: .sha256), "46119246")
    }

    func testValidationAllowsOneStepOfDrift() {
        let secret = "JBSWY3DPEHPK3PXP"
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = KitoTOTP.code(secret: secret, at: now.addingTimeInterval(-30)) ?? ""
        let old = KitoTOTP.code(secret: secret, at: now.addingTimeInterval(-90)) ?? ""
        XCTAssertTrue(KitoTOTP.isValid(previous, secret: secret, at: now))
        XCTAssertFalse(KitoTOTP.isValid(old, secret: secret, at: now))
        XCTAssertFalse(KitoTOTP.isValid("12", secret: secret, at: now))
        XCTAssertNil(KitoTOTP.code(secret: "not base32!"))
    }

    func testRecoveryCodes() {
        let codes = KitoRecoveryCodes.generate(count: 8)
        XCTAssertEqual(codes.count, 8)
        XCTAssertEqual(Set(codes).count, 8)
        for code in codes {
            XCTAssertEqual(code.count, 9)
            XCTAssertEqual(Array(code)[4], "-")
            XCTAssertFalse(code.contains("0") || code.contains("O") || code.contains("1") || code.contains("I"))
        }
    }
}

final class OTPAuthURLTests: XCTestCase {
    func testBuildsTheStandardURL() {
        let url = KitoOTPAuthURL(issuer: "Kito", account: "wycliff@example.com", secret: "jbsw y3dp ehpk 3pxp")
        XCTAssertEqual(url.string,
                       "otpauth://totp/Kito:wycliff%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Kito&algorithm=SHA1&digits=6&period=30")
        XCTAssertEqual(url.url?.scheme, "otpauth")
        XCTAssertEqual(url.url?.host, "totp")
    }

    func testEscapesSpacesPlusAndColons() {
        let url = KitoOTPAuthURL(issuer: "Kito Travel: Beta", account: "w+test@example.com", secret: "ABC", digits: 8, period: 60,
                                 algorithm: .sha256)
        XCTAssertEqual(url.string,
                       "otpauth://totp/Kito%20Travel%3A%20Beta:w%2Btest%40example.com?secret=ABC&issuer=Kito%20Travel%3A%20Beta&algorithm=SHA256&digits=8&period=60")
        XCTAssertNotNil(url.url)
    }

    func testOmitsIssuerWhenEmpty() {
        XCTAssertEqual(KitoOTPAuthURL(issuer: "", account: "wycliff", secret: "ABC").string,
                       "otpauth://totp/wycliff?secret=ABC&algorithm=SHA1&digits=6&period=30")
    }

    func testQRCodeRenders() throws {
        let url = KitoOTPAuthURL(issuer: "Kito", account: "wycliff@example.com", secret: KitoBase32.randomSecret())
        let image = try XCTUnwrap(KitoQRCode.image(for: url.string, scale: 4))
        XCTAssertGreaterThan(image.size.width, 80)
        XCTAssertEqual(image.size.width, image.size.height)
    }
}

final class StepFlowTests: XCTestCase {
    func testStartsOnFirstStep() {
        let flow = KitoStepFlow<KitoForgotPasswordStep>()
        XCTAssertEqual(flow.current, .email)
        XCTAssertTrue(flow.isFirst)
        XCTAssertFalse(flow.canGoBack)
        XCTAssertEqual(flow.progress, 0.25)
    }

    func testAdvancesAndGoesBack() {
        var flow = KitoStepFlow<KitoForgotPasswordStep>()
        XCTAssertTrue(flow.advance())
        XCTAssertEqual(flow.current, .code)
        XCTAssertEqual(flow.direction, .forward)
        XCTAssertTrue(flow.canGoBack)
        XCTAssertTrue(flow.back())
        XCTAssertEqual(flow.current, .email)
        XCTAssertEqual(flow.direction, .backward)
        XCTAssertFalse(flow.back())
    }

    func testCannotLeaveTheLastStep() {
        var flow = KitoStepFlow<KitoForgotPasswordStep>()
        flow.advance(); flow.advance(); flow.advance()
        XCTAssertEqual(flow.current, .done)
        XCTAssertTrue(flow.isLast)
        XCTAssertFalse(flow.canGoBack)
        XCTAssertFalse(flow.advance())
        XCTAssertFalse(flow.back())
        XCTAssertEqual(flow.progress, 1)
    }

    func testJumpAndReset() {
        var flow = KitoStepFlow<KitoTwoFactorStep>()
        XCTAssertTrue(flow.go(to: .recoveryCodes))
        XCTAssertEqual(flow.direction, .forward)
        XCTAssertTrue(flow.go(to: .scan))
        XCTAssertEqual(flow.direction, .backward)
        flow.advance()
        flow.reset()
        XCTAssertEqual(flow.current, .scan)
    }

    func testCustomSteps() {
        XCTAssertNil(KitoStepFlow<String>(steps: []))
        var flow = KitoStepFlow(steps: ["a", "b"])
        XCTAssertEqual(flow?.current, "a")
        XCTAssertFalse(flow?.go(to: "z") ?? true)
        flow?.advance()
        XCTAssertEqual(flow?.current, "b")
    }
}

final class ErrorTests: XCTestCase {
    func testMessages() {
        XCTAssertTrue(KitoAuthError.cancelled.isCancellation)
        XCTAssertTrue(KitoAuthError.passkeysNotConfigured(domain: "example.com").localizedDescription.contains("webcredentials:example.com"))
        XCTAssertEqual(KitoAuthError.failed(message: "Nope").localizedDescription, "Nope")
    }

    func testCatchingMapsThrowsToResults() async {
        let cancelled = await KitoAuthResult.catching { throw KitoAuthError.cancelled }
        XCTAssertNil(cancelled)
        let failed = await KitoAuthResult.catching { throw KitoAuthError.failed(message: "Server down") }
        XCTAssertEqual(failed, .failure(message: "Server down"))
        let success = await KitoAuthResult.catching { .success }
        XCTAssertEqual(success, .success)
    }

    @MainActor
    func testAuthorizationErrorMapping() {
        let cancel = NSError(domain: ASAuthorizationErrorDomainForTests.domain, code: 1001)
        XCTAssertEqual(AuthorizationSession.map(cancel), .cancelled)
        let unassociated = NSError(domain: ASAuthorizationErrorDomainForTests.domain, code: 1004, userInfo: [
            NSLocalizedFailureReasonErrorKey: "Application with identifier ABC is not associated with domain example.com",
        ])
        XCTAssertEqual(AuthorizationSession.map(unassociated, relyingParty: "example.com"), .passkeysNotConfigured(domain: "example.com"))
    }
}

private enum ASAuthorizationErrorDomainForTests {
    static let domain = ASAuthorizationError.errorDomain
}
