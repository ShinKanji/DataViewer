import SwiftUI

enum TimelineScrubberContext: Equatable {
    case mainPlot
    case statistics
}

struct TimelineScrubberLayoutMetrics {
    static let standardDockHeight: CGFloat = 88
    static let compactDockHeight: CGFloat = 72

    let preferredHeight: CGFloat
    let outerHorizontalPadding: CGFloat
    let bottomPadding: CGFloat
    let trackHeight: CGFloat
    let trackCornerRadius: CGFloat

    static func preferredHeight(
        for context: TimelineScrubberContext,
        workspaceLayout: WorkspaceLayout
    ) -> CGFloat {
        metrics(for: context, workspaceLayout: workspaceLayout).preferredHeight
    }

    static func metrics(
        for context: TimelineScrubberContext,
        workspaceLayout: WorkspaceLayout
    ) -> TimelineScrubberLayoutMetrics {
        return TimelineScrubberLayoutMetrics(
            preferredHeight: standardDockHeight,
            outerHorizontalPadding: 12,
            bottomPadding: 10,
            trackHeight: 66,
            trackCornerRadius: 0
        )
    }
}

struct TimelineScrubberView: View {
    @Bindable var viewModel: DataViewModel
    var context: TimelineScrubberContext = .mainPlot
    @Environment(\.workspaceLayout) private var workspaceLayout

    @State private var dragMode: DragMode?
    @State private var dragStartRange = VisibleTimeRange(start: 0, end: 1)
    @State private var didBeginTimelineScrub = false

    private var layoutMetrics: TimelineScrubberLayoutMetrics {
        TimelineScrubberLayoutMetrics.metrics(for: context, workspaceLayout: workspaceLayout)
    }

    private var dockTopSeparator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.08),
                        Color.primary.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 1)
    }

    private enum DragMode {
        case move
        case start
        case end
    }

    var body: some View {
        let fullRange = resolvedFullRange
        let visibleRange = resolvedVisibleRange
        let metrics = layoutMetrics

        VStack(alignment: .leading, spacing: 0) {
            dockTopSeparator

            HStack(alignment: .center, spacing: Constants.controlSpacing) {
                timelineTrack(fullRange: fullRange, visibleRange: visibleRange, metrics: metrics)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, metrics.outerHorizontalPadding)
            .padding(.vertical, metrics.bottomPadding)
        }
        .contentSurface(.timelineDock)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "时间轴", comment: "Timeline accessibility label"))
        .accessibilityValue(accessibilityRangeValue(fullRange: fullRange, visibleRange: visibleRange))
        .accessibilityHint(String(localized: "调整可见时间窗口范围", comment: "Timeline accessibility hint"))
        .accessibilityAdjustableAction { direction in
            adjustRangeViaAccessibility(
                direction: direction,
                fullRange: fullRange,
                visibleRange: visibleRange
            )
        }
        .accessibilityIdentifier(timelineAccessibilityID)
    }

    private func timelineTrack(
        fullRange: VisibleTimeRange,
        visibleRange: VisibleTimeRange,
        metrics: TimelineScrubberLayoutMetrics
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.trackCornerRadius, style: .continuous)
        let selectionShape = Rectangle()

        return GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let plotHeight = max(geometry.size.height, 1)

            let rawStartX = xPosition(for: visibleRange.start, width: width, fullRange: fullRange)
            let rawEndX = xPosition(for: visibleRange.end, width: width, fullRange: fullRange)
            let startX = min(max(rawStartX, 0), width)
            let endX = min(max(rawEndX, 0), width)
            let visualSelectionWidth = max(endX - startX, 0)
            let hitSelectionWidth = max(visualSelectionWidth, 8)
            let minimumHitTargetSize = CGSize(width: 44, height: max(plotHeight, 44))

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    previewPath(
                        in: CGSize(width: width, height: plotHeight),
                        fullRange: fullRange
                    )
                    .stroke(Color.secondary.opacity(0.55), lineWidth: 1)

                    selectionBody(shape: selectionShape)
                        .frame(width: visualSelectionWidth, height: plotHeight)
                        .offset(x: startX)
                }
                .clipShape(shape)

                gripHandle
                    .frame(width: minimumHitTargetSize.width, height: minimumHitTargetSize.height)
                    .offset(x: startX - minimumHitTargetSize.width / 2, y: (plotHeight - minimumHitTargetSize.height) / 2)
                    .gesture(rangeDragGesture(mode: .start, fullRange: fullRange, width: width))

                gripHandle
                    .frame(width: minimumHitTargetSize.width, height: minimumHitTargetSize.height)
                    .offset(x: startX + visualSelectionWidth - minimumHitTargetSize.width / 2, y: (plotHeight - minimumHitTargetSize.height) / 2)
                    .gesture(rangeDragGesture(mode: .end, fullRange: fullRange, width: width))

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: hitSelectionWidth, height: plotHeight)
                    .offset(x: startX)
                    .contentShape(Rectangle())
                    .gesture(rangeDragGesture(mode: .move, fullRange: fullRange, width: width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(panGesture(fullRange: fullRange, visibleRange: visibleRange, width: width))
        }
        .frame(
            maxWidth: .infinity,
            minHeight: metrics.trackHeight,
            maxHeight: metrics.trackHeight,
            alignment: .center
        )
        .background {
            shape.fill(.regularMaterial)
        }
    }

    private var resolvedFullRange: VisibleTimeRange {
        switch context {
        case .mainPlot: viewModel.fullRange
        case .statistics: viewModel.statisticsFullRange
        }
    }

    private var resolvedVisibleRange: VisibleTimeRange {
        switch context {
        case .mainPlot: viewModel.visibleRange
        case .statistics: viewModel.statisticsVisibleRange
        }
    }

    private func previewPath(in size: CGSize, fullRange: VisibleTimeRange) -> Path {
        var path = Path()
        let samples: [(time: Double, value: Double)]
        switch context {
        case .statistics:
            samples = viewModel.statisticsTimelinePreviewSamples
        case .mainPlot:
            samples = viewModel.timelinePreviewSamples
        }
        guard samples.count > 1 else { return path }

        var minV = Double.greatestFiniteMagnitude
        var maxV = -Double.greatestFiniteMagnitude
        for s in samples {
            let v = s.value
            if v < minV { minV = v }
            if v > maxV { maxV = v }
        }
        guard maxV > minV else { return path }

        let valueSpan = max(maxV - minV, 1e-6)
        let height = size.height
        let heightMinus8 = height - 8
        let width = size.width
        let fullSpan = max(fullRange.length, 0.001)

        for (index, sample) in samples.enumerated() {
            let x = CGFloat((sample.time - fullRange.start) / fullSpan) * width
            let y = height - CGFloat((sample.value - minV) / valueSpan) * heightMinus8 - 4
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    @ViewBuilder
    private func selectionBody(shape: Rectangle) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 0.8)
            }
    }

    private var gripHandle: some View {
        ZStack {
            Color.clear

            RoundedRectangle(cornerRadius: Constants.gripCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Constants.gripCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Constants.gripCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.8)
                }
                .frame(width: 22, height: 40)

            HStack(spacing: 3) {
                Capsule()
                    .fill(Color.primary.opacity(0.34))
                    .frame(width: 1.5, height: 18)
                Capsule()
                    .fill(Color.primary.opacity(0.34))
                    .frame(width: 1.5, height: 18)
            }
        }
        .contentShape(Rectangle())
    }

    private func xPosition(for time: Double, width: CGFloat, fullRange: VisibleTimeRange) -> CGFloat {
        TimeCoordinateMapper(domain: fullRange.start...fullRange.end).xPosition(for: time, width: width)
    }

    private func time(for x: CGFloat, width: CGFloat, fullRange: VisibleTimeRange) -> Double {
        TimeCoordinateMapper(domain: fullRange.start...fullRange.end).time(for: x, width: width)
    }

    private func rangeDragGesture(mode: DragMode, fullRange: VisibleTimeRange, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = mode
                    dragStartRange = resolvedVisibleRange
                    beginTimelineScrubIfNeeded()
                }
                applyDrag(
                    translation: value.translation.width,
                    width: width,
                    fullRange: fullRange
                )
            }
            .onEnded { _ in
                dragMode = nil
                endTimelineScrubIfNeeded()
            }
    }

    private func panGesture(
        fullRange: VisibleTimeRange,
        visibleRange: VisibleTimeRange,
        width: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = .move
                    dragStartRange = visibleRange
                    beginTimelineScrubIfNeeded()
                }
                applyDrag(
                    translation: value.translation.width,
                    width: width,
                    fullRange: fullRange
                )
            }
            .onEnded { _ in
                dragMode = nil
                endTimelineScrubIfNeeded()
            }
    }

    private func beginTimelineScrubIfNeeded() {
        guard !didBeginTimelineScrub else { return }
        didBeginTimelineScrub = true
        switch context {
        case .mainPlot:
            viewModel.beginTimelineScrub()
        case .statistics:
            viewModel.beginStatisticsTimelineScrub()
        }
    }

    private func endTimelineScrubIfNeeded() {
        guard didBeginTimelineScrub else { return }
        didBeginTimelineScrub = false
        switch context {
        case .mainPlot:
            viewModel.endMainPlotTimelineScrub()
        case .statistics:
            viewModel.endStatisticsTimelineScrub()
        }
    }

    private func applyDrag(
        translation: CGFloat,
        width: CGFloat,
        fullRange: VisibleTimeRange
    ) {
        let deltaTime = Double(translation / width) * fullRange.length
        guard let dragMode else { return }

        switch dragMode {
        case .start:
            updateRange(start: dragStartRange.start + deltaTime, end: dragStartRange.end)
        case .end:
            updateRange(start: dragStartRange.start, end: dragStartRange.end + deltaTime)
        case .move:
            var newStart = dragStartRange.start + deltaTime
            var newEnd = dragStartRange.end + deltaTime
            if newStart < fullRange.start {
                newEnd += fullRange.start - newStart
                newStart = fullRange.start
            }
            if newEnd > fullRange.end {
                newStart -= newEnd - fullRange.end
                newEnd = fullRange.end
            }
            updateRange(start: newStart, end: newEnd)
        }
    }

    private func updateRange(start: Double, end: Double) {
        switch context {
        case .mainPlot:
            viewModel.updateVisibleRange(start: start, end: end)
        case .statistics:
            viewModel.updateStatisticsVisibleRange(start: start, end: end)
        }
    }

    private func accessibilityRangeValue(
        fullRange: VisibleTimeRange,
        visibleRange: VisibleTimeRange
    ) -> String {
        "可见 \(timeText(visibleRange.start)) 到 \(timeText(visibleRange.end))，范围 \(timeText(visibleRange.length))，全程 \(timeText(fullRange.length))"
    }

    private func adjustRangeViaAccessibility(
        direction: AccessibilityAdjustmentDirection,
        fullRange: VisibleTimeRange,
        visibleRange: VisibleTimeRange
    ) {
        let step = max(visibleRange.length * 0.1, 0.1)
        switch direction {
        case .increment:
            updateRange(start: visibleRange.start + step, end: visibleRange.end + step)
        case .decrement:
            updateRange(start: visibleRange.start - step, end: visibleRange.end - step)
        @unknown default:
            break
        }
    }

    private func timeText(_ seconds: Double) -> String {
        String(format: "%.2f 秒", seconds)
    }

    private var timelineAccessibilityID: String {
        switch context {
        case .mainPlot: "timelineScrubber"
        case .statistics: "statisticsTimelineScrubber"
        }
    }
}
