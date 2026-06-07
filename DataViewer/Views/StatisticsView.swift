import SwiftUI

struct StatisticsView: View {
    @Bindable var viewModel: DataViewModel
    @Environment(\.workspaceLayout) private var workspaceLayout
    @State private var intervalModeChangeTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                    intervalSection
                    StatisticsPlotAreaView(viewModel: viewModel)
                    geoSection
                    signalStatisticsSection
                }
                .padding(20)
            }
            TimelineScrubberView(viewModel: viewModel, context: .statistics)
                .frame(
                    height: TimelineScrubberLayoutMetrics.preferredHeight(
                        for: .statistics,
                        workspaceLayout: workspaceLayout
                    )
                )
        }
        .sensoryFeedback(.selection, trigger: intervalModeChangeTrigger)
        .onAppear {
            viewModel.beginStatisticsDraft()
            viewModel.prepareStatisticsTimeRanges()
        }
        .onDisappear {
            viewModel.commitStatisticsDraft()
        }
        .onChange(of: viewModel.statisticsIntervalMode) { _, _ in
            intervalModeChangeTrigger += 1
            viewModel.scheduleStatisticsRefresh()
        }
    }

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            Text(String(localized: "统计区间", comment: "Statistics interval section title"))
                .font(.headline)

            Picker(
                String(localized: "区间模式", comment: "Interval mode picker label"),
                selection: $viewModel.statisticsIntervalMode
            ) {
                ForEach(StatisticsIntervalMode.allCases) { mode in
                    Text(mode.segmentedTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("statisticsIntervalModePicker")

            if let summary = rangeSummaryContent {
                StatisticsIntervalSummaryView(
                    mode: viewModel.statisticsIntervalMode,
                    startEndpoint: summary.start,
                    endEndpoint: summary.end,
                    copyText: summary.copyText,
                    onCommitStart: { viewModel.updateStatisticsActiveRangeStart($0) },
                    onCommitEnd: { viewModel.updateStatisticsActiveRangeEnd($0) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("statisticsIntervalSection")
    }

    private var rangeSummaryContent: (
        start: StatisticsTimeEndpoint,
        end: StatisticsTimeEndpoint,
        copyText: String
    )? {
        let endpoints: (start: StatisticsTimeEndpoint, end: StatisticsTimeEndpoint)?
        switch viewModel.statisticsIntervalMode {
        case .abInterval:
            guard viewModel.statisticsABMarkersReady else { return nil }
            endpoints = viewModel.statisticsABIntervalEndpoints
        case .currentWindow:
            guard let range = viewModel.statisticsActiveRange else { return nil }
            endpoints = (
                viewModel.statisticsTimeEndpoint(at: range.start),
                viewModel.statisticsTimeEndpoint(at: range.end)
            )
        }
        guard let endpoints else { return nil }
        let copyText = StatisticsExportFormatter.intervalSummaryLines(
            mode: viewModel.statisticsIntervalMode,
            start: endpoints.start,
            end: endpoints.end
        ).joined(separator: "\n")
        return (endpoints.start, endpoints.end, copyText)
    }

    @ViewBuilder
    private var geoSection: some View {
        if let summary = viewModel.cachedStatisticsOutput.geoSummary, summary.isAvailable {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "地理信息", comment: "Geographic information section title"))
                    .font(.headline)
                CopyableStatisticsText(text: StatisticsExportFormatter.geoSectionText(from: summary))
            }
            .accessibilityIdentifier("statisticsGeoSection")
        }
    }

    @ViewBuilder
    private var signalStatisticsSection: some View {
        Text(String(localized: "信号统计", comment: "Signal statistics section title"))
            .font(.headline)

        if viewModel.statisticsIntervalMode == .abInterval, !viewModel.statisticsABMarkersReady {
            ContentUnavailableView {
                Label(
                    String(localized: "待设定区间", comment: "Statistics pending AB interval title"),
                    systemImage: "line.3.horizontal"
                )
            } description: {
                Text(String(localized: "在上方图表中拖动 A、B 标记后再查看统计结果",
                           comment: "Statistics pending AB interval description"))
            }
            .frame(maxWidth: .infinity)
        } else if viewModel.isAllPlotGroupsEmpty {
            ContentUnavailableView(
                String(localized: "暂无已选信号", comment: "No selected signals placeholder"),
                systemImage: "waveform.path.ecg",
                description: Text(statisticsEmptyHint)
            )
        } else {
            let groups = viewModel.cachedStatisticsOutput.groupedLines
            if groups.isEmpty {
                Text(String(localized: "所选区间内无可用数据", comment: "No data in selected range"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                CopyableStatisticsText(
                    text: StatisticsExportFormatter.signalSectionText(groupedLines: groups)
                )
                .accessibilityIdentifier("statisticsSignalOutput")
            }
        }
    }

    private var statisticsEmptyHint: String {
        String(localized: "请先在「信号」页点按或选择候选信号后再查看统计",
               comment: "Empty statistics hint")
    }
}

private struct StatisticsIntervalSummaryView: View {
    let mode: StatisticsIntervalMode
    let startEndpoint: StatisticsTimeEndpoint
    let endEndpoint: StatisticsTimeEndpoint
    let copyText: String
    let onCommitStart: (Double) -> Void
    let onCommitEnd: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                StatisticsExportFormatter.intervalModeLine(
                    mode: mode,
                    start: startEndpoint,
                    end: endEndpoint
                )
            )
            .textSelection(.enabled)

            HStack(spacing: 4) {
                Text(String(localized: "统计范围", comment: "Statistics range label") + ":")

                EditableStatisticsRangeEndpointsView(
                    start: startEndpoint.seconds,
                    end: endEndpoint.seconds,
                    onCommitStart: onCommitStart,
                    onCommitEnd: onCommitEnd
                )

                if startEndpoint.clockTime != nil || endEndpoint.clockTime != nil {
                    let startClock = startEndpoint.clockTime?.formatted ?? "—"
                    let endClock = endEndpoint.clockTime?.formatted ?? "—"
                    Text("（\(startClock) - \(endClock)）")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.callout.monospaced())
        .contextMenu {
            Button(String(localized: "复制", comment: "Copy to clipboard button"), systemImage: "doc.on.doc") {
                StatisticsClipboard.copy(copyText)
            }
        }
        .accessibilityIdentifier("statisticsRangeSummary")
    }
}

private struct EditableStatisticsRangeEndpointsView: View {
    var start: Double
    var end: Double
    var onCommitStart: (Double) -> Void
    var onCommitEnd: (Double) -> Void

    var body: some View {
        EditableVisibleTimeRangeView(
            start: start,
            end: end,
            length: end - start,
            showsLength: false,
            onCommitStart: onCommitStart,
            onCommitEnd: onCommitEnd
        )
        .accessibilityIdentifier("statisticsEditableRange")
    }
}
