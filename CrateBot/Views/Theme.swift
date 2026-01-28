import SwiftUI

// MARK: - Theme Design System
// "Vinyl Warmth" - Warm, analog-inspired design for crate digging

struct Theme {
    // MARK: - Colors

    struct Colors {
        // Background hierarchy (darkest to lightest) - warm undertones
        static let bgBase = Color(hex: "0d0c0b")
        static let bgWindow = Color(hex: "1a1816")
        static let bgElevated = Color(hex: "242220")
        static let bgSurface = Color(hex: "2a2826")
        static let bgHover = Color(hex: "322f2d")
        static let bgActive = Color(hex: "3a3533")

        // Text hierarchy
        static let textPrimary = Color(hex: "fafaf9")
        static let textSecondary = Color(hex: "d6d3d1")
        static let textTertiary = Color(hex: "78716c")

        // Primary Accent - Warm Amber (the soul of CrateBot)
        static let accentPrimary = Color(hex: "f59e0b")
        static let accentLight = Color(hex: "fbbf24")
        static let accentDark = Color(hex: "d97706")

        // Secondary Accent - Electric Violet (creative energy)
        static let accentSecondary = Color(hex: "8b5cf6")
        static let accentSecondaryLight = Color(hex: "a78bfa")

        // Status
        static let statusSuccess = Color(hex: "10b981")
        static let statusWarning = Color(hex: "f59e0b")
        static let statusError = Color(hex: "ef4444")

        // Category colors (for tags)
        static let categoryGenre = Color(hex: "a78bfa")      // Violet
        static let categoryTiming = Color(hex: "f59e0b")     // Amber
        static let categoryMood = Color(hex: "f472b6")       // Pink
        static let categoryDescriptive = Color(hex: "10b981") // Emerald
    }

    // MARK: - Shadows & Glows

    struct Shadows {
        // Elevation shadows
        static func elevation(_ level: Int) -> Color {
            Color.black.opacity(Double(level) * 0.05)
        }

        // Brand glows - evoke VU meters and analog warmth
        static let glowAmber = Color(hex: "f59e0b")
        static let glowAmberIntense = Color(hex: "fbbf24")
        static let glowViolet = Color(hex: "8b5cf6")
    }

    // MARK: - Typography

    struct Fonts {
        // Satoshi for display, General Sans for body (from design system)
        // Falls back to DM Sans which is similar
        static let display = "Satoshi"
        static let body = "General Sans"
        static let mono = "JetBrains Mono"

        static func heading(_ size: CGFloat = 18) -> Font {
            // Try Satoshi first, fall back to system
            .custom(display, size: size).weight(.semibold)
        }

        static func body(_ size: CGFloat = 13) -> Font {
            .custom(body, size: size)
        }

        static func label(_ size: CGFloat = 11) -> Font {
            .custom(body, size: size).weight(.medium)
        }

        static func mono(_ size: CGFloat = 13) -> Font {
            .custom(mono, size: size)
        }

        static func display(_ size: CGFloat = 24) -> Font {
            .custom(display, size: size).weight(.bold)
        }

        // System font fallbacks
        static func headingSystem(_ size: CGFloat = 18) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        static func bodySystem(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        static func labelSystem(_ size: CGFloat = 11) -> Font {
            .system(size: size, weight: .medium, design: .default)
        }

        static func monoSystem(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    // MARK: - Spacing (Base unit: 4px)

    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radius

    struct Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let full: CGFloat = 9999
    }

    // MARK: - Animation

    struct Animation {
        static let fast: Double = 0.15
        static let standard: Double = 0.2
        static let medium: Double = 0.3
        static let slow: Double = 0.4

        static var smooth: SwiftUI.Animation {
            .timingCurve(0.4, 0, 0.2, 1, duration: standard)
        }

        static var bounce: SwiftUI.Animation {
            .timingCurve(0.68, -0.55, 0.265, 1.55, duration: medium)
        }

        static var snap: SwiftUI.Animation {
            .timingCurve(0, 0, 0.2, 1, duration: fast)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.accentLight, Theme.Colors.accentPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .foregroundColor(Theme.Colors.bgBase)
            .cornerRadius(Theme.Radius.sm)
            .shadow(
                color: isHovered ? Theme.Shadows.glowAmber.opacity(0.5) : .clear,
                radius: isHovered ? 12 : 0
            )
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .offset(y: isHovered ? -1 : 0)
            .animation(Theme.Animation.snap, value: isHovered)
            .animation(Theme.Animation.snap, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isHovered ? Theme.Colors.bgHover : Theme.Colors.bgElevated)
            .foregroundColor(isHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .cornerRadius(Theme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(
                        isHovered ? Theme.Colors.accentPrimary.opacity(0.5) : Theme.Colors.textTertiary.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .shadow(color: isHovered ? .black.opacity(0.1) : .clear, radius: 4, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.snap, value: isHovered)
            .animation(Theme.Animation.snap, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct DangerButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isHovered ? Theme.Colors.statusError.opacity(0.25) : Theme.Colors.statusError.opacity(0.15))
            .foregroundColor(Theme.Colors.statusError)
            .cornerRadius(Theme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(
                        isHovered ? Theme.Colors.statusError.opacity(0.6) : Theme.Colors.statusError.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isHovered ? Theme.Colors.statusError.opacity(0.3) : .clear,
                radius: isHovered ? 8 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.snap, value: isHovered)
            .animation(Theme.Animation.snap, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct DisabledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.bgSurface)
            .foregroundColor(Theme.Colors.textTertiary)
            .cornerRadius(Theme.Radius.sm)
    }
}

struct GhostButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isHovered ? Theme.Colors.bgHover : .clear)
            .foregroundColor(isHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .cornerRadius(Theme.Radius.sm)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.snap, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Type-erasing button style wrapper
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

// MARK: - Vinyl Logo (Spins during processing)

struct VinylLogo: View {
    var isProcessing: Bool = false
    var size: CGFloat = 28

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Outer disc with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.Colors.accentLight, Theme.Colors.accentPrimary, Theme.Colors.accentDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Inner grooves (subtle rings)
            Circle()
                .strokeBorder(Theme.Colors.accentDark.opacity(0.3), lineWidth: 1)
                .frame(width: size * 0.7, height: size * 0.7)

            Circle()
                .strokeBorder(Theme.Colors.accentDark.opacity(0.2), lineWidth: 0.5)
                .frame(width: size * 0.5, height: size * 0.5)

            // Center label
            Circle()
                .fill(Theme.Colors.bgBase)
                .frame(width: size * 0.25, height: size * 0.25)
        }
        .shadow(color: Theme.Shadows.glowAmber.opacity(isProcessing ? 0.6 : 0.3), radius: isProcessing ? 12 : 6)
        .rotationEffect(.degrees(rotation))
        .onChange(of: isProcessing) { _, processing in
            if processing {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    rotation = 0
                }
            }
        }
    }
}

// MARK: - CrateBot Logo

struct CrateBotLogo: View {
    var isProcessing: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VinylLogo(isProcessing: isProcessing, size: 28)

            HStack(spacing: 0) {
                Text("Crate")
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Bot")
                    .foregroundColor(Theme.Colors.accentPrimary)
            }
            .font(Theme.Fonts.heading(20))
        }
    }
}

// MARK: - LED Status Indicator

struct StatusLED: View {
    enum Status {
        case complete, processing, pending, error
    }

    let status: Status
    var size: CGFloat = 8
    @State private var isPulsing = false

    var color: Color {
        switch status {
        case .complete: return Theme.Colors.statusSuccess
        case .processing: return Theme.Colors.accentPrimary
        case .pending: return Theme.Colors.textTertiary
        case .error: return Theme.Colors.statusError
        }
    }

    var glowColor: Color {
        switch status {
        case .complete: return Theme.Colors.statusSuccess
        case .processing: return Theme.Shadows.glowAmber
        case .pending: return .clear
        case .error: return Theme.Colors.statusError
        }
    }

    var body: some View {
        Group {
            if status == .pending {
                // Subtle dash for pending
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.textTertiary.opacity(0.4))
                    .frame(width: size, height: 3)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .shadow(color: glowColor.opacity(status == .processing ? (isPulsing ? 0.8 : 0.4) : 0.5), radius: status == .processing ? 8 : 4)
                    .scaleEffect(status == .processing && isPulsing ? 1.1 : 1.0)
                    .animation(
                        status == .processing
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                    .onAppear {
                        if status == .processing {
                            isPulsing = true
                        }
                    }
                    .onChange(of: status) { _, newStatus in
                        isPulsing = newStatus == .processing
                    }
            }
        }
    }
}

// MARK: - Pipeline Stepper

struct PipelineStepper: View {
    let steps: [String]
    let currentStep: Int // 0-indexed

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 6) {
                    // Step indicator
                    ZStack {
                        Circle()
                            .fill(stepColor(for: index))
                            .frame(width: 24, height: 24)

                        if index < currentStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.Colors.bgBase)
                        } else {
                            Text("\(index + 1)")
                                .font(Theme.Fonts.label(11))
                                .foregroundColor(index == currentStep ? Theme.Colors.bgBase : Theme.Colors.textTertiary)
                        }
                    }

                    Text(label)
                        .font(Theme.Fonts.label(12))
                        .foregroundColor(stepLabelColor(for: index))
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < currentStep ? Theme.Colors.statusSuccess : Theme.Colors.textTertiary.opacity(0.3))
                        .frame(width: 40, height: 2)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.md)
    }

    func stepColor(for index: Int) -> Color {
        if index < currentStep { return Theme.Colors.statusSuccess }
        if index == currentStep { return Theme.Colors.statusWarning }
        return Color.clear
    }

    func stepLabelColor(for index: Int) -> Color {
        if index < currentStep { return Theme.Colors.statusSuccess }
        if index == currentStep { return Theme.Colors.statusWarning }
        return Theme.Colors.textTertiary
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let label: String
    let value: String
    var detail: String? = nil
    var isHighlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label.uppercased())
                .font(Theme.Fonts.label(11))
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(0.5)

            Text(value)
                .font(Theme.Fonts.mono(24))
                .fontWeight(.semibold)
                .foregroundColor(isHighlighted ? Theme.Colors.accentPrimary : Theme.Colors.textPrimary)

            if let detail = detail {
                Text(detail)
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHighlighted
                ? LinearGradient(
                    colors: [
                        Theme.Colors.accentPrimary.opacity(0.1),
                        Theme.Colors.statusWarning.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(colors: [Theme.Colors.bgSurface], startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(Theme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(
                    isHighlighted ? Theme.Colors.accentPrimary.opacity(0.3) : Theme.Colors.textTertiary.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - File Row

struct ThemedFileRow: View {
    let filename: String
    let artist: String?
    let duration: String?
    let status: StatusLED.Status
    let time: String?
    var errorMessage: String? = nil

    var statusLabel: String {
        switch status {
        case .complete: return "Complete"
        case .processing: return "Processing"
        case .pending: return "Pending"
        case .error: return "Error"
        }
    }

    var statusColor: Color {
        switch status {
        case .complete: return Theme.Colors.statusSuccess
        case .processing: return Theme.Colors.statusWarning
        case .pending: return Theme.Colors.textTertiary
        case .error: return Theme.Colors.statusError
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatusLED(status: status, size: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(Theme.Fonts.mono(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if let error = errorMessage {
                    Text(error)
                        .font(Theme.Fonts.body(11))
                        .foregroundColor(Theme.Colors.statusError)
                } else if let artist = artist {
                    Text("\(artist) \(duration ?? "")")
                        .font(Theme.Fonts.body(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            Text(statusLabel)
                .font(Theme.Fonts.label(11))
                .foregroundColor(statusColor)
                .textCase(.uppercase)

            Text(time ?? "")
                .font(Theme.Fonts.mono(11))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(status == .processing ? Theme.Colors.statusWarning.opacity(0.08) : Color.clear)
    }
}

// MARK: - Themed Section Header

struct ThemedSectionHeader: View {
    let title: String
    var count: Int? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.label(13))
                .foregroundColor(Theme.Colors.textPrimary)

            if let count = count {
                Text("\(count) total")
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            if let trailing = trailing {
                trailing
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.bgElevated)
    }
}

// MARK: - Category Tag Chip

struct CategoryTagChip: View {
    enum Category {
        case genre, timing, mood, descriptive

        var color: Color {
            switch self {
            case .genre: return Theme.Colors.categoryGenre
            case .timing: return Theme.Colors.categoryTiming
            case .mood: return Theme.Colors.categoryMood
            case .descriptive: return Theme.Colors.categoryDescriptive
            }
        }
    }

    let tag: String
    let category: Category
    var confidence: Float? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(Theme.Fonts.label(12))
                .foregroundColor(Theme.Colors.textPrimary)

            if let confidence = confidence {
                Text("\(Int(confidence * 100))%")
                    .font(Theme.Fonts.label(10))
                    .foregroundColor(confidenceColor(confidence))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(confidenceColor(confidence).opacity(0.15))
                    .cornerRadius(4)
            }

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(category.color.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(category.color.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(Theme.Radius.sm)
    }

    func confidenceColor(_ value: Float) -> Color {
        if value >= 0.8 { return Theme.Colors.statusSuccess }
        if value >= 0.5 { return Theme.Colors.statusWarning }
        return Theme.Colors.statusError
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.3),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.5)
            .offset(x: phase * geo.size.width)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
        }
        .clipped()
    }
}

// MARK: - Themed Progress Bar

struct ThemedProgressBar: View {
    let progress: Double
    var isAnimating: Bool = false
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.Colors.bgElevated)

                // Progress bar
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.accentLight, Theme.Colors.accentPrimary, Theme.Colors.accentDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * CGFloat(progress), height))
                    .shadow(color: Theme.Shadows.glowAmber.opacity(0.4), radius: 4)
                    .overlay {
                        // Shimmer effect when animating
                        if isAnimating && progress > 0 && progress < 1 {
                            ShimmerEffect()
                                .cornerRadius(height / 2)
                        }
                    }
            }
        }
        .frame(height: height)
    }
}

// MARK: - LED VU Meter Progress Bar

/// A VU meter style progress bar with green/red LED segments
struct LEDProgressBar: View {
    let progress: Double
    var isAnimating: Bool = false
    var segmentCount: Int = 20
    var height: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { segment in
                let segmentProgress = Double(segment) / Double(segmentCount)
                let isLit = progress > segmentProgress

                RoundedRectangle(cornerRadius: 1)
                    .fill(segmentColor(for: segment, isLit: isLit))
                    .frame(height: height)
                    .shadow(
                        color: isLit ? segmentGlowColor(for: segment).opacity(0.6) : .clear,
                        radius: isLit ? 3 : 0
                    )
                    .opacity(isLit ? 1.0 : 0.3)
            }
        }
    }

    /// Get the color for a segment based on its position (green -> yellow -> red)
    private func segmentColor(for segment: Int, isLit: Bool) -> Color {
        let position = Double(segment) / Double(segmentCount)

        if position < 0.6 {
            // Green zone (0-60%)
            return isLit ? Theme.Colors.statusSuccess : Theme.Colors.statusSuccess.opacity(0.2)
        } else if position < 0.8 {
            // Yellow/amber zone (60-80%)
            return isLit ? Theme.Colors.statusWarning : Theme.Colors.statusWarning.opacity(0.2)
        } else {
            // Red zone (80-100%)
            return isLit ? Theme.Colors.statusError : Theme.Colors.statusError.opacity(0.2)
        }
    }

    /// Get the glow color for a segment
    private func segmentGlowColor(for segment: Int) -> Color {
        let position = Double(segment) / Double(segmentCount)

        if position < 0.6 {
            return Theme.Colors.statusSuccess
        } else if position < 0.8 {
            return Theme.Colors.statusWarning
        } else {
            return Theme.Colors.statusError
        }
    }
}

// MARK: - Noise Texture Overlay

struct NoiseOverlay: View {
    var opacity: Double = 0.03

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                // Generate noise pattern
                for x in stride(from: 0, to: size.width, by: 2) {
                    for y in stride(from: 0, to: size.height, by: 2) {
                        let brightness = Double.random(in: 0...1)
                        context.fill(
                            Path(CGRect(x: x, y: y, width: 2, height: 2)),
                            with: .color(.white.opacity(brightness * opacity))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
    }
}

// MARK: - Themed Card

struct ThemedCard<Content: View>: View {
    var accentColor: Color? = nil
    var isInteractive: Bool = false
    @State private var isHovered = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            content()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.lg)
        .overlay(
            VStack {
                if let accent = accentColor {
                    LinearGradient(
                        colors: [accent, Theme.Colors.accentPrimary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 3)
                    Spacer()
                }
            }
            .cornerRadius(Theme.Radius.lg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(
                    isHovered ? Theme.Colors.accentPrimary.opacity(0.3) : Theme.Colors.textTertiary.opacity(0.1),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.1), radius: isHovered ? 12 : 6, y: isHovered ? 4 : 2)
        .offset(y: isInteractive && isHovered ? -2 : 0)
        .animation(Theme.Animation.smooth, value: isHovered)
        .onHover { hover in
            if isInteractive { isHovered = hover }
        }
    }
}

// MARK: - Card Header with Icon

struct CardHeader: View {
    let icon: String
    let title: String
    var iconColor: Color = Theme.Colors.accentPrimary

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(Theme.Fonts.heading(16))
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Entrance Animation Modifier

struct SlideUpAnimation: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .animation(
                .timingCurve(0.4, 0, 0.2, 1, duration: 0.4).delay(delay),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}

struct FadeInAnimation: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(
                .easeOut(duration: 0.3).delay(delay),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}

struct ScaleInAnimation: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .animation(
                .timingCurve(0.4, 0, 0.2, 1, duration: 0.3).delay(delay),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}

extension View {
    func slideUpAnimation(delay: Double = 0) -> some View {
        modifier(SlideUpAnimation(delay: delay))
    }

    func fadeInAnimation(delay: Double = 0) -> some View {
        modifier(FadeInAnimation(delay: delay))
    }

    func scaleInAnimation(delay: Double = 0) -> some View {
        modifier(ScaleInAnimation(delay: delay))
    }
}

// MARK: - VU Meter Stat (Studio Equipment Style)

struct VUMeterStat: View {
    let label: String
    let value: String
    var progress: Double? = nil
    var color: Color = Theme.Colors.accentPrimary
    var isHighlighted: Bool = false
    var showMeter: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            Text(label)
                .font(Theme.Fonts.mono(9))
                .fontWeight(.medium)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(0.5)

            // Value display (LED style)
            Text(value)
                .font(Theme.Fonts.mono(16))
                .fontWeight(.bold)
                .foregroundColor(isHighlighted ? color : Theme.Colors.textPrimary)
                .shadow(color: isHighlighted ? color.opacity(0.5) : .clear, radius: 4)

            // Mini VU meter bar (always present for consistent height)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track with segments
                    HStack(spacing: 1) {
                        ForEach(0..<8, id: \.self) { _ in
                            Rectangle()
                                .fill(Theme.Colors.bgBase)
                                .frame(height: 4)
                        }
                    }

                    // Fill (only if showMeter is true and progress provided)
                    if showMeter, let progress = progress {
                        HStack(spacing: 1) {
                            ForEach(0..<8, id: \.self) { segment in
                                let segmentThreshold = Double(segment) / 8.0
                                Rectangle()
                                    .fill(progress > segmentThreshold ? segmentColor(segment: segment, baseColor: color) : Color.clear)
                                    .frame(height: 4)
                            }
                        }
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Colors.bgBase)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(isHighlighted ? color.opacity(0.3) : Theme.Colors.textTertiary.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // VU meter color gradient (green -> yellow -> red at peaks)
    private func segmentColor(segment: Int, baseColor: Color) -> Color {
        if segment < 5 {
            return baseColor
        } else if segment < 7 {
            return Theme.Colors.statusWarning
        } else {
            return Theme.Colors.statusError
        }
    }
}

// MARK: - Previews

#Preview("Theme Components") {
    ScrollView {
        VStack(spacing: 24) {
            // Logo
            HStack(spacing: 24) {
                CrateBotLogo(isProcessing: false)
                CrateBotLogo(isProcessing: true)
            }
            .slideUpAnimation()

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Status LEDs
            HStack(spacing: 20) {
                VStack {
                    StatusLED(status: .complete, size: 12)
                    Text("Done").font(Theme.Fonts.label(10)).foregroundColor(Theme.Colors.textTertiary)
                }
                VStack {
                    StatusLED(status: .processing, size: 12)
                    Text("Active").font(Theme.Fonts.label(10)).foregroundColor(Theme.Colors.textTertiary)
                }
                VStack {
                    StatusLED(status: .pending, size: 12)
                    Text("Pending").font(Theme.Fonts.label(10)).foregroundColor(Theme.Colors.textTertiary)
                }
                VStack {
                    StatusLED(status: .error, size: 12)
                    Text("Error").font(Theme.Fonts.label(10)).foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .slideUpAnimation(delay: 0.05)

            // Pipeline Stepper
            PipelineStepper(
                steps: ["Select", "Extract", "Train", "Validate"],
                currentStep: 1
            )
            .slideUpAnimation(delay: 0.1)

            // Stat Cards
            HStack(spacing: 12) {
                StatCard(label: "Files", value: "142", detail: "10 remaining")
                StatCard(label: "ETA", value: "5m 23s", detail: "at current rate", isHighlighted: true)
            }
            .slideUpAnimation(delay: 0.15)

            // Category Tags
            HStack(spacing: 8) {
                CategoryTagChip(tag: "House", category: .genre, confidence: 0.92)
                CategoryTagChip(tag: "Peak", category: .timing)
                CategoryTagChip(tag: "Energetic", category: .mood, confidence: 0.78, onRemove: {})
                CategoryTagChip(tag: "Vocal", category: .descriptive)
            }
            .slideUpAnimation(delay: 0.2)

            // Progress Bars
            VStack(spacing: 12) {
                ThemedProgressBar(progress: 0.65, isAnimating: false)
                ThemedProgressBar(progress: 0.45, isAnimating: true)
            }
            .slideUpAnimation(delay: 0.25)

            // Buttons
            HStack(spacing: 12) {
                Button("Primary") {}
                    .buttonStyle(PrimaryButtonStyle())
                Button("Secondary") {}
                    .buttonStyle(SecondaryButtonStyle())
                Button("Danger") {}
                    .buttonStyle(DangerButtonStyle())
                Button("Ghost") {}
                    .buttonStyle(GhostButtonStyle())
            }
            .slideUpAnimation(delay: 0.3)

            // Card with header
            ThemedCard(accentColor: Theme.Colors.accentPrimary, isInteractive: true) {
                CardHeader(icon: "music.note.list", title: "Tagged Files")
                Text("Hover over this card to see the interactive effect")
                    .font(Theme.Fonts.body(13))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .slideUpAnimation(delay: 0.35)
        }
        .padding(24)
    }
    .frame(width: 500, height: 700)
    .background(Theme.Colors.bgWindow)
    .overlay(NoiseOverlay())
}
