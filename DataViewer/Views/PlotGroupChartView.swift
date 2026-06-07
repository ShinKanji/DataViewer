import SwiftUI
import Charts

struct PlotGroupChartView: View {
    let samples: [PlotSample]
    let xDomain: ClosedRange<Double>
    var yDomainOverride: ClosedRange<Double>?
    var minHeight: CGFloat = 220

    var chartSelectionTime: Double?
    var chartSelectionReadings: [ChartSelectionSample] = []
    var isCursorInteractionEnabled: Bool = false
    var onChartSelectionTimeChange: ((Double) -> Void)?
    var onChartSelectionEnd: (() -> Void)?

    var body: some View {
        let yDomain = yDomainOverride ?? yRange(for: samples)

        Chart(samples) { sample in
            LineMark(
                x: .value("时间", sample.time),
                y: .value("值", sample.value)
            )
            .foregroundStyle(by: .value("信号", sample.seriesName))
            .interpolationMethod(.linear)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartForegroundStyleScale(range: ChartColorPalette.colors)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
            PlotLinkedCursorChartOverlay(
                proxy: proxy,
                cursorTime: chartSelectionTime,
                readings: chartSelectionReadings,
                isInteractionEnabled: isCursorInteractionEnabled,
                onCursorMove: onChartSelectionTimeChange,
                onCursorEnd: onChartSelectionEnd
            )
        }
        .frame(minHeight: minHeight)
        .contentSurface(.chartContainer)
    }

    private func yRange(for samples: [PlotSample]) -> ClosedRange<Double> {
        SeriesSampler.yRange(
            for: samples,
            in: VisibleTimeRange(start: xDomain.lowerBound, end: xDomain.upperBound)
        )
    }
}

private struct PlotLinkedCursorChartOverlay: View {
    let proxy: ChartProxy
    let cursorTime: Double?
    let readings: [ChartSelectionSample]
    let isInteractionEnabled: Bool
    let onCursorMove: ((Double) -> Void)?
    let onCursorEnd: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            if let plotFrameAnchor = proxy.plotFrame {
            let plotFrame = geometry[plotFrameAnchor]

            ZStack(alignment: .topLeading) {
                if let cursorTime,
                   let xPos = proxy.position(forX: cursorTime) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1.5, height: plotFrame.height)
                        .position(x: xPos, y: plotFrame.midY)

                    ForEach(readings) { reading in
                        if let yPos = proxy.position(forY: reading.scaledValue) {
                            let color = ChartColorPalette.color(at: reading.colorIndex)
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                Text(formatValue(reading.scaledValue))
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .contentAnnotationBackground(
                                        RoundedRectangle(cornerRadius: Constants.smallCornerRadius, style: .continuous)
                                    )
                                    .offset(x: 10, y: -14)
                            }
                            .position(x: xPos, y: yPos)
                        }
                    }
                }

                if isInteractionEnabled, onCursorMove != nil {
                    CursorInteractionGestureView(
                        onChanged: { location in
                            handleLocation(location, plotFrame: plotFrame)
                        },
                        onEnded: {
                            onCursorEnd?()
                        }
                    )
                    .frame(width: plotFrame.width, height: plotFrame.height)
                    .position(x: plotFrame.midX, y: plotFrame.midY)
                }
            }
            }
        }
    }

    private func handleLocation(_ location: CGPoint, plotFrame: CGRect) {
        guard plotFrame.contains(location),
              let time = proxy.value(atX: location.x, as: Double.self) else { return }
        onCursorMove?(time)
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}

enum ChartColorPalette {
    static let colors: [Color] = [.blue, .orange, .green, .red, .purple, .teal, .pink, .yellow]

    static func color(at index: Int) -> Color {
        let palette = colors
        guard !palette.isEmpty else { return .primary }
        return palette[index % palette.count]
    }
}
