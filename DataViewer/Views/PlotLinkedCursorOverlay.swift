import SwiftUI

struct PlotGroupChartContainer: View {
    @Bindable var viewModel: DataViewModel
    let group: PlotGroup

    var body: some View {
        let isScrubbing = viewModel.isTimelineScrubbing
        let interactionEnabled = !isScrubbing

        let title = viewModel.plotGroupTitle(for: group)
        let showsHeader = viewModel.plotGroupShowsChartHeader(for: group)

        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            PlotGroupChartView(
                samples: viewModel.plotChartSamples(for: group),
                xDomain: viewModel.visibleRange.start...viewModel.visibleRange.end,
                yDomainOverride: nil,
                chartSelectionTime: viewModel.chartSelectionTime,
                chartSelectionReadings: viewModel.chartSelectionReadings(for: group),
                isCursorInteractionEnabled: interactionEnabled,
                onChartSelectionTimeChange: { viewModel.updateChartSelection(time: $0) },
                onChartSelectionEnd: { viewModel.clearChartSelection() }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(String(localized: "\(group.channelIDs.count) 条曲线", comment: "Chart series count accessibility value"))
        .accessibilityIdentifier("plotGroupChart_\(group.id.uuidString)")
    }
}
