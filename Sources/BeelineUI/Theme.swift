import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Colors that adapt the way Apple's own do.
///
/// A fixed navy reads well on white and disappears on black, so every brand
/// colour here has a dark-mode counterpart. Semantic greys come from the
/// system so they track Increase Contrast and the rest of the accessibility
/// settings for free.
public extension Color {

    /// The primary accent: Georgia Tech navy in light, lifted for dark so it
    /// still reads as a tappable colour on black.
    static let beelineNavy = adaptive(
        light: (0.12, 0.23, 0.37),
        dark: (0.45, 0.65, 0.95)
    )

    /// Georgia Tech gold, darkened in light mode to hold contrast on white.
    static let beelineGold = adaptive(
        light: (0.62, 0.53, 0.22),
        dark: (0.85, 0.74, 0.40)
    )

    /// The drawn route.
    static let beelineRoute = adaptive(
        light: (0.10, 0.42, 0.90),
        dark: (0.40, 0.64, 1.00)
    )

    /// Walking time and "free" states.
    static let beelineWalk = adaptive(
        light: (0.13, 0.52, 0.36),
        dark: (0.35, 0.80, 0.56)
    )

    static var cardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// The body of a map pin or marker: paper-white in light, near-black in
    /// dark, matching what Apple Maps does with its own annotations.
    static var markerBody: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }

    static var groupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// A colour that resolves per trait collection on iOS, and falls back to
    /// the light value elsewhere.
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func searchKeyboard() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
}

/// Hex colors arrive from the bus feed as "#ff0000". Route colours are the
/// route's identity, so they are deliberately *not* adapted — a red line is
/// the Red route in either theme.
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
