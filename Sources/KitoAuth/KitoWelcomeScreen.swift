//
//  KitoWelcomeScreen.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI

/// A way to sign up or sign in, shown as a button on `KitoWelcomeScreen`.
public enum KitoAuthProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, google, email, phone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apple: return "Continue with Apple"
        case .google: return "Continue with Google"
        case .email: return "Continue with email"
        case .phone: return "Continue with phone"
        }
    }
}

/// One page of the `.carousel` welcome style.
public struct KitoWelcomePage: Identifiable, Sendable {
    public let id = UUID()
    public var systemImage: String
    public var title: String
    public var message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }
}

/// The backdrop of `KitoWelcomeScreen`.
public struct KitoWelcomeStyle {
    enum Kind {
        case gradient([Color])
        case photo(Image)
        case carousel([KitoWelcomePage])
        case minimal
    }

    let kind: Kind

    /// A slowly drifting mesh gradient (a blurred-orb fallback before iOS 18).
    public static var gradient: KitoWelcomeStyle { KitoWelcomeStyle(kind: .gradient(defaultColors)) }
    /// A mesh gradient in your own colours.
    public static func gradient(_ colors: [Color]) -> KitoWelcomeStyle {
        KitoWelcomeStyle(kind: .gradient(colors.isEmpty ? defaultColors : colors))
    }
    /// A full-bleed photo with a slow zoom and a dark scrim under the buttons.
    public static func photo(_ image: Image) -> KitoWelcomeStyle { KitoWelcomeStyle(kind: .photo(image)) }
    /// Swipeable value-proposition pages that advance on their own.
    public static func carousel(_ pages: [KitoWelcomePage]) -> KitoWelcomeStyle { KitoWelcomeStyle(kind: .carousel(pages)) }
    /// Just the logo, title and buttons on the theme background.
    public static var minimal: KitoWelcomeStyle { KitoWelcomeStyle(kind: .minimal) }

    static let defaultColors: [Color] = [
        Color(red: 0.09, green: 0.07, blue: 0.22), Color(red: 0.36, green: 0.19, blue: 0.78), Color(red: 0.93, green: 0.33, blue: 0.53),
        Color(red: 0.15, green: 0.12, blue: 0.45), Color(red: 0.99, green: 0.55, blue: 0.36), Color(red: 0.48, green: 0.22, blue: 0.85),
        Color(red: 0.05, green: 0.05, blue: 0.14), Color(red: 0.21, green: 0.12, blue: 0.52), Color(red: 0.08, green: 0.06, blue: 0.2),
    ]

    var isDark: Bool {
        switch kind {
        case .gradient, .photo: return true
        case .carousel, .minimal: return false
        }
    }
}

/// A landing screen: a backdrop, your name and pitch, a stack of provider buttons and
/// "Already have an account? Sign in".
///
/// ```swift
/// KitoWelcomeScreen(title: "Kito", subtitle: "Plan trips with friends.", style: .gradient) { provider in
///     switch provider {
///     case .apple: Task { try await signIn(with: KitoAppleSignIn.signIn()) }
///     case .google: googleSignIn()
///     case .email, .phone: path.append(provider)
///     }
/// } onSignIn: { path.append(.signIn) }
/// ```
public struct KitoWelcomeScreen: View {
    let title: String
    let subtitle: String?
    let style: KitoWelcomeStyle
    let providers: [KitoAuthProvider]
    var logo: Image?
    var tint: Color?
    let onProvider: (KitoAuthProvider) -> Void
    var onSignIn: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(title: String, subtitle: String? = nil, style: KitoWelcomeStyle = .gradient,
                providers: [KitoAuthProvider] = [.apple, .google, .email], logo: Image? = nil, tint: Color? = nil,
                onProvider: @escaping (KitoAuthProvider) -> Void, onSignIn: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.providers = providers
        self.logo = logo
        self.tint = tint
        self.onProvider = onProvider
        self.onSignIn = onSignIn
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var ink: Color { style.isDark ? .white : theme.colors.onBackground }

    public var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                if case .carousel(let pages) = style.kind {
                    brand(compact: true)
                        .padding(.top, theme.spacing.xl)
                    WelcomeCarousel(pages: pages, accent: palette.accent)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: theme.spacing.xl)
                    brand(compact: false)
                    Spacer(minLength: theme.spacing.xl)
                }
                buttons
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
            .frame(maxWidth: 520)
        }
        .onAppear { withAnimation(.authSpring(reduceMotion, bounce: 0.3).delay(0.1)) { appeared = true } }
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        switch style.kind {
        case .gradient(let colors):
            AnimatedMesh(colors: colors).ignoresSafeArea()
        case .photo(let image):
            PhotoBackdrop(image: image)
        case .carousel, .minimal:
            AuthBackground(accent: palette.accent)
        }
    }

    // MARK: Brand

    private func brand(compact: Bool) -> some View {
        VStack(spacing: compact ? theme.spacing.sm : theme.spacing.lg) {
            if let logo {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
                    .padding(compact ? 10 : 18)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 14 : 24, style: .continuous)
                            .fill(style.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(palette.accent.opacity(0.1)))
                    )
                    .foregroundStyle(style.isDark ? .white : palette.accent)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(compact ? theme.typography.titleMedium : .system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
            if let subtitle, !compact {
                Text(subtitle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(.authSpring(reduceMotion).delay(0.08), value: appeared)
            }
        }
        .shadow(color: style.isDark ? .black.opacity(0.25) : .clear, radius: 12, y: 4)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: theme.spacing.md - 2) {
            ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                KitoProviderButton(provider, onDark: style.isDark, tint: tint) { onProvider(provider) }
                    .offset(y: appeared || reduceMotion ? 0 : 40)
                    .opacity(appeared ? 1 : 0)
                    .animation(.authSpring(reduceMotion, bounce: 0.25).delay(0.15 + Double(index) * 0.06), value: appeared)
            }
            if let onSignIn {
                HStack(spacing: theme.spacing.xs) {
                    Text("Already have an account?").foregroundStyle(ink.opacity(0.7))
                    Button("Sign in") {
                        AuthHaptics.tap()
                        onSignIn()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(style.isDark ? .white : palette.accent)
                }
                .font(theme.typography.label)
                .padding(.top, theme.spacing.sm)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.45), value: appeared)
            }
        }
    }
}

/// A Kito capsule for one sign-in provider. Google is a styled button only: call your own
/// Google Sign-In code from `action`.
public struct KitoProviderButton: View {
    let provider: KitoAuthProvider
    var onDark: Bool
    var tint: Color?
    let action: () -> Void

    @Environment(\.kitoTheme) private var theme

    /// - Parameter onDark: Use the white variants, for photos and gradients.
    public init(_ provider: KitoAuthProvider, onDark: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.provider = provider
        self.onDark = onDark
        self.tint = tint
        self.action = action
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }

    public var body: some View {
        switch provider {
        case .apple:
            ProviderCapsule(title: provider.title,
                            style: onDark ? .filled(background: .white, foreground: .black)
                                          : .filled(background: palette.accent, foreground: palette.onAccent),
                            logo: { AppleLogo() }, action: action)
        case .google:
            ProviderCapsule(title: provider.title,
                            style: onDark ? .filled(background: .white.opacity(0.16), foreground: .white)
                                          : .filled(background: theme.colors.surface, foreground: theme.colors.onSurface),
                            logo: { GoogleLogo().frame(width: 18, height: 18) }, action: action)
                .overlay(Capsule().strokeBorder(onDark ? .white.opacity(0.25) : theme.colors.border, lineWidth: 1).allowsHitTesting(false))
        case .email:
            ProviderCapsule(title: provider.title, style: .outline(onDark ? .white.opacity(0.85) : theme.colors.onBackground.opacity(0.85)),
                            logo: { Image(systemName: "envelope.fill") }, action: action)
        case .phone:
            ProviderCapsule(title: provider.title, style: .outline(onDark ? .white.opacity(0.85) : theme.colors.onBackground.opacity(0.85)),
                            logo: { Image(systemName: "phone.fill") }, action: action)
        }
    }
}

/// A four-colour "G" drawn from arcs.
struct GoogleLogo: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let line = size * 0.2
            ZStack {
                arc(0.0, 0.13, Color(red: 0.26, green: 0.52, blue: 0.96), line)
                arc(0.13, 0.42, Color(red: 0.20, green: 0.66, blue: 0.33), line)
                arc(0.42, 0.58, Color(red: 0.98, green: 0.74, blue: 0.02), line)
                arc(0.58, 0.875, Color(red: 0.92, green: 0.26, blue: 0.21), line)
                Rectangle()
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: size * 0.46, height: line)
                    .offset(x: size * 0.23 - line * 0.1)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ color: Color, _ line: CGFloat) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
            .padding(line / 2)
    }
}

// MARK: - Backdrops

/// A 3×3 mesh whose inner points drift, or blurred orbs before iOS 18. Still under Reduce Motion.
struct AnimatedMesh: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: points(time), colors: meshColors)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom))
            } else {
                orbs(time)
            }
        }
        .accessibilityHidden(true)
    }

    private var meshColors: [Color] {
        (0..<9).map { colors[$0 % max(1, colors.count)] }
    }

    private func points(_ time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time)
        func wobble(_ speed: Float, _ phase: Float, _ amount: Float) -> Float { sin(t * speed + phase) * amount }
        return [
            [0, 0], [0.5 + wobble(0.35, 0, 0.12), 0], [1, 0],
            [0, 0.5 + wobble(0.4, 1, 0.1)], [0.5 + wobble(0.5, 2, 0.18), 0.5 + wobble(0.45, 3, 0.16)], [1, 0.5 + wobble(0.3, 4, 0.12)],
            [0, 1], [0.5 + wobble(0.42, 5, 0.14), 1], [1, 1],
        ]
    }

    /// Where orb `index` drifts to at `time`; split out so the compiler checks it quickly.
    private static func orbOffset(index: Int, time t: Double) -> CGSize {
        let i = Double(index)
        let x: Double = cos(t + i * 1.6) * 110
        let y: Double = sin(t * 0.8 + i) * 180
        return CGSize(width: x, height: y)
    }

    private func orbs(_ time: TimeInterval) -> some View {
        let t = time * 0.4
        return ZStack {
            (colors.first ?? .black)
            ForEach(0..<min(4, colors.count), id: \.self) { index in
                Circle()
                    .fill(colors[(index * 2 + 1) % colors.count])
                    .frame(width: 320, height: 320)
                    .offset(Self.orbOffset(index: index, time: t))
                    .blur(radius: 70)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
        }
    }
}

/// A photo that slowly zooms, with a scrim so white buttons stay readable.
struct PhotoBackdrop: View {
    let image: Image
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomed = false

    var body: some View {
        GeometryReader { proxy in
            image
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(zoomed ? 1.12 : 1)
                .clipped()
                .overlay(
                    LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                           .init(color: .black.opacity(0.55), location: 0.6), .init(color: .black.opacity(0.9), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                )
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { zoomed = true }
        }
        .accessibilityHidden(true)
    }
}

/// Paged value props with stretching dots; advances every few seconds until touched.
struct WelcomeCarousel: View {
    let pages: [KitoWelcomePage]
    var accent: Color
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0
    @State private var autoAdvance = true

    var body: some View {
        VStack(spacing: theme.spacing.lg) {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    CarouselPage(page: page, accent: accent, isCurrent: index == selection)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(DragGesture().onChanged { _ in autoAdvance = false })

            HStack(spacing: theme.spacing.xs + 2) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selection ? accent : theme.colors.border)
                        .frame(width: index == selection ? 24 : 8, height: 8)
                }
            }
            .animation(.authSpring(reduceMotion, bounce: 0.4), value: selection)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(selection + 1) of \(max(1, pages.count))")
        }
        .padding(.bottom, theme.spacing.xl)
        .task(id: autoAdvance) {
            guard autoAdvance, !reduceMotion, pages.count > 1 else { return }
            while !Task.isCancelled && autoAdvance {
                try? await Task.sleep(for: .seconds(3.5))
                guard autoAdvance, !Task.isCancelled else { break }
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { selection = (selection + 1) % pages.count }
            }
        }
    }
}

struct CarouselPage: View {
    let page: KitoWelcomePage
    var accent: Color
    var isCurrent: Bool
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            ZStack {
                Circle().fill(accent.opacity(0.06)).frame(width: 200, height: 200)
                    .scaleEffect(isCurrent && !reduceMotion ? 1 : 0.8)
                Circle().fill(accent.opacity(0.1)).frame(width: 150, height: 150)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(accent.gradient)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(isCurrent || reduceMotion ? 0 : -12))
                    .shadow(color: accent.opacity(0.35), radius: 18, y: 10)
                Image(systemName: page.systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isCurrent)
            }
            .accessibilityHidden(true)
            VStack(spacing: theme.spacing.sm) {
                Text(page.title)
                    .font(theme.typography.displayMedium)
                    .foregroundStyle(theme.colors.onBackground)
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.onBackground.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(y: isCurrent || reduceMotion ? 0 : 20)
            .opacity(isCurrent ? 1 : 0.3)
        }
        .padding(.horizontal, theme.spacing.lg)
        .animation(.authSpring(reduceMotion, bounce: 0.35), value: isCurrent)
        .accessibilityElement(children: .combine)
    }
}
