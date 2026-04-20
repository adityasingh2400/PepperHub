import SwiftUI

// MARK: - Hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - UIColor hex init

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8)  & 0xFF) / 255
        let b = CGFloat(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Semantic adaptive colors
//
// Light palette: warm cream / off-white
// Dark palette:  warm charcoal (not cold blue-gray)

extension Color {

    // Surfaces
    static let appBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "1a1714")
            : UIColor(hex: "faf5f0")
    })

    static let appCard = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "252220")
            : UIColor.white
    })

    static let appCardElevated = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "2e2a27")
            : UIColor.white
    })

    // Borders & dividers
    static let appBorder = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "3d3530")
            : UIColor(hex: "e8ddd6")
    })

    static let appDivider = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "2d2926")
            : UIColor(hex: "f0ebe5")
    })

    // Text
    static let appTextPrimary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "f0ebe5")
            : UIColor(hex: "1c1c1e")
    })

    static let appTextSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "b8aca4")
            : UIColor(hex: "374151")
    })

    static let appTextTertiary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "8a7d75")
            : UIColor(hex: "6b7280")
    })

    static let appTextMeta = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "6e635c")
            : UIColor(hex: "9ca3af")
    })

    // Brand
    static let appAccent = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "e8294f")
            : UIColor(hex: "9f1239")
    })

    static let appAccentTint = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "2d1520")
            : UIColor(hex: "fce7ec")
    })

    // Input
    static let appInputBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "2d2926")
            : UIColor(hex: "f0ebe5")
    })
}
