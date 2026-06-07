import SwiftUI

struct PlotAreaView: View {
    @Bindable var viewModel: DataViewModel
    @Environment(\.workspaceLayout) private var workspaceLayout

    var body: some View {
        VStack(spacing: 0) {
            plotDropZone
            TimelineScrubberView(viewModel: viewModel)
                .frame(
                    height: TimelineScrubberLayoutMetrics.preferredHeight(
                        for: .mainPlot,
                        workspaceLayout: workspaceLayout
                    )
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            EditableVisibleTimeRangeView(
                start: viewModel.visibleRange.start,
                end: viewModel.visibleRange.end,
                length: viewModel.visibleRange.length,
                onCommitStart: { start in
                    viewModel.updateVisibleRange(start: start, end: viewModel.visibleRange.end)
                },
                onCommitEnd: { end in
                    viewModel.updateVisibleRange(start: viewModel.visibleRange.start, end: end)
                }
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, Constants.toolbarHorizontalInset)
            .padding(.vertical, Constants.toolbarVerticalInset)
        }
    }

    private var plotDropZone: some View {
        Group {
            if viewModel.isAllPlotGroupsEmpty {
                ContentUnavailableView(
                    String(localized: "暂无曲线", comment: "Empty plot area title"),
                    systemImage: "chart.xyaxis.line",
                    description: Text(emptyPlotHint)
                )
                .accessibilityIdentifier("plotAreaEmpty")
                .accessibilityLabel(String(localized: "暂无曲线", comment: "Empty plot area accessibility label"))
            } else {
                ScrollView {
                    LazyVStack(spacing: Constants.plotGroupSpacing) {
                        ForEach(viewModel.orderedNonEmptyPlotGroups) { group in
                            PlotGroupChartContainer(viewModel: viewModel, group: group)
                        }
                    }
                    .padding(Constants.plotGroupSpacing)
                }
                .accessibilityElement()
                .accessibilityIdentifier("plotArea")
                .accessibilityLabel(String(localized: "数据曲线", comment: "Plot area accessibility label"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .plotViewportInteraction(
            target: .mainPlot,
            viewModel: viewModel,
            isEnabled: !viewModel.isAllPlotGroupsEmpty
        )
        .channelCandidateDropDestination(viewModel: viewModel, style: .fullFrameContentShape)
        .accessibilityElement()
        .accessibilityIdentifier(
            !viewModel.isAllPlotGroupsEmpty
                ? "plotAreaReady"
                : "plotAreaDropTarget"
        )
    }

    private var emptyPlotHint: String {
        workspaceLayout.select(
            phone: String(localized: "点按「信号」页中的候选信号添加，或拖放到已选区域",
                           comment: "Empty plot hint on iPhone / iPad portrait"),
            wide: String(localized: "从左侧候选区点选后使用添加按钮",
                          comment: "Empty plot hint on iPad landscape")
        )
    }
}
