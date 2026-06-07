import SwiftUI

enum SublyColor {
    #if canImport(UIKit)
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    #else
    static let background = Color.gray.opacity(0.08)
    static let surface = Color.gray.opacity(0.14)
    #endif
    static let accent = Color.indigo
    static let warning = Color.orange
    static let danger = Color.red
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
