import SwiftUI
import UIKit

/// Small design-token set shared by every screen. Colors use system palettes so light/dark
/// and increased-contrast modes adapt automatically; typography only uses semantic text styles
/// so Dynamic Type keeps working.
enum HimatchColor {
    static let accent = Color(uiColor: .systemIndigo)
    static let availability = Color(uiColor: .systemIndigo)
    static let plan = Color(uiColor: .systemGreen)
    static let hosting = Color(uiColor: .systemOrange)
    static let attention = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)
    static let separator = Color(uiColor: .separator)
    static let gridLine = Color(uiColor: .separator).opacity(0.6)
    static let unavailable = Color(uiColor: .tertiarySystemFill)
    static let secondaryText = Color(uiColor: .secondaryLabel)

    static func tint(_ color: Color) -> Color { color.opacity(0.14) }
}

enum HimatchSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

enum HimatchRadius {
    static let card: CGFloat = 16
    static let control: CGFloat = 12
    static let block: CGFloat = 8
}

enum HimatchMetrics {
    /// Apple HIG minimum hit target.
    static let minTapTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 50
}

enum HimatchFont {
    static let screenTitle = Font.largeTitle.weight(.bold)
    static let hero = Font.title.weight(.bold)
    static let sectionTitle = Font.title3.weight(.semibold)
    static let cardTitle = Font.headline
    static let body = Font.body
    static let supporting = Font.subheadline
    static let caption = Font.caption
    static let emphasizedValue = Font.title3.weight(.semibold).monospacedDigit()
}
