import SwiftUI

enum LiquidGlassButtonRole: String, CaseIterable, Sendable {
    case primary
    case secondary
    case toolbar
    case inline
    case destructive
}

enum LiquidGlassResolvedButtonStyle: String, Equatable, Sendable {
    case glassProminent
    case glass
    case borderedProminent
    case bordered
    case plain
}

enum LiquidGlassStyleResolver {
    static var supportsLiquidGlass: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    static func resolvedButtonStyle(for role: LiquidGlassButtonRole) -> LiquidGlassResolvedButtonStyle {
        guard supportsLiquidGlass else {
            return legacyButtonStyle(for: role)
        }
        switch role {
        case .primary, .destructive:
            return .glassProminent
        case .secondary, .toolbar:
            return .glass
        case .inline:
            return .plain
        }
    }

    static func legacyButtonStyle(for role: LiquidGlassButtonRole) -> LiquidGlassResolvedButtonStyle {
        switch role {
        case .primary, .destructive:
            return .borderedProminent
        case .secondary, .toolbar:
            return .bordered
        case .inline:
            return .plain
        }
    }

    static var platformChromeColor: Color {
        Color(.secondarySystemBackground)
    }

    static func platformChartBackground() -> Color {
        Color(.secondarySystemBackground)
    }

    static func platformSidebarBackground() -> Color {
        Color(.systemGroupedBackground)
    }

    static var editingBackgroundStyle: some ShapeStyle {
        Constants.editingBackgroundStyle
    }
}
