import SwiftUI

enum ContentSurfaceKind: Sendable {
    case chromeBar
    case chartContainer
    case timelineDock
    case editingPanel
}

struct ContentSurfaceModifier: ViewModifier {
    let kind: ContentSurfaceKind

    func body(content: Content) -> some View {
        switch kind {
        case .chromeBar, .timelineDock:
            content
                .background { chromeBarBackground }
                .overlay(alignment: .bottom) { ContentSectionSeparator() }
        case .chartContainer:
            let shape = RoundedRectangle(cornerRadius: Constants.chartCornerRadius, style: .continuous)
            content
                .background {
                    shape.fill(LiquidGlassStyleResolver.platformChartBackground())
                }
                .clipShape(shape)
        case .editingPanel:
            let shape = RoundedRectangle(cornerRadius: Constants.cornerRadius, style: .continuous)
            content
                .background {
                    shape.fill(LiquidGlassStyleResolver.editingBackgroundStyle)
                }
                .clipShape(shape)
        }
    }

    @ViewBuilder
    private var chromeBarBackground: some View {
        switch kind {
        case .timelineDock:
            Rectangle().fill(.regularMaterial)
        case .chromeBar:
            LiquidGlassStyleResolver.platformChromeColor
        default:
            EmptyView()
        }
    }
}

struct ContentSectionSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

extension View {
    func contentSurface(_ kind: ContentSurfaceKind) -> some View {
        modifier(ContentSurfaceModifier(kind: kind))
    }
}

struct LiquidGlassProminentShapeBackground<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        if #available(iOS 26.0, *), LiquidGlassStyleResolver.supportsLiquidGlass {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(Color.accentColor), in: shape)
        } else {
            shape
                .fill(Color.accentColor)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

extension View {
    @ViewBuilder
    func contentAnnotationBackground<S: InsettableShape>(_ shape: S) -> some View {
        background {
            shape.fill(.ultraThinMaterial)
        }
    }

    func liquidGlassFloatingPanel(
        cornerRadius: CGFloat = Constants.cornerRadius,
        extendsIntoSafeArea edges: Edge.Set = []
    ) -> some View {
        modifier(
            LiquidGlassFloatingPanelModifier(
                cornerRadius: cornerRadius,
                extendsIntoSafeArea: edges
            )
        )
    }

    func liquidGlassToolbarBackground() -> some View {
        background {
            Group {
                if #available(iOS 26.0, *) {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: Rectangle())
                } else {
                    Rectangle()
                        .fill(.bar)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct LiquidGlassFloatingPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var extendsIntoSafeArea: Edge.Set

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background { panelBackground(shape: shape) }
            .clipShape(shape)
    }

    @ViewBuilder
    private func panelBackground(shape: RoundedRectangle) -> some View {
        if extendsIntoSafeArea.isEmpty {
            glassOrMaterialFill(in: shape)
        } else {
            glassOrMaterialFill(in: shape)
                .ignoresSafeArea(edges: extendsIntoSafeArea)
        }
    }

    @ViewBuilder
    private func glassOrMaterialFill<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}
