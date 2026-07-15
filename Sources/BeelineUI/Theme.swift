import SwiftUI

public extension Color {
    /// Georgia Tech gold, darkened enough to hold contrast on white.
    static let beelineGold = Color(red: 0.70, green: 0.61, blue: 0.29)
    static let beelineNavy = Color(red: 0.12, green: 0.23, blue: 0.37)
    static let beelineRoute = Color(red: 0.18, green: 0.45, blue: 0.90)
    static let beelineWalk = Color(red: 0.20, green: 0.62, blue: 0.45)

    static var cardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var groupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
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

/// Hex colors arrive from the bus feed as "#ff0000".
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
