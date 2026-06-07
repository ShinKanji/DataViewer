import CoreGraphics
import Foundation

extension DataViewModel {
    func plotViewportVisibleRange(for target: PlotViewportTarget) -> VisibleTimeRange {
        switch target {
        case .mainPlot: visibleRange
        case .statistics: statisticsVisibleRange
        }
    }

    func plotViewportFullRange(for target: PlotViewportTarget) -> VisibleTimeRange {
        switch target {
        case .mainPlot: fullRange
        case .statistics: statisticsFullRange
        }
    }

    func applyPanGestureTranslation(
        target: PlotViewportTarget,
        deltaX: CGFloat,
        width: CGFloat,
        panScale: Double = PlotViewportConstants.scrollWheelPanScale
    ) {
        let visible = plotViewportVisibleRange(for: target)
        guard visible.length > 0 else { return }
        let deltaTime = panDeltaTime(
            deltaX: deltaX,
            width: width,
            visibleLength: visible.length,
            scale: panScale
        )
        guard deltaTime != 0 else { return }

        switch target {
        case .mainPlot:
            panVisibleRange(byDeltaTime: deltaTime)
            beginPlotViewportInteraction(for: .mainPlot)
        case .statistics:
            panStatisticsVisibleRange(byDeltaTime: deltaTime)
            beginPlotViewportInteraction(for: .statistics)
        }
    }

    func applyScrollWheelZoom(
        target: PlotViewportTarget,
        deltaX: CGFloat,
        anchorX: CGFloat,
        width: CGFloat
    ) {
        let visible = plotViewportVisibleRange(for: target)
        guard visible.length > 0 else { return }
        let anchor = plotViewportTime(atX: anchorX, width: width, range: visible)
        let factor = scrollWheelZoomFactor(deltaX: deltaX)
        applyPlotViewportZoom(target: target, factor: factor, anchor: anchor)
    }

    func applyMagnification(
        target: PlotViewportTarget,
        magnification: CGFloat,
        anchorX: CGFloat,
        width: CGFloat
    ) {
        guard magnification != 0 else { return }
        let visible = plotViewportVisibleRange(for: target)
        guard visible.length > 0 else { return }
        let anchor = plotViewportTime(atX: anchorX, width: width, range: visible)
        let factor = magnifyZoomFactor(magnification: magnification)
        applyPlotViewportZoom(target: target, factor: factor, anchor: anchor)
    }

    private func applyPlotViewportZoom(target: PlotViewportTarget, factor: Double, anchor: Double) {
        switch target {
        case .mainPlot:
            zoomVisibleRange(factor: factor, anchor: anchor)
            beginPlotViewportInteraction(for: .mainPlot)
        case .statistics:
            zoomStatisticsVisibleRange(factor: factor, anchor: anchor)
            beginPlotViewportInteraction(for: .statistics)
        }
    }
}
