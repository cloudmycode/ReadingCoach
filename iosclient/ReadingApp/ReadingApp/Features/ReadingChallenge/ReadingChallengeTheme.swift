import SwiftUI
import UIKit

/// Keep custom reward colors responsive to the same system appearance as the app.
/// Do not resolve the UIColor here: its provider must remain live when appearance changes.
enum ReadingChallengeTheme {
    static let canvas = color(0xF4F7FC, dark: 0x000000)
    static let ink = color(0x141B2E, dark: 0xEDF2FC)
    static let muted = color(0x64748B, dark: 0xA9B8CD)
    static let accent = color(0x0062FF, dark: 0x80B4FF)
    static let border = color(0xDFE7F2, dark: 0x303D50)
    static let softBlue = color(0xEDF5FF, dark: 0x1B2D46)
    static let softGold = color(0xFFF3DF, dark: 0x392F20)
    static let gold = color(0xFFBD00, dark: 0xFFD05C)
    static let heroGold = Color(red: 1, green: 0.84, blue: 0.22)
    static let pink = color(0xF46C89, dark: 0xFF8DA6)
    static let cyan = Color(red: 0, green: 0.90, blue: 1)
    static let onHeroSecondary = Color(red: 0.83, green: 0.89, blue: 1)
    static let track = color(0xE2E8F0, dark: 0x263144)
    static let heroGradient = LinearGradient(colors: [
        color(0x0065FF, dark: 0x0952D2),
        color(0x043DC5, dark: 0x0C2E8A)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    static func color(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1
            )
        })
    }
}

/// Match the toolbar to the page, independent of the content passing beneath it.
private struct ReadingRewardScrollAppearance: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .background(ReadingChallengeTheme.canvas.ignoresSafeArea())
            .toolbarBackground(ReadingChallengeTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
    }
}

extension View {
    func readingRewardScrollAppearance() -> some View {
        modifier(ReadingRewardScrollAppearance())
    }
}
