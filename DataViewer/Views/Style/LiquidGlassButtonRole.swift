import SwiftUI

enum LiquidGlassControlSize {
    case regular
    case compact
}

struct LiquidGlassButtonRoleModifier: ViewModifier {
    let role: LiquidGlassButtonRole

    @ViewBuilder
    func body(content: Content) -> some View {
        if LiquidGlassStyleResolver.supportsLiquidGlass {
            switch LiquidGlassStyleResolver.resolvedButtonStyle(for: role) {
            case .glassProminent:
                content.buttonStyle(.glassProminent)
            case .glass:
                content.buttonStyle(.glass)
            case .borderedProminent:
                content.buttonStyle(.borderedProminent)
            case .bordered:
                content.buttonStyle(.bordered)
            case .plain:
                content.buttonStyle(.plain)
            }
        } else {
            switch LiquidGlassStyleResolver.legacyButtonStyle(for: role) {
            case .borderedProminent:
                content.buttonStyle(.borderedProminent)
            case .bordered:
                content.buttonStyle(.bordered)
            case .plain:
                content.buttonStyle(.plain)
            case .glassProminent, .glass:
                content.buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    func liquidGlassButtonRole(_ role: LiquidGlassButtonRole) -> some View {
        modifier(LiquidGlassButtonRoleModifier(role: role))
    }

    @ViewBuilder
    func glassControl(
        _ role: LiquidGlassButtonRole,
        size: LiquidGlassControlSize = .regular,
        touchTarget: Bool = true
    ) -> some View {
        let sized = Group {
            switch size {
            case .regular:
                self
            case .compact:
                self.controlSize(.small)
            }
        }
        .liquidGlassButtonRole(role)

        if touchTarget {
            sized.minimumTouchTarget()
        } else {
            sized
        }
    }
}

struct LiquidGlassButtonGroup<Content: View>: View {
    var spacing: CGFloat = Constants.controlSpacingTight
    @ViewBuilder var content: () -> Content

    var body: some View {
        if LiquidGlassStyleResolver.supportsLiquidGlass {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
