import SwiftUI

struct StatisticsPlotAreaView: View {
    @Bindable var viewModel: DataViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsABCoachingBanner {
                abCoachingBanner
            }

            plotContent
        }
    }

    private var showsABCoachingBanner: Bool {
        viewModel.statisticsIntervalMode == .abInterval && !viewModel.statisticsABMarkersReady
    }

    private var abCoachingBanner: some View {
        Label {
            Text(String(localized: "拖动 A、B 标记设定统计区间",
                       comment: "AB interval coaching banner on statistics chart"))
                .font(.callout)
        } icon: {
            Image(systemName: "hand.draw")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: Constants.smallCornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        }
        .accessibilityIdentifier("statisticsABCoachingBanner")
    }

    @ViewBuilder
    private var plotContent: some View {
        if viewModel.isAllPlotGroupsEmpty {
            ContentUnavailableView(
                String(localized: "暂无曲线", comment: "Empty statistics plot area title"),
                systemImage: "chart.xyaxis.line",
                description: Text(emptyPlotHint)
            )
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityIdentifier("statisticsPlotAreaEmpty")
            .accessibilityLabel(String(localized: "暂无曲线", comment: "Empty plot area accessibility label"))
        } else {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.orderedNonEmptyPlotGroups) { group in
                    StatisticsGroupChartRow(viewModel: viewModel, group: group)
                }
            }
            .plotViewportInteraction(target: .statistics, viewModel: viewModel)
            .accessibilityElement()
            .accessibilityIdentifier("statisticsPlotArea")
            .accessibilityLabel(String(localized: "统计曲线", comment: "Statistics plot area accessibility label"))
        }
    }

    private var emptyPlotHint: String {
        String(localized: "在「信号」页点按或选择候选信号后添加",
               comment: "Empty statistics plot hint")
    }
}

private struct StatisticsGroupChartRow: View {
    @Bindable var viewModel: DataViewModel
    let group: PlotGroup

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlotGroupChartView(
                samples: viewModel.statisticsChartSamples(for: group),
                xDomain: viewModel.statisticsVisibleRange.start...viewModel.statisticsVisibleRange.end,
                yDomainOverride: nil
            )
            if viewModel.statisticsIntervalMode == .abInterval {
                StatisticsABMarkerOverlay(
                    xDomain: viewModel.statisticsVisibleRange.start...viewModel.statisticsVisibleRange.end,
                    markerA: viewModel.statisticsMarkerA,
                    markerB: viewModel.statisticsMarkerB,
                    onUpdateA: { viewModel.updateStatisticsMarkerA($0) },
                    onUpdateB: { viewModel.updateStatisticsMarkerB($0) }
                )
            }
        }
    }
}

struct StatisticsABMarkerOverlay: View {
    let xDomain: ClosedRange<Double>
    let markerA: Double?
    let markerB: Double?
    let onUpdateA: (Double) -> Void
    let onUpdateB: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                if let markerA {
                    statisticsMarkerLine(
                        label: "A",
                        color: .orange,
                        markerTime: markerA,
                        width: width,
                        height: height,
                        onMarkerTimeChanged: onUpdateA
                    )
                }
                if let markerB {
                    statisticsMarkerLine(
                        label: "B",
                        color: .purple,
                        markerTime: markerB,
                        width: width,
                        height: height,
                        onMarkerTimeChanged: onUpdateB
                    )
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
    }

    private func statisticsMarkerLine(
        label: String,
        color: Color,
        markerTime: Double,
        width: CGFloat,
        height: CGFloat,
        onMarkerTimeChanged: @escaping (Double) -> Void
    ) -> some View {
        let x = xPosition(for: markerTime, width: width)
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(color.opacity(0.85))
                .frame(width: 2, height: height)
            Text(label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .contentAnnotationBackground(Capsule())
                .foregroundStyle(.primary)
                .offset(y: 4)
        }
        .offset(x: x - 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onMarkerTimeChanged(time(for: value.location.x, width: width))
                }
        )
        .accessibilityElement()
        .accessibilityIdentifier("statisticsPlotMarker\(label)")
        .accessibilityLabel(String(localized: "\(label) 标记", comment: "Statistics marker accessibility label"))
        .accessibilityValue(String(format: String(localized: "%.2f 秒", comment: "Seconds format for marker accessibility"), markerTime))
        .accessibilityHint(String(localized: "拖动以调整 \(label) 标记位置", comment: "Drag marker accessibility hint"))
        .accessibilityAdjustableAction { direction in
            let step = max(xDomain.upperBound - xDomain.lowerBound, 0.001) * 0.02
            switch direction {
            case .increment:
                onMarkerTimeChanged(clampStatisticsTime(markerTime + step))
            case .decrement:
                onMarkerTimeChanged(clampStatisticsTime(markerTime - step))
            @unknown default:
                break
            }
        }
    }

    private func clampStatisticsTime(_ time: Double) -> Double {
        min(max(time, xDomain.lowerBound), xDomain.upperBound)
    }

    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        TimeCoordinateMapper(domain: xDomain).xPosition(for: time, width: width)
    }

    private func time(for x: CGFloat, width: CGFloat) -> Double {
        TimeCoordinateMapper(domain: xDomain).time(for: x, width: width)
    }
}
