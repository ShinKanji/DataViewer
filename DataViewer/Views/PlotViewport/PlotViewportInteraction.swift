import SwiftUI

private struct PlotViewportInteractionModifier: ViewModifier {
    let target: PlotViewportTarget
    @Bindable var viewModel: DataViewModel
    let isEnabled: Bool

    @State private var lastMagnification: CGFloat = 1.0
    @State private var contentWidth: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { newWidth in
                contentWidth = max(newWidth, 1)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard isEnabled else { return }
                        let delta = value - lastMagnification
                        lastMagnification = value
                        guard delta != 0 else { return }
                        let anchorX = contentWidth / 2
                        viewModel.applyMagnification(
                            target: target,
                            magnification: CGFloat(delta),
                            anchorX: anchorX,
                            width: contentWidth
                        )
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
    }
}

extension View {
    func plotViewportInteraction(
        target: PlotViewportTarget,
        viewModel: DataViewModel,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            PlotViewportInteractionModifier(
                target: target,
                viewModel: viewModel,
                isEnabled: isEnabled
            )
        )
    }
}
