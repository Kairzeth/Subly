import SwiftUI

enum SublyColor {
    #if canImport(UIKit)
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    #else
    static let background = Color.gray.opacity(0.08)
    static let surface = Color.gray.opacity(0.14)
    #endif
    static let accent = Color(red: 0.25, green: 0.42, blue: 0.96)
    static let accentDeep = Color(red: 0.12, green: 0.20, blue: 0.48)
    static let mint = Color(red: 0.12, green: 0.70, blue: 0.62)
    static let coral = Color(red: 0.94, green: 0.40, blue: 0.32)
    static let amber = Color(red: 0.96, green: 0.64, blue: 0.20)
    static let orchid = Color(red: 0.58, green: 0.35, blue: 0.93)
    static let sky = Color(red: 0.18, green: 0.63, blue: 0.91)
    static let slate = Color(red: 0.25, green: 0.29, blue: 0.38)
    static let warning = amber
    static let danger = coral

    static let chartPalette: [Color] = [
        accent,
        mint,
        coral,
        amber,
        orchid,
        sky,
        Color(red: 0.72, green: 0.38, blue: 0.56),
        Color(red: 0.34, green: 0.56, blue: 0.30)
    ]

    static func chartColor(at index: Int) -> Color {
        chartPalette[index % chartPalette.count]
    }
}

enum SublySpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

enum SublyCornerRadius {
    static let card: CGFloat = 8
}

struct CurrencyAmountText: View {
    var money: Money?
    var font: Font = .system(.title3, design: .rounded, weight: .semibold)

    var body: some View {
        Text(money?.formatted ?? "需要补充汇率")
            .font(font)
            .foregroundStyle(money == nil ? SublyColor.warning : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

struct StatusTagView: View {
    var status: SubscriptionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}

struct CategoryTagView: View {
    var name: String

    var body: some View {
        Label(name, systemImage: "tag")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct EmptyStateView: View {
    var title: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
    }
}
