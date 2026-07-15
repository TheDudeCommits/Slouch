import SwiftUI

enum SlouchColor {
    static let void = Color(red: 7 / 255, green: 11 / 255, blue: 24 / 255)
    static let deepNavy = Color(red: 16 / 255, green: 26 / 255, blue: 50 / 255)
    static let moonstone = Color(red: 200 / 255, green: 213 / 255, blue: 228 / 255)
    static let teal = Color(red: 94 / 255, green: 214 / 255, blue: 203 / 255)
    static let lavender = Color(red: 147 / 255, green: 136 / 255, blue: 232 / 255)
    static let solarGold = Color(red: 231 / 255, green: 185 / 255, blue: 106 / 255)
    static let danger = Color(red: 235 / 255, green: 116 / 255, blue: 105 / 255)
    static let glass = Color.white.opacity(0.085)
    static let glassStroke = Color.white.opacity(0.16)
}
enum SlouchSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 34
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24
    var tint: Color = SlouchColor.glass

    func body(content: Content) -> some View {
        content
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SlouchColor.glassStroke, lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24, tint: Color = SlouchColor.glass) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }

    func slouchTitle() -> some View {
        font(.system(size: 34, weight: .light, design: .rounded))
            .tracking(-0.6)
            .foregroundStyle(SlouchColor.moonstone)
    }
}

struct SpaceGradientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SlouchColor.void, SlouchColor.deepNavy, SlouchColor.void],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [SlouchColor.lavender.opacity(0.22), .clear],
                center: UnitPoint(x: 0.85, y: 0.12),
                startRadius: 8,
                endRadius: 280
            )

            RadialGradient(
                colors: [SlouchColor.teal.opacity(0.12), .clear],
                center: UnitPoint(x: 0.08, y: 0.72),
                startRadius: 8,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }
}
