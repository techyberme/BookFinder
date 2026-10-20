import SwiftUI
import UIKit

/// Editorial palette: slate neutrals, one accent (Madrid crimson, `brand-500` in the web app),
/// plus semantic green/amber for loan status. Every color has a dark-mode variant.
enum Palette {
    static let accent = dynamic(light: 0xC8102E, dark: 0xF0465E)
    static let ink = dynamic(light: 0x0F172A, dark: 0xF1F5F9)          // slate-900 / slate-100
    static let inkSecondary = dynamic(light: 0x475569, dark: 0xA3B1C6) // slate-600 / ~slate-400
    static let inkTertiary = dynamic(light: 0x64748B, dark: 0x8291A7)
    static let paper = dynamic(light: 0xFAFAF7, dark: 0x0B0F17)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x151B26)
    static let rule = dynamic(light: 0xE2E8F0, dark: 0x263041)         // slate-200
    static let chip = dynamic(light: 0xF1F5F9, dark: 0x1E2633)         // slate-100
    static let available = dynamic(light: 0x047857, dark: 0x34D399)    // emerald-700 / emerald-400
    static let availableBg = dynamic(light: 0xECFDF5, dark: 0x0F2A22)
    static let onLoan = dynamic(light: 0x92400E, dark: 0xFBBF24)       // amber-800 / amber-400
    static let onLoanBg = dynamic(light: 0xFFFBEB, dark: 0x2B2210)
    static let accentBg = dynamic(light: 0xFDF2F2, dark: 0x2A1216)     // brand-50

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Bundled fonts (see Info.plist `UIAppFonts`). Sizes scale with Dynamic Type via `relativeTo:`.
enum Typo {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title3) -> Font {
        let name: String
        switch weight {
        case .regular, .light, .thin, .ultraLight: name = "Fraunces-Regular"
        case .semibold, .medium: name = "Fraunces-SemiBold"
        default: name = "Fraunces-Bold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .medium: name = "PlusJakartaSans-Medium"
        case .semibold: name = "PlusJakartaSans-SemiBold"
        case .bold: name = "PlusJakartaSans-Bold"
        case .heavy, .black: name = "PlusJakartaSans-ExtraBold"
        default: name = "PlusJakartaSans-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-SemiBold", size: size, relativeTo: style)
    }
}

extension View {
    /// Small uppercase section label used across the editorial layout.
    func eyebrow() -> some View {
        font(Typo.sans(11, .bold, relativeTo: .caption2)).textCase(.uppercase).tracking(1.1)
            .foregroundStyle(Palette.inkSecondary)
    }

    func cardStyle() -> some View {
        background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule))
    }
}
