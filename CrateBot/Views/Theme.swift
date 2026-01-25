import SwiftUI

// MARK: - Theme Design System

struct Theme {
    // MARK: - Colors

    struct Colors {
        // Background hierarchy (darkest to lightest)
        static let bgBase = Color(hex: "0d0c0b")
        static let bgWindow = Color(hex: "1a1816")
        static let bgElevated = Color(hex: "242220")
        static let bgSurface = Color(hex: "2a2826")
        static let bgHover = Color(hex: "322f2d")
        static let bgActive = Color(hex: "3a3533")

        // Text hierarchy
        static let textPrimary = Color(hex: "f5f2ef")
        static let textSecondary = Color(hex: "a8a29e")
        static let textTertiary = Color(hex: "6b6560")

        // Accent
        static let accentPrimary = Color(hex: "5b9bd5")

        // Status
        static let statusSuccess = Color(hex: "7bc47f")
        static let statusWarning = Color(hex: "e5a54b")
        static let statusError = Color(hex: "d97373")

        // Category colors (for tags)
        static let categoryGenre = Color(hex: "a78bda")
        static let categoryTiming = Color(hex: "5b9bd5")
        static let categoryMood = Color(hex: "e5a54b")
        static let categoryDescriptive = Color(hex: "7bc47f")
    }

    // MARK: - Typography

    struct Fonts {
        static let display = "DM Sans"
        static let mono = "JetBrains Mono"

        static func heading(_ size: CGFloat = 18) -> Font {
            .custom(display, size: size).weight(.semibold)
        }

        static func body(_ size: CGFloat = 13) -> Font {
            .custom(display, size: size)
        }

        static func label(_ size: CGFloat = 11) -> Font {
            .custom(display, size: size).weight(.medium)
        }

        static func mono(_ size: CGFloat = 13) -> Font {
            .custom(mono, size: size)
        }

        // System font fallbacks (use these if custom fonts aren't installed)
        static func headingSystem(_ size: CGFloat = 18) -> Font {
            .system(size: size, weight: .semibold, design: .default)
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

    // MARK: - Spacing

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Radius

    struct Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.accentPrimary)
            .foregroundColor(Theme.Colors.bgBase)
            .cornerRadius(Theme.Radius.sm)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.bgElevated)
            .foregroundColor(Theme.Colors.textSecondary)
            .cornerRadius(Theme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.Colors.textTertiary.opacity(0.2), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.label(13))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.statusError.opacity(0.15))
            .foregroundColor(Theme.Colors.statusError)
            .cornerRadius(Theme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.Colors.statusError.opacity(0.3), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
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

// MARK: - LED Status Indicator

struct StatusLED: View {
    enum Status {
        case complete, processing, pending, error
    }

    let status: Status
    var size: CGFloat = 8

    var color: Color {
        switch status {
        case .complete: return Theme.Colors.statusSuccess
        case .processing: return Theme.Colors.statusWarning
        case .pending: return Theme.Colors.textTertiary
        case .error: return Theme.Colors.statusError
        }
    }

    var body: some View {
        Group {
            if status == .pending {
                // Use a dash for pending instead of an empty circle (avoids looking like a checkbox)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.textTertiary.opacity(0.4))
                    .frame(width: size, height: 3)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .shadow(color: color.opacity(0.5), radius: 4)
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

// MARK: - Themed Progress Bar

struct ThemedProgressBar: View {
    let progress: Double
    var showPercentage: Bool = true
    var height: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Colors.bgElevated)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.accentPrimary, Theme.Colors.statusWarning],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Themed Card

struct ThemedCard<Content: View>: View {
    var accentColor: Color? = nil
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
                .strokeBorder(Theme.Colors.textTertiary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Theme Components") {
    VStack(spacing: 20) {
        // Status LEDs
        HStack(spacing: 16) {
            StatusLED(status: .complete, size: 12)
            StatusLED(status: .processing, size: 12)
            StatusLED(status: .pending, size: 12)
            StatusLED(status: .error, size: 12)
        }

        // Pipeline Stepper
        PipelineStepper(
            steps: ["Select", "Extract", "Train", "Validate"],
            currentStep: 1
        )

        // Stat Cards
        HStack(spacing: 8) {
            StatCard(label: "Files", value: "142", detail: "10 remaining")
            StatCard(label: "ETA", value: "5m 23s", detail: "at current rate", isHighlighted: true)
        }

        // Category Tags
        HStack(spacing: 8) {
            CategoryTagChip(tag: "House", category: .genre, confidence: 0.92)
            CategoryTagChip(tag: "Fast", category: .timing)
            CategoryTagChip(tag: "Energetic", category: .mood, onRemove: {})
        }

        // Progress Bar
        ThemedProgressBar(progress: 0.65)

        // Buttons
        HStack(spacing: 12) {
            Button("Primary") {}
                .buttonStyle(PrimaryButtonStyle())
            Button("Secondary") {}
                .buttonStyle(SecondaryButtonStyle())
            Button("Danger") {}
                .buttonStyle(DangerButtonStyle())
        }
    }
    .padding(24)
    .background(Theme.Colors.bgWindow)
}
