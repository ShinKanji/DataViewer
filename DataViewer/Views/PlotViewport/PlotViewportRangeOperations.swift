import Foundation

nonisolated enum PlotViewportConstants {
    static let scrollWheelPanScale: Double = 0.5
    static let touchPanScale: Double = 1.0
    static let scrollWheelZoomInFactor: Double = 0.92
    static let scrollWheelZoomOutFactor: Double = 1.08
}

nonisolated enum PlotViewportTarget: Equatable {
    case mainPlot
    case statistics
}

nonisolated enum PlotViewportRangeOperations {
    static func shiftedVisibleRange(
        current: VisibleTimeRange,
        full: VisibleTimeRange,
        deltaTime: Double
    ) -> VisibleTimeRange {
        var newStart = current.start + deltaTime
        var newEnd = current.end + deltaTime

        if newStart < full.start {
            newEnd += full.start - newStart
            newStart = full.start
        }
        if newEnd > full.end {
            newStart -= newEnd - full.end
            newEnd = full.end
        }

        return VisibleTimeRange(start: newStart, end: newEnd)
    }

    static func zoomedVisibleRange(
        current: VisibleTimeRange,
        full: VisibleTimeRange,
        factor: Double,
        anchor: Double?
    ) -> VisibleTimeRange? {
        guard factor > 0, full.length > 0, current.length > 0 else { return nil }

        let anchorTime = anchor ?? (current.start + current.end) / 2
        var newLength = current.length * factor
        newLength = max(0.1, min(newLength, full.length))

        let anchorRatio = (anchorTime - current.start) / current.length
        var newStart = anchorTime - anchorRatio * newLength
        var newEnd = newStart + newLength

        if newStart < full.start {
            newStart = full.start
            newEnd = min(full.end, newStart + newLength)
        }
        if newEnd > full.end {
            newEnd = full.end
            newStart = max(full.start, newEnd - newLength)
        }

        return VisibleTimeRange(start: newStart, end: newEnd)
    }
}

nonisolated func plotViewportTime(atX x: CGFloat, width: CGFloat, range: VisibleTimeRange) -> Double {
    let clampedWidth = max(width, 1)
    let ratio = Double(min(max(x / clampedWidth, 0), 1))
    return range.start + ratio * range.length
}

nonisolated func panDeltaTime(
    deltaX: CGFloat,
    width: CGFloat,
    visibleLength: Double,
    scale: Double = PlotViewportConstants.scrollWheelPanScale
) -> Double {
    let clampedWidth = max(width, 1)
    return -Double(deltaX / clampedWidth) * visibleLength * scale
}

nonisolated func scrollWheelZoomFactor(deltaX: CGFloat) -> Double {
    deltaX > 0
        ? PlotViewportConstants.scrollWheelZoomInFactor
        : PlotViewportConstants.scrollWheelZoomOutFactor
}

nonisolated func magnifyZoomFactor(magnification: CGFloat) -> Double {
    guard magnification.isFinite else { return 1 }
    let factor = 1.0 - Double(magnification)
    return min(1.25, max(0.75, factor))
}
