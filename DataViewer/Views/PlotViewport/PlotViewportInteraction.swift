import SwiftUI

private struct PlotViewportInteractionModifier: ViewModifier {
    let target: PlotViewportTarget
    @Bindable var viewModel: DataViewModel
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                        .overlay {
                            if isEnabled {
                                PlotViewportUIKitGestureRepresentable(
                                    target: target,
                                    viewModel: viewModel,
                                    isEnabled: isEnabled
                                )
                            }
                        }
                }
            }
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
