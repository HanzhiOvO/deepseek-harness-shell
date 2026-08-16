import SwiftUI
import DeepSeekHarnessCore

/// DeepSeek Harness Shell 设计系统：颜色、渐变、品牌组件统一在此维护。
enum Theme {
    // MARK: - 品牌色
    static let accent = Color(red: 0.20, green: 0.43, blue: 1.00)
    static let accentDeep = Color(red: 0.07, green: 0.13, blue: 0.45)
    static let accentSoft = Color(red: 0.88, green: 0.92, blue: 1.00)
    static let success = Color(red: 0.12, green: 0.68, blue: 0.42)
    static let warning = Color(red: 0.95, green: 0.60, blue: 0.10)
    static let danger = Color(red: 0.88, green: 0.28, blue: 0.28)

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.35, green: 0.55, blue: 1.00),
            accentDeep
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softAccentGradient = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.96, blue: 1.00),
            Color(red: 0.85, green: 0.90, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let bannerGradient = softAccentGradient

    // MARK: - 表面与描边
    static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    static var cardStroke: Color {
        Color.primary.opacity(0.06)
    }

    static var cardStrokeStrong: Color {
        Color.primary.opacity(0.13)
    }

    static var hairline: Color {
        Color.primary.opacity(0.07)
    }
}

extension Color {
    static let dshAccent = Theme.accent
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 应用品牌图标：DeepSeek 蓝渐变圆角方块 + 终端符号。
struct BrandMark: View {
    var size: CGFloat = 44
    var cornerRadius: CGFloat? = nil
    var systemImage: String = "terminal.fill"
    var imageFont: Font? = nil

    var body: some View {
        let radius = cornerRadius ?? size * 0.28
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.accentGradient)
                .shadow(color: Theme.accentDeep.opacity(0.25), radius: size * 0.12, y: size * 0.08)

            Image(systemName: systemImage)
                .font(imageFont ?? .system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("DeepSeek Harness Shell")
    }
}

/// 小徽章：图标 + 文字 + 色彩，全应用通用。
struct TintBadge: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}
