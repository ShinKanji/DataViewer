import Foundation
import Observation
import QuartzCore
import SwiftUI

struct PlotChannelMutationSnapshot: Equatable {
    var plotGroups: [PlotGroup]
    var activeGroupID: UUID?
    var selectedChannelIDs: [UUID]
}

struct ChannelActionToast: Identifiable {
    let id = UUID()
    let message: String
    let undoSnapshot: PlotChannelMutationSnapshot
}

struct JumpPointRemovalResult: Equatable {
    var processedCount: Int
    var removedTotal: Int
    var skippedDerived: [UUID]
    var skippedUnavailable: [UUID]
}

struct HeadingUnwrapResult: Equatable {
    var processedCount: Int
    var skippedDerived: [UUID]
    var skippedUnavailable: [UUID]
}

@MainActor
@Observable
final class DataViewModel {
    var dataFileURL: URL?

    var candidateChannels: [ChannelDescriptor] = []
    var selectedChannelIDs: [UUID] = []
    var plotGroups: [PlotGroup] = []

    var loadedSeries: [UUID: DataSeries] = [:]
    var visibleRange = VisibleTimeRange(start: 0, end: 60)
    var fullRange = VisibleTimeRange(start: 0, end: 60)

    var isLoading = false
    var loadingProgress: LoadingProgressState?
    var statusMessage = String(localized: "请导入 TXT 或 CSV 数据文件", comment: "Initial status message")
    var errorMessage: String?

    var selectedCandidateIDs: Set<UUID> = []
    var selectedPlottedIDs: Set<UUID> = []
    var activeGroupID: UUID?

    var selectedPlotGroupIDs: Set<UUID> {
        get {
            Set(orderedNonEmptyPlotGroups.filter { isPlotGroupFullySelected($0) }.map(\.id))
        }
        set {
            var newPlotted = selectedPlottedIDs
            for group in orderedNonEmptyPlotGroups {
                let nowSelected = newValue.contains(group.id)
                let wasSelected = isPlotGroupFullySelected(group)
                if nowSelected && !wasSelected {
                    newPlotted.formUnion(group.channelIDs)
                } else if !nowSelected && wasSelected {
                    newPlotted.subtract(group.channelIDs)
                }
            }
            selectedPlottedIDs = newPlotted
        }
    }

    var channelValueScales: [UUID: Double] = [:]
    var chartSelectionTime: Double?
    var isChartSelectionActive = false
    var isUITestFixturesReady = false
    var isShowingDataImporter = false
    var channelActionToast: ChannelActionToast?

    var statisticsIntervalMode: StatisticsIntervalMode = .currentWindow
    var statisticsVisibleRange = VisibleTimeRange(start: 0, end: 60)
    var statisticsFullRange = VisibleTimeRange(start: 0, end: 60)
    var statisticsMarkerA: Double?
    var statisticsMarkerB: Double?
    var geoSamples: [GeoCoordinateSample]?
    var geoLoadState: GeoLoadState = .idle

    var plotGroupSamples: [UUID: [PlotSample]] = [:]
    var statisticsGroupSamples: [UUID: [PlotSample]] = [:]
    var plotGroupFullPreviewSamples: [UUID: [PlotSample]] = [:]
    var statisticsGroupFullPreviewSamples: [UUID: [PlotSample]] = [:]
    var isTimelineScrubbing = false
    var isStatisticsTimelineScrubbing = false
    var cachedStatisticsOutput = CachedStatisticsOutput.empty
    var timelinePreviewSamples: [(time: Double, value: Double)] = []
    var statisticsTimelinePreviewSamples: [(time: Double, value: Double)] = []

    private var catalogByID: [UUID: ChannelDescriptor] = [:]
    private var derivedRecords: [UUID: DerivedChannelRecord] = [:]
    private var derivedSeriesCache: [UUID: DataSeries] = [:]
    private var displaySeriesCache: [UUID: DataSeries] = [:]
    private var securityScopedURLs: [URL] = []
    private var plotSampleRefreshTask: Task<Void, Never>?
    private var statisticsRefreshTask: Task<Void, Never>?
    private var fullPreviewRefreshTask: Task<Void, Never>?
    private var statisticsScrollResetTask: Task<Void, Never>?
    private var mainPlotScrollResetTask: Task<Void, Never>?
    private var timelinePreviewRefreshTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var catalogBackgroundTask: Task<Void, Never>?
    private let loadingProgressSimulator = LoadingProgressSimulator()
    private var clockTimeTable: TextClockTimeTable?
    private let plotSampleStore = PlotSampleStore()
    private var sampleCacheGeneration: UInt = 0
    private var lastVisibleRangeCommitTime: TimeInterval = 0
    private var lastStatisticsVisibleRangeCommitTime: TimeInterval = 0
    private var lastStatisticsOutputKey: StatisticsOutputKey?

    private var cachedFriendlyName: [UUID: String] = [:]
    private var cachedPlotSeriesName: [UUID: String] = [:]
    private var cachedChannelListSubtitle: [UUID: String] = [:]
    private var cachedSelectedChannelSubtitle: [UUID: String?] = [:]

    private struct StatisticsOutputKey: Equatable {
        let mode: StatisticsIntervalMode
        let range: VisibleTimeRange
        let markerA: Double?
        let markerB: Double?
        let dataGeneration: UInt
    }

    private struct StatisticsDraftSnapshot {
        var statisticsIntervalMode: StatisticsIntervalMode
        var statisticsVisibleRange: VisibleTimeRange
        var statisticsMarkerA: Double?
        var statisticsMarkerB: Double?
    }

    private var statisticsDraftSnapshot: StatisticsDraftSnapshot?

    private static let sampleRefreshDebounceMs = 120
    private static let visibleRangeThrottleInterval: TimeInterval = 1.0 / 30
    private static let samplePreviewMaxPoints = 1_500
    private static let sampleFullMaxPoints = 4_000
    private static let timelinePreviewMaxPoints = 1_200

    private struct ChannelSampleTask: Sendable {
        let groupID: UUID
        let series: DataSeries
        let range: VisibleTimeRange
        let maxPoints: Int
        let timeOffset: Double
        let valueScale: Double
        let seriesName: String
    }

    private struct FullPreviewChannelTask: Sendable {
        let groupID: UUID
        let isStatistics: Bool
        let series: DataSeries
        let range: VisibleTimeRange
        let timeOffset: Double
        let valueScale: Double
        let seriesName: String
    }

    var availableCandidates: [ChannelDescriptor] {
        let selected = Set(selectedChannelIDs)
        return candidateChannels.filter { !selected.contains($0.id) }
    }

    var selectedChannels: [ChannelDescriptor] {
        selectedChannelIDs.compactMap { catalogByID[$0] }
    }

    var plottedGroupChipItems: [(id: UUID, group: PlotGroup, title: String, subtitle: String?)] {
        orderedNonEmptyPlotGroups.map { group in
            (
                id: group.id,
                group: group,
                title: plotGroupTitle(for: group),
                subtitle: plotGroupSubtitle(for: group)
            )
        }
    }

    var orderedNonEmptyPlotGroups: [PlotGroup] {
        plotGroups.filter { !$0.channelIDs.isEmpty }
    }

    var isAllPlotGroupsEmpty: Bool {
        plotGroups.allSatisfy { $0.channelIDs.isEmpty }
    }

    func plotGroupTitle(for group: PlotGroup) -> String {
        PlotGroupDisplayNaming.title(
            for: group,
            catalogByID: catalogByID,
            derivedRecords: derivedRecords
        )
    }

    func plotGroupSubtitle(for group: PlotGroup) -> String? {
        PlotGroupDisplayNaming.subtitle(
            for: group,
            catalogByID: catalogByID,
            derivedRecords: derivedRecords
        )
    }

    func plotGroupShowsChartHeader(for group: PlotGroup) -> Bool {
        PlotGroupDisplayNaming.showsChartHeader(for: group)
    }

    func channelDescriptor(for channelID: UUID) -> ChannelDescriptor? {
        catalogByID[channelID]
    }

    func isPlotGroupFullySelected(_ group: PlotGroup) -> Bool {
        !group.channelIDs.isEmpty && group.channelIDs.allSatisfy { selectedPlottedIDs.contains($0) }
    }

    func togglePlotGroupSelection(_ group: PlotGroup) {
        if isPlotGroupFullySelected(group) {
            selectedPlottedIDs.subtract(group.channelIDs)
        } else {
            selectedPlottedIDs.formUnion(group.channelIDs)
        }
    }

    func movePlotGroups(fromOffsets: IndexSet, toOffset: Int) {
        var ordered = orderedNonEmptyPlotGroups
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let emptyGroups = plotGroups.filter { $0.channelIDs.isEmpty }
        plotGroups = ordered + emptyGroups
        syncSelectedChannelIDsFromPlotGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
    }

    func movePlotGroupUp(_ groupID: UUID) {
        guard let index = orderedNonEmptyPlotGroups.firstIndex(where: { $0.id == groupID }),
              index > 0 else { return }
        movePlotGroups(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
    }

    func movePlotGroupDown(_ groupID: UUID) {
        let groups = orderedNonEmptyPlotGroups
        guard let index = groups.firstIndex(where: { $0.id == groupID }),
              index < groups.count - 1 else { return }
        movePlotGroups(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
    }

    func syncSelectedChannelIDsFromPlotGroups() {
        selectedChannelIDs = plotGroups.flatMap(\.channelIDs)
    }

    var previewSeries: DataSeries? {
        for channelID in selectedChannelIDs {
            if let series = loadedSeries[channelID] {
                return series
            }
        }
        return loadedSeries.values.first
    }

    func requestImportData() {
        isShowingDataImporter = true
    }

    func handleImportedFile(_ url: URL) {
        isShowingDataImporter = false
        let accessed = url.startAccessingSecurityScopedResource()
        if accessed { url.stopAccessingSecurityScopedResource() }
        openDataFile(url)
    }

    var statisticsActiveRange: VisibleTimeRange? {
        switch statisticsIntervalMode {
        case .currentWindow:
            guard statisticsVisibleRange.length > 0 else { return nil }
            return statisticsVisibleRange
        case .abInterval:
            guard let a = statisticsMarkerA, let b = statisticsMarkerB else { return nil }
            return VisibleTimeRange(start: min(a, b), end: max(a, b))
        }
    }

    var statisticsABMarkersReady: Bool {
        statisticsMarkerA != nil && statisticsMarkerB != nil
    }

    var statisticsABIntervalEndpoints: (start: StatisticsTimeEndpoint, end: StatisticsTimeEndpoint)? {
        guard statisticsIntervalMode == .abInterval,
              statisticsABMarkersReady,
              let markerA = statisticsMarkerA,
              let markerB = statisticsMarkerB else { return nil }
        let startSeconds = min(markerA, markerB)
        let endSeconds = max(markerA, markerB)
        return (
            statisticsTimeEndpoint(at: startSeconds),
            statisticsTimeEndpoint(at: endSeconds)
        )
    }

    func geoSegmentSummary(for range: VisibleTimeRange) -> GeoSegmentSummary? {
        guard let geoSamples else { return nil }
        return GeoSegmentResolver.summary(samples: geoSamples, range: range)
    }

    func statisticsTimeEndpoint(at displaySeconds: Double) -> StatisticsTimeEndpoint {
        let clockTime = clockTimeTable?.clockTime(atDisplaySeconds: displaySeconds)
        return StatisticsTimeEndpoint(seconds: displaySeconds, clockTime: clockTime)
    }

    init() {
        if DataViewerLaunchConfig.isUITesting {
            Task { @MainActor in
                await DataViewerLaunchConfig.applyIfNeeded(to: self)
            }
        }
    }

    func openDataFile(_ url: URL) {
        if let previous = dataFileURL {
            TabularTextParser.invalidateCache(for: previous)
        }
        replaceSecurityScopedURL(old: dataFileURL, new: url)
        dataFileURL = url
        geoSamples = nil
        geoLoadState = .idle
        reloadCatalog()
    }

    func friendlyName(for descriptor: ChannelDescriptor) -> String {
        if let cached = cachedFriendlyName[descriptor.id] {
            return cached
        }
        return computeFriendlyName(descriptor)
    }

    func plotSeriesName(for descriptor: ChannelDescriptor) -> String {
        if let cached = cachedPlotSeriesName[descriptor.id] {
            return cached
        }
        return computePlotSeriesName(descriptor)
    }

    var plottedChannelDescriptors: [ChannelDescriptor] {
        var seen = Set<UUID>()
        var result: [ChannelDescriptor] = []
        for group in plotGroups {
            for channelID in group.channelIDs where !seen.contains(channelID) {
                seen.insert(channelID)
                if let descriptor = catalogByID[channelID] {
                    result.append(descriptor)
                }
            }
        }
        return result
    }

    func effectiveScale(for channelID: UUID) -> Double {
        let scale = channelValueScales[channelID] ?? 1
        return scale.isFinite && scale != 0 ? scale : 1
    }

    func applyChannelScale(channelID: UUID, multiplier: Double) {
        guard multiplier.isFinite, multiplier != 0 else { return }
        channelValueScales[channelID] = effectiveScale(for: channelID) * multiplier
        invalidateDerivedCache(forParentID: channelID)
        invalidatePlotSampleCache()
        refreshPlotSamplesNow()
        scheduleStatisticsRefresh()
    }

    func resetChannelScale(channelID: UUID) {
        channelValueScales.removeValue(forKey: channelID)
        invalidateDerivedCache(forParentID: channelID)
        invalidatePlotSampleCache()
        refreshPlotSamplesNow()
        scheduleStatisticsRefresh()
    }

    func resetAllChannelScales() {
        guard !channelValueScales.isEmpty else { return }
        channelValueScales.removeAll()
        invalidateDerivedCache(forParentID: nil)
        invalidatePlotSampleCache()
        refreshPlotSamplesNow()
        scheduleStatisticsRefresh()
    }

    func isDerivedChannel(_ channelID: UUID) -> Bool {
        derivedRecords[channelID] != nil
    }

    func jumpRemovalTargetChannelIDs() -> [UUID] {
        selectedChannelIDs.filter { derivedRecords[$0] == nil }
    }

    func jumpRemovalTargetChannels() -> [ChannelDescriptor] {
        jumpRemovalTargetChannelIDs().compactMap { catalogByID[$0] }
    }

    var hasSelectedHeadingAngleChannels: Bool {
        !selectedHeadingAngleChannelIDs().isEmpty
    }

    func selectedHeadingAngleChannelIDs() -> [UUID] {
        selectedChannelIDs.filter { channelID in
            guard derivedRecords[channelID] == nil,
                  let descriptor = catalogByID[channelID] else {
                return false
            }
            return ChannelColumnNaming.isHeadingAngleColumn(descriptor.columnName)
        }
    }

    func selectedHeadingAngleChannels() -> [ChannelDescriptor] {
        selectedHeadingAngleChannelIDs().compactMap { catalogByID[$0] }
    }

    func unwrapHeadingAngleInSelectedChannels() async -> HeadingUnwrapResult {
        let targetIDs = selectedHeadingAngleChannelIDs()
        var result = HeadingUnwrapResult(
            processedCount: 0,
            skippedDerived: [],
            skippedUnavailable: []
        )

        result.skippedDerived = selectedChannelIDs.filter { derivedRecords[$0] != nil }

        var isAnyModified = false
        for channelID in targetIDs {
            guard let series = await ensureRawSeriesLoaded(channelID) else {
                result.skippedUnavailable.append(channelID)
                continue
            }

            let unwrapped = SignalTransform.unwrapHeadingAngle(values: series.values)
            loadedSeries[channelID] = DataSeries(
                id: series.id,
                descriptor: series.descriptor,
                times: series.times,
                values: unwrapped
            )
            derivedSeriesCache.removeValue(forKey: channelID)
            invalidateDerivedCache(forParentID: channelID)
            result.processedCount += 1
            isAnyModified = true
        }

        if isAnyModified {
            invalidatePlotSampleCache()
            refreshPlotSamplesNow()
            scheduleStatisticsRefresh()
        }

        return result
    }

    func removeJumpPointsFromSelectedChannels(
        manualThreshold: Double?
    ) async -> JumpPointRemovalResult {
        let targetIDs = jumpRemovalTargetChannelIDs()
        var result = JumpPointRemovalResult(
            processedCount: 0,
            removedTotal: 0,
            skippedDerived: [],
            skippedUnavailable: []
        )

        let skippedDerived = selectedChannelIDs.filter { derivedRecords[$0] != nil }
        result.skippedDerived = skippedDerived

        var isAnyModified = false
        for channelID in targetIDs {
            guard let series = await ensureRawSeriesLoaded(channelID) else {
                result.skippedUnavailable.append(channelID)
                continue
            }

            let removal = SignalTransform.removeJumpPoints(
                values: series.values,
                threshold: manualThreshold
            )
            guard let thresholdUsed = removal.thresholdUsed else {
                result.skippedUnavailable.append(channelID)
                continue
            }
            guard removal.removedCount > 0 else {
                result.processedCount += 1
                continue
            }

            loadedSeries[channelID] = DataSeries(
                id: series.id,
                descriptor: series.descriptor,
                times: series.times,
                values: removal.values
            )
            derivedSeriesCache.removeValue(forKey: channelID)
            invalidateDerivedCache(forParentID: channelID)
            result.processedCount += 1
            result.removedTotal += removal.removedCount
            isAnyModified = true
        }

        if isAnyModified {
            invalidatePlotSampleCache()
            refreshPlotSamplesNow()
            scheduleStatisticsRefresh()
        }

        return result
    }

    func defaultComputeSourceChannelID() -> UUID? {
        if selectedCandidateIDs.count == 1, let id = selectedCandidateIDs.first {
            return id
        }
        if selectedChannelIDs.count == 1, let id = selectedChannelIDs.first {
            return id
        }
        return nil
    }

    var computeSourceChannelChoices: [ChannelDescriptor] {
        var seen = Set<UUID>()
        var result: [ChannelDescriptor] = []
        for id in selectedChannelIDs {
            guard !seen.contains(id), let descriptor = catalogByID[id] else { continue }
            seen.insert(id)
            result.append(descriptor)
        }
        for descriptor in availableCandidates where !seen.contains(descriptor.id) {
            seen.insert(descriptor.id)
            result.append(descriptor)
        }
        return result
    }

    @discardableResult
    func registerDerivedChannel(
        parentID: UUID,
        op: DerivedOpKind,
        windowSamples: Int? = nil
    ) throws -> UUID {
        guard catalogByID[parentID] != nil else {
            throw DerivedRegistrationError.parentNotFound
        }
        if op == .movmean {
            guard let windowSamples, windowSamples >= 1 else {
                throw DerivedRegistrationError.invalidWindow
            }
        }

        guard let parentDescriptor = catalogByID[parentID] else {
            throw DerivedRegistrationError.parentNotFound
        }

        let parentDisplayName = plotSeriesName(for: parentDescriptor)
        let baseName = derivedDisplayName(
            parentName: parentDisplayName,
            op: op,
            windowSamples: windowSamples
        )
        let uniqueName = uniquifyDerivedDisplayName(baseName)
        let record = DerivedChannelRecord(
            parentID: parentID,
            op: op,
            windowSamples: windowSamples,
            displayName: uniqueName
        )
        derivedRecords[record.id] = record

        let descriptor = ChannelDescriptor(
            id: record.id,
            containerName: parentDescriptor.containerName,
            columnName: DerivedChannelNaming.internalColumnName(displayName: uniqueName),
            columnIndex: -1
        )
        candidateChannels.append(descriptor)
        catalogByID[descriptor.id] = descriptor
        invalidateDerivedCache(forParentID: parentID)
        statusMessage = String(localized: "已加入候选：", comment: "Candidate added prefix") + uniqueName
        return record.id
    }

    func resolveDataSeries(for channelID: UUID) async -> DataSeries? {
        if let cached = derivedSeriesCache[channelID] {
            return cached
        }
        guard let descriptor = catalogByID[channelID] else { return nil }

        if let derived = derivedRecords[channelID] {
            guard let parentSeries = await resolveDataSeries(for: derived.parentID) else { return nil }
            let transformed = SignalTransform.apply(
                op: derived.op,
                times: parentSeries.times,
                values: parentSeries.values,
                windowSamples: derived.windowSamples
            )
            guard transformed.count == parentSeries.times.count else { return nil }
            let scale = effectiveScale(for: channelID)
            let scaledValues = transformed.map { $0.isFinite ? $0 * scale : $0 }
            let series = DataSeries(
                id: channelID,
                descriptor: descriptor,
                times: parentSeries.times,
                values: scaledValues
            )
            derivedSeriesCache[channelID] = series
            return series
        }

        guard let raw = await ensureRawSeriesLoaded(channelID) else { return nil }
        let scale = effectiveScale(for: channelID)
        let values = raw.values.map { $0.isFinite ? $0 * scale : $0 }
        let series = DataSeries(id: channelID, descriptor: descriptor, times: raw.times, values: values)
        derivedSeriesCache[channelID] = series
        return series
    }

    func invalidateDerivedCache(forParentID parentID: UUID?) {
        if let parentID {
            derivedSeriesCache.removeValue(forKey: parentID)
            for id in derivedRecords.keys where hasAncestor(id, ancestor: parentID) {
                derivedSeriesCache.removeValue(forKey: id)
            }
        } else {
            derivedSeriesCache.removeAll()
        }
        displaySeriesCache.removeAll()
    }

    enum DerivedRegistrationError: LocalizedError {
        case parentNotFound
        case invalidWindow

        var errorDescription: String? {
            switch self {
            case .parentNotFound:
                return "找不到源信号"
            case .invalidWindow:
                return "滑动平均窗口必须为 ≥ 1 的整数"
            }
        }
    }

    private func derivedDisplayName(
        parentName: String,
        op: DerivedOpKind,
        windowSamples: Int?
    ) -> String {
        switch op {
        case .deriv:
            return "d(\(parentName))/dt"
        case .integ:
            return "∫(\(parentName))dt"
        case .movmean:
            return "MA(\(parentName),\(windowSamples ?? 1))"
        }
    }

    private func uniquifyDerivedDisplayName(_ baseName: String) -> String {
        let existingNames = Set(
            candidateChannels.compactMap { descriptor -> String? in
                if let derived = derivedRecords[descriptor.id] {
                    return derived.displayName
                }
                return plotSeriesName(for: descriptor)
            }
        )
        if !existingNames.contains(baseName) { return baseName }
        var suffix = 2
        while existingNames.contains("\(baseName) (\(suffix))") {
            suffix += 1
        }
        return "\(baseName) (\(suffix))"
    }

    private func hasAncestor(_ channelID: UUID, ancestor: UUID) -> Bool {
        var current: UUID? = channelID
        while let id = current {
            if id == ancestor { return true }
            guard let derived = derivedRecords[id] else { break }
            current = derived.parentID
        }
        return false
    }

    private func ensureRawSeriesLoaded(_ channelID: UUID) async -> DataSeries? {
        guard derivedRecords[channelID] == nil else { return nil }
        if let cached = loadedSeries[channelID] {
            return cached
        }
        guard let descriptor = catalogByID[channelID] else { return nil }
        do {
            let series = try await loadSeries(for: descriptor)
            loadedSeries[channelID] = series
            return series
        } catch {
            return nil
        }
    }

    private func resolveDisplaySeriesSnapshot(for channelIDs: Set<UUID>) async -> [UUID: DataSeries] {
        var result: [UUID: DataSeries] = [:]
        for channelID in channelIDs {
            if let series = await resolveDataSeries(for: channelID) {
                result[channelID] = series
            }
        }
        displaySeriesCache = result
        return result
    }

    private func pruneDerivedRecords() {
        var hasChanged = true
        while hasChanged {
            hasChanged = false
            for (id, record) in derivedRecords {
                let parentAvailable = catalogByID[record.parentID] != nil
                if !parentAvailable {
                    derivedRecords.removeValue(forKey: id)
                    derivedSeriesCache.removeValue(forKey: id)
                    channelValueScales.removeValue(forKey: id)
                    candidateChannels.removeAll { $0.id == id }
                    catalogByID.removeValue(forKey: id)
                    hasChanged = true
                }
            }
        }
    }

    private func syncDerivedCandidates(with rawPlotCandidates: [ChannelDescriptor]) {
        catalogByID = Dictionary(uniqueKeysWithValues: rawPlotCandidates.map { ($0.id, $0) })
        pruneDerivedRecords()
        let derivedDescriptors = derivedRecords.values.map { record -> ChannelDescriptor in
            let parent = catalogByID[record.parentID]
            return ChannelDescriptor(
                id: record.id,
                containerName: parent?.containerName ?? "derived",
                columnName: DerivedChannelNaming.internalColumnName(displayName: record.displayName),
                columnIndex: -1
            )
        }
        for descriptor in derivedDescriptors {
            catalogByID[descriptor.id] = descriptor
        }
        candidateChannels = rawPlotCandidates + derivedDescriptors
    }

    private func refreshDisplayNameCache() {
        var friendly: [UUID: String] = [:]
        var series: [UUID: String] = [:]
        var subtitle: [UUID: String] = [:]
        var selectedSubtitle: [UUID: String?] = [:]
        friendly.reserveCapacity(candidateChannels.count)
        series.reserveCapacity(candidateChannels.count)
        subtitle.reserveCapacity(candidateChannels.count)
        selectedSubtitle.reserveCapacity(candidateChannels.count)

        for descriptor in candidateChannels {
            let id = descriptor.id
            friendly[id] = computeFriendlyName(descriptor)
            series[id] = computePlotSeriesName(descriptor)
            subtitle[id] = computeChannelListSubtitle(descriptor)
            selectedSubtitle[id] = computeSelectedChannelSubtitle(descriptor)
        }
        cachedFriendlyName = friendly
        cachedPlotSeriesName = series
        cachedChannelListSubtitle = subtitle
        cachedSelectedChannelSubtitle = selectedSubtitle
    }

    private func computeFriendlyName(_ descriptor: ChannelDescriptor) -> String {
        if let derived = derivedRecords[descriptor.id] {
            return derived.displayName
        }
        if ChannelColumnNaming.usesVelocityKPHDisplayName(descriptor.columnName) {
            return ChannelColumnNaming.unifiedVelocityKPHDisplayName
        }
        return descriptor.columnName
    }

    private func computePlotSeriesName(_ descriptor: ChannelDescriptor) -> String {
        computeFriendlyName(descriptor)
    }

    private func computeChannelListSubtitle(_ descriptor: ChannelDescriptor) -> String {
        if let derived = derivedRecords[descriptor.id] {
            return "派生 · \(derived.displayName)"
        }
        return descriptor.containerName
    }

    private func computeSelectedChannelSubtitle(_ descriptor: ChannelDescriptor) -> String? {
        if derivedRecords[descriptor.id] != nil {
            return "派生"
        }
        return nil
    }

    func updateChartSelection(time: Double) {
        let clamped = min(max(time, visibleRange.start), visibleRange.end)
        chartSelectionTime = clamped
        isChartSelectionActive = true
    }

    func clearChartSelection() {
        chartSelectionTime = nil
        isChartSelectionActive = false
    }

    func chartSelectionReadings(for group: PlotGroup) -> [ChartSelectionSample] {
        guard let plotTime = chartSelectionTime else { return [] }
        var results: [ChartSelectionSample] = []
        for (index, channelID) in group.channelIDs.enumerated() {
            guard let descriptor = catalogByID[channelID] else { continue }
            let value: Double?
            if let series = displaySeriesCache[channelID] {
                value = SeriesSampler.valueAtPlotTime(
                    plotTime,
                    series: series,
                    timeOffset: 0,
                    valueScale: 1
                )
            } else if let series = loadedSeries[channelID] {
                value = SeriesSampler.valueAtPlotTime(
                    plotTime,
                    series: series,
                    timeOffset: 0,
                    valueScale: effectiveScale(for: channelID)
                )
            } else {
                continue
            }
            guard let value else { continue }
            results.append(
                ChartSelectionSample(
                    channelID: channelID,
                    seriesName: plotSeriesName(for: descriptor),
                    scaledValue: value,
                    plotTime: plotTime,
                    colorIndex: index % 8
                )
            )
        }
        return results
    }

    func channelListSubtitle(for descriptor: ChannelDescriptor) -> String {
        if let cached = cachedChannelListSubtitle[descriptor.id] {
            return cached
        }
        return computeChannelListSubtitle(descriptor)
    }

    func selectedChannelSubtitle(for descriptor: ChannelDescriptor) -> String? {
        if let cached = cachedSelectedChannelSubtitle[descriptor.id] {
            return cached
        }
        return computeSelectedChannelSubtitle(descriptor)
    }

    func bootstrapUITestFixtures(from directory: URL) async {
        statusMessage = String(localized: "正在加载测试数据...", comment: "Loading test data status")
        let dataURL = DataViewerLaunchConfig.uiTestDataFileURL(in: directory)
        replaceSecurityScopedURL(old: dataFileURL, new: dataURL)
        dataFileURL = dataURL
        await loadCatalog()
        await refreshLoadedSeriesAndRange()
        isUITestFixturesReady = true
    }

    func reloadCatalog() {
        Task {
            await loadCatalog()
        }
    }

    func loadCatalog() async {
        isLoading = true
        errorMessage = nil
        loadingProgress = LoadingProgressState(phaseLabel: ImportDurationEstimator.importingFileLabel, fraction: 0)

        let fileURL = dataFileURL
        let phases = ImportDurationEstimator.phases(
            dataFileURL: fileURL,
            selectedChannelCount: selectedChannelIDs.count
        )
        beginLoadingProgress(phases: phases)

        do {
            var phaseIndex = 0

            if let fileURL {
                loadingProgressEnterPhase(at: phaseIndex)
                let descriptors = try await Task.detached {
                    try TabularTextParser.parseCatalog(from: fileURL)
                }.value
                loadingProgressCompletePhase(at: phaseIndex)
                phaseIndex += 1

                loadingProgressEnterPhase(at: phaseIndex)
                let clockTable = try? await Task.detached {
                    try TextClockTimeResolver.load(from: fileURL)
                }.value
                clockTimeTable = clockTable
                loadingProgressCompletePhase(at: phaseIndex)
                phaseIndex += 1

                let plotCandidates = ChannelColumnNaming.candidateListChannels(from: descriptors)
                syncDerivedCandidates(with: plotCandidates)
                refreshDisplayNameCache()
                selectedCandidateIDs = selectedCandidateIDs.filter { catalogByID[$0] != nil }
                selectedChannelIDs.removeAll { catalogByID[$0] == nil }
                plotGroups = plotGroups.map { group in
                    var updated = group
                    updated.channelIDs.removeAll { !selectedChannelIDs.contains($0) }
                    return updated
                }
                pruneEmptyPlotGroups()
                syncSelectedChannelIDsFromPlotGroups()
                loadedSeries.removeAll()
                invalidatePlotSampleCache()

                let shouldReloadSeries = !selectedChannelIDs.isEmpty
                if shouldReloadSeries {
                    await refreshLoadedSeriesAndRange(
                        continuesLoadingSession: true,
                        startingPhaseIndex: phaseIndex
                    )
                } else {
                    finishLoadingProgress()
                    isLoading = false
                }

                reloadGeoSamples()
            } else {
                candidateChannels = []
                catalogByID = [:]
                clockTimeTable = nil
                finishLoadingProgress()
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            finishLoadingProgress()
            isLoading = false
        }
    }

    func reloadGeoSamples() {
        guard let fileURL = dataFileURL else {
            geoSamples = nil
            geoLoadState = .idle
            return
        }

        geoLoadState = .loading
        Task {
            let result: [GeoCoordinateSample]?
            do {
                result = try await Task.detached {
                    try TextGeoLoader.load(from: fileURL)
                }.value
            } catch {
                result = nil
            }
            geoSamples = result
            geoLoadState = result == nil ? .unavailable : .ready
            scheduleStatisticsRefresh()
        }
    }

    @discardableResult
    func addCandidatesFromDrag(_ ids: [UUID]) -> Bool {
        addCandidatesToPlot(ids)
    }

    @discardableResult
    func addCandidatesToPlot(_ ids: [UUID]) -> Bool {
        let newIDs = resolvedCandidateIDsToAdd(from: ids)
        guard !newIDs.isEmpty else { return false }

        let undoSnapshot = capturePlotChannelSnapshot()
        assignToNewGroup(newIDs)
        syncSelectedChannelIDsFromPlotGroups()
        selectedCandidateIDs.subtract(newIDs)
        Task { await refreshLoadedSeriesAndRange() }

        let message = channelAddToastMessage(for: newIDs)
        presentChannelActionToast(message: message, undoSnapshot: undoSnapshot)
        return true
    }

    func removePlottedChannel(_ channelID: UUID) {
        guard selectedChannelIDs.contains(channelID) else { return }

        let undoSnapshot = capturePlotChannelSnapshot()
        for index in plotGroups.indices {
            plotGroups[index].channelIDs.removeAll { $0 == channelID }
        }
        loadedSeries.removeValue(forKey: channelID)
        selectedPlottedIDs.remove(channelID)
        syncSelectedChannelIDsFromPlotGroups()
        pruneEmptyPlotGroups()
        dissolveSingleSignalGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
        Task { await refreshLoadedSeriesAndRange() }

        if let channel = catalogByID[channelID] {
            let message = String(
                format: String(localized: "已移除 %@", comment: "Removed channel toast"),
                friendlyName(for: channel)
            )
            presentChannelActionToast(message: message, undoSnapshot: undoSnapshot)
        }
    }

    func undoLastChannelMutation() {
        guard let toast = channelActionToast else { return }
        toastDismissTask?.cancel()
        channelActionToast = nil
        restorePlotChannelSnapshot(toast.undoSnapshot)
        Task { await refreshLoadedSeriesAndRange() }
    }

    func dismissChannelActionToast() {
        toastDismissTask?.cancel()
        channelActionToast = nil
    }

    private func capturePlotChannelSnapshot() -> PlotChannelMutationSnapshot {
        PlotChannelMutationSnapshot(
            plotGroups: plotGroups,
            activeGroupID: activeGroupID,
            selectedChannelIDs: selectedChannelIDs
        )
    }

    private func restorePlotChannelSnapshot(_ snapshot: PlotChannelMutationSnapshot) {
        plotGroups = snapshot.plotGroups
        activeGroupID = snapshot.activeGroupID
        selectedChannelIDs = snapshot.selectedChannelIDs
        let validIDs = Set(selectedChannelIDs)
        for key in loadedSeries.keys where !validIDs.contains(key) {
            loadedSeries.removeValue(forKey: key)
        }
        selectedPlottedIDs = selectedPlottedIDs.intersection(validIDs)
        pruneEmptyPlotGroups()
        dissolveSingleSignalGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
    }

    private func channelAddToastMessage(for ids: [UUID]) -> String {
        let names = ids.compactMap { catalogByID[$0].map { friendlyName(for: $0) } }
        switch names.count {
        case 0:
            return String(localized: "已添加到曲线", comment: "Generic add toast")
        case 1:
            return String(
                format: String(localized: "已添加 %@", comment: "Single channel add toast"),
                names[0]
            )
        default:
            return String(
                format: String(localized: "已添加 %lld 个信号", comment: "Multiple channels add toast"),
                Int64(names.count)
            )
        }
    }

    private func presentChannelActionToast(message: String, undoSnapshot: PlotChannelMutationSnapshot) {
        toastDismissTask?.cancel()
        let toast = ChannelActionToast(message: message, undoSnapshot: undoSnapshot)
        channelActionToast = toast
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            if channelActionToast?.id == toast.id {
                channelActionToast = nil
            }
        }
    }

    func assignSelectedPlottedToActiveGroup() {
        guard let activeGroupID else { return }
        for id in selectedPlottedIDs {
            assignChannel(id, to: activeGroupID)
        }
    }

    func candidateDragPayload(for channel: ChannelDescriptor) -> ChannelDragPayload {
        let dragIDs: [UUID]
        if selectedCandidateIDs.contains(channel.id), !selectedCandidateIDs.isEmpty {
            dragIDs = availableCandidates
                .map(\.id)
                .filter { selectedCandidateIDs.contains($0) }
        } else {
            dragIDs = [channel.id]
        }
        return ChannelDragPayload(channelIDs: dragIDs)
    }

    func removeSelectedPlotted() {
        for index in plotGroups.indices {
            plotGroups[index].channelIDs.removeAll { selectedPlottedIDs.contains($0) }
        }
        for id in selectedPlottedIDs {
            loadedSeries.removeValue(forKey: id)
        }
        selectedPlottedIDs.removeAll()
        syncSelectedChannelIDsFromPlotGroups()
        pruneEmptyPlotGroups()
        dissolveSingleSignalGroups()
        Task { await refreshLoadedSeriesAndRange() }
    }

    func removePlotGroup(_ groupID: UUID) {
        guard let groupIndex = plotGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let channelIDs = plotGroups[groupIndex].channelIDs
        for id in channelIDs {
            loadedSeries.removeValue(forKey: id)
            selectedPlottedIDs.remove(id)
        }
        plotGroups.remove(at: groupIndex)
        if activeGroupID == groupID {
            activeGroupID = plotGroups.last?.id
        }
        syncSelectedChannelIDsFromPlotGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
        Task { await refreshLoadedSeriesAndRange() }
    }

    func createGroup() {
        guard selectedPlottedIDs.count >= 2 else { return }
        let ids = Array(selectedPlottedIDs)
        for id in ids {
            for index in plotGroups.indices {
                plotGroups[index].channelIDs.removeAll { $0 == id }
            }
        }
        let group = PlotGroup(name: defaultMergedGroupName(for: ids), channelIDs: ids)
        plotGroups.append(group)
        activeGroupID = group.id
        selectedPlottedIDs.removeAll()
        syncSelectedChannelIDsFromPlotGroups()
        pruneEmptyPlotGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
    }

    func renameActiveGroup(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let id = activeGroupID,
              let index = plotGroups.firstIndex(where: { $0.id == id }) else { return }
        plotGroups[index].name = trimmed
    }

    func assignChannel(_ channelID: UUID, to groupID: UUID) {
        for index in plotGroups.indices {
            plotGroups[index].channelIDs.removeAll { $0 == channelID }
        }
        guard let groupIndex = plotGroups.firstIndex(where: { $0.id == groupID }) else { return }
        if !plotGroups[groupIndex].channelIDs.contains(channelID) {
            plotGroups[groupIndex].channelIDs.append(channelID)
        }
        applyInferredGroupNameIfAppropriate(for: groupID)
        syncSelectedChannelIDsFromPlotGroups()
        pruneEmptyPlotGroups()
        dissolveSingleSignalGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
    }

    func schedulePlotSampleRefresh() {
        guard !isTimelineScrubbing else { return }
        let generation = sampleCacheGeneration
        plotSampleRefreshTask?.cancel()
        plotSampleRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.sampleRefreshDebounceMs))
            guard !Task.isCancelled else { return }
            await performPlotSampleRefresh(
                generation: generation,
                maxPoints: Self.sampleFullMaxPoints
            )
        }
    }

    func scheduleStatisticsRefresh() {
        guard !isStatisticsTimelineScrubbing else { return }
        let generation = sampleCacheGeneration
        statisticsRefreshTask?.cancel()
        statisticsRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.sampleRefreshDebounceMs))
            guard !Task.isCancelled else { return }
            await performStatisticsRefresh(
                generation: generation,
                maxPoints: Self.sampleFullMaxPoints,
                includeOutput: true
            )
        }
    }

    func refreshPlotSamplesNow() {
        plotSampleRefreshTask?.cancel()
        let generation = sampleCacheGeneration
        Task {
            await performPlotSampleRefresh(
                generation: generation,
                maxPoints: Self.sampleFullMaxPoints
            )
        }
    }

    func refreshStatisticsNow() {
        statisticsRefreshTask?.cancel()
        let generation = sampleCacheGeneration
        Task {
            await performStatisticsRefresh(
                generation: generation,
                maxPoints: Self.sampleFullMaxPoints,
                includeOutput: true
            )
        }
    }

    func refreshFullPreviewSamples() {
        fullPreviewRefreshTask?.cancel()
        let generation = sampleCacheGeneration
        fullPreviewRefreshTask = Task {
            await performFullPreviewRefresh(generation: generation)
        }
    }

    func ensureFullPreviewSamplesReady() {
        let needsPlotPreview = plotGroups.contains { group in
            !group.channelIDs.isEmpty && plotGroupFullPreviewSamples[group.id] == nil
        }
        let needsStatsPreview = plotGroups.contains { group in
            !group.channelIDs.isEmpty && statisticsGroupFullPreviewSamples[group.id] == nil
        }
        if needsPlotPreview || needsStatsPreview {
            refreshFullPreviewSamples()
        }
    }

    func beginTimelineScrub() {
        isTimelineScrubbing = true
        ensureFullPreviewSamplesReady()
    }

    func beginStatisticsTimelineScrub() {
        isStatisticsTimelineScrubbing = true
        ensureFullPreviewSamplesReady()
    }

    func endMainPlotTimelineScrub() {
        isTimelineScrubbing = false
        refreshPlotSamplesNow()
    }

    func endStatisticsTimelineScrub() {
        isStatisticsTimelineScrubbing = false
        refreshStatisticsNow()
    }

    func beginPlotViewportInteraction(for target: PlotViewportTarget) {
        switch target {
        case .mainPlot:
            beginTimelineScrub()
            mainPlotScrollResetTask?.cancel()
            mainPlotScrollResetTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                endPlotViewportInteraction(for: .mainPlot)
            }
        case .statistics:
            beginStatisticsTimelineScrub()
            statisticsScrollResetTask?.cancel()
            statisticsScrollResetTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                endPlotViewportInteraction(for: .statistics)
            }
        }
    }

    func endPlotViewportInteraction(for target: PlotViewportTarget) {
        switch target {
        case .mainPlot:
            endMainPlotTimelineScrub()
        case .statistics:
            endStatisticsTimelineScrub()
        }
    }

    func plotChartSamples(for group: PlotGroup) -> [PlotSample] {
        if isTimelineScrubbing {
            return plotGroupFullPreviewSamples[group.id] ?? plotGroupSamples[group.id] ?? []
        }
        return plotGroupSamples[group.id] ?? []
    }

    func plotChartYDomain(for group: PlotGroup) -> ClosedRange<Double>? {
        guard isTimelineScrubbing else { return nil }
        let samples = plotChartSamples(for: group)
        guard !samples.isEmpty else { return nil }
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        for s in samples where s.value.isFinite {
            if s.value < minVal { minVal = s.value }
            if s.value > maxVal { maxVal = s.value }
        }
        guard minVal.isFinite, maxVal.isFinite, maxVal > minVal else { return nil }
        let padding = (maxVal - minVal) * 0.08
        return (minVal - padding)...(maxVal + padding)
    }

    func statisticsChartSamples(for group: PlotGroup) -> [PlotSample] {
        if isStatisticsTimelineScrubbing {
            return statisticsGroupFullPreviewSamples[group.id] ?? statisticsGroupSamples[group.id] ?? []
        }
        return statisticsGroupSamples[group.id] ?? []
    }

    func statisticsChartYDomain(for group: PlotGroup) -> ClosedRange<Double>? {
        guard isStatisticsTimelineScrubbing else { return nil }
        let samples = statisticsChartSamples(for: group)
        guard !samples.isEmpty else { return nil }
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        for s in samples where s.value.isFinite {
            if s.value < minVal { minVal = s.value }
            if s.value > maxVal { maxVal = s.value }
        }
        guard minVal.isFinite, maxVal.isFinite, maxVal > minVal else { return nil }
        let padding = (maxVal - minVal) * 0.08
        return (minVal - padding)...(maxVal + padding)
    }

    func beginStatisticsDraft() {
        statisticsDraftSnapshot = StatisticsDraftSnapshot(
            statisticsIntervalMode: statisticsIntervalMode,
            statisticsVisibleRange: statisticsVisibleRange,
            statisticsMarkerA: statisticsMarkerA,
            statisticsMarkerB: statisticsMarkerB
        )
    }

    func revertStatisticsDraft() {
        guard let snapshot = statisticsDraftSnapshot else { return }
        statisticsIntervalMode = snapshot.statisticsIntervalMode
        statisticsVisibleRange = snapshot.statisticsVisibleRange
        statisticsMarkerA = snapshot.statisticsMarkerA
        statisticsMarkerB = snapshot.statisticsMarkerB
        statisticsDraftSnapshot = nil
        refreshStatisticsNow()
    }

    func commitStatisticsDraft() {
        statisticsDraftSnapshot = nil
    }

    func prepareStatisticsTimeRanges() {
        statisticsFullRange = fullRange
        let global = fullRange
        guard global.length > 0 else {
            statisticsVisibleRange = global
            resetStatisticsABMarkers()
            return
        }

        let defaultEnd = min(global.end, global.start + max(60, global.length * 0.2))
        let defaultVisible = VisibleTimeRange(start: global.start, end: defaultEnd)
        let main = visibleRange
        let mainFillsGlobal = main.length >= global.length * 0.95

        if main.start >= global.start,
           main.end <= global.end,
           main.length > 0,
           !mainFillsGlobal {
            statisticsVisibleRange = main
        } else {
            statisticsVisibleRange = defaultVisible
        }
        resetStatisticsABMarkers()
        refreshFullPreviewSamples()
        refreshStatisticsNow()
        scheduleTimelinePreviewCacheRefresh()
    }

    func updateStatisticsVisibleRange(start: Double, end: Double) {
        let clampedStart = max(statisticsFullRange.start, min(start, statisticsFullRange.end))
        let clampedEnd = max(clampedStart + 0.1, min(end, statisticsFullRange.end))

        if isStatisticsTimelineScrubbing {
            let now = CACurrentMediaTime()
            if now - lastStatisticsVisibleRangeCommitTime < Self.visibleRangeThrottleInterval
                && clampedStart == statisticsVisibleRange.start
                && clampedEnd == statisticsVisibleRange.end {
                return
            }
            lastStatisticsVisibleRangeCommitTime = now
        }

        statisticsVisibleRange = VisibleTimeRange(start: clampedStart, end: clampedEnd)
        if !isStatisticsTimelineScrubbing {
            scheduleStatisticsRefresh()
        }
    }

    func zoomStatisticsVisibleRange(factor: Double, anchor: Double? = nil) {
        guard let shifted = PlotViewportRangeOperations.zoomedVisibleRange(
            current: statisticsVisibleRange,
            full: statisticsFullRange,
            factor: factor,
            anchor: anchor
        ) else { return }
        updateStatisticsVisibleRange(start: shifted.start, end: shifted.end)
    }

    func zoomVisibleRange(factor: Double, anchor: Double? = nil) {
        guard let shifted = PlotViewportRangeOperations.zoomedVisibleRange(
            current: visibleRange,
            full: fullRange,
            factor: factor,
            anchor: anchor
        ) else { return }
        updateVisibleRange(start: shifted.start, end: shifted.end)
    }

    func panVisibleRange(byDeltaTime deltaTime: Double) {
        guard deltaTime != 0, fullRange.length > 0 else { return }
        let shifted = PlotViewportRangeOperations.shiftedVisibleRange(
            current: visibleRange,
            full: fullRange,
            deltaTime: deltaTime
        )
        updateVisibleRange(start: shifted.start, end: shifted.end)
    }

    func panStatisticsVisibleRange(byDeltaTime deltaTime: Double) {
        guard deltaTime != 0, statisticsFullRange.length > 0 else { return }
        let shifted = PlotViewportRangeOperations.shiftedVisibleRange(
            current: statisticsVisibleRange,
            full: statisticsFullRange,
            deltaTime: deltaTime
        )
        updateStatisticsVisibleRange(start: shifted.start, end: shifted.end)
    }

    func updateStatisticsMarkerA(_ time: Double) {
        statisticsMarkerA = clampStatisticsTime(time)
        scheduleStatisticsRefresh()
    }

    func updateStatisticsMarkerB(_ time: Double) {
        statisticsMarkerB = clampStatisticsTime(time)
        scheduleStatisticsRefresh()
    }

    func updateStatisticsActiveRangeStart(_ start: Double) {
        switch statisticsIntervalMode {
        case .currentWindow:
            updateStatisticsVisibleRange(start: start, end: statisticsVisibleRange.end)
        case .abInterval:
            updateStatisticsABIntervalBoundary(isStart: true, time: start)
        }
    }

    func updateStatisticsActiveRangeEnd(_ end: Double) {
        switch statisticsIntervalMode {
        case .currentWindow:
            updateStatisticsVisibleRange(start: statisticsVisibleRange.start, end: end)
        case .abInterval:
            updateStatisticsABIntervalBoundary(isStart: false, time: end)
        }
    }

    func statisticsPreviewSamples(maxPoints: Int = 1_200) -> [(time: Double, value: Double)] {
        _ = maxPoints
        return statisticsTimelinePreviewSamples
    }

    func previewSamples(maxPoints: Int = 1_200) -> [(time: Double, value: Double)] {
        _ = maxPoints
        return timelinePreviewSamples
    }

    func refreshTimelinePreviewCacheNow() async {
        timelinePreviewRefreshTask?.cancel()
        await refreshTimelinePreviewCache()
    }

    func updateVisibleRange(start: Double, end: Double) {
        let clampedStart = max(fullRange.start, min(start, fullRange.end))
        let clampedEnd = max(clampedStart + 0.1, min(end, fullRange.end))

        if isTimelineScrubbing {
            let now = CACurrentMediaTime()
            if now - lastVisibleRangeCommitTime < Self.visibleRangeThrottleInterval
                && clampedStart == visibleRange.start
                && clampedEnd == visibleRange.end {
                return
            }
            lastVisibleRangeCommitTime = now
        }

        visibleRange = VisibleTimeRange(start: clampedStart, end: clampedEnd)
        if !isTimelineScrubbing {
            schedulePlotSampleRefresh()
        }
    }

    func displayTimeOffset(for descriptor: ChannelDescriptor) -> Double {
        _ = descriptor
        return 0
    }

    func invalidatePlotSampleCacheForTesting() {
        invalidatePlotSampleCache()
    }

    func configureCatalogForTesting(_ descriptors: [ChannelDescriptor]) {
        candidateChannels = descriptors
        catalogByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    }

    var groupingEligibleGroups: [PlotGroup] {
        plotGroups.filter { $0.channelIDs.count >= 2 }
    }

    private func defaultStatisticsPreviewChannelID() -> UUID? {
        for group in plotGroups {
            for channelID in group.channelIDs where loadedSeries[channelID] != nil {
                return channelID
            }
        }
        return nil
    }

    private var statisticsPreviewSeries: DataSeries? {
        guard let id = defaultStatisticsPreviewChannelID(), let series = loadedSeries[id] else {
            return nil
        }
        return series
    }

    private func resetStatisticsABMarkers() {
        let span = statisticsVisibleRange.length
        guard span > 0 else { return }
        statisticsMarkerA = statisticsVisibleRange.start + span / 3
        statisticsMarkerB = statisticsVisibleRange.start + span * 2 / 3
    }

    private func clampStatisticsTime(_ time: Double) -> Double {
        min(max(time, statisticsFullRange.start), statisticsFullRange.end)
    }

    private func updateStatisticsABIntervalBoundary(isStart: Bool, time: Double) {
        guard let markerA = statisticsMarkerA, let markerB = statisticsMarkerB else { return }
        let rounded = clampStatisticsTime(time.rounded())
        let currentStart = min(markerA, markerB)
        let currentEnd = max(markerA, markerB)
        let edit = PlotViewportRangeOperations.normalizedEndpointEdit(
            editingStart: isStart,
            input: rounded,
            currentStart: currentStart,
            currentEnd: currentEnd
        )
        let range = PlotViewportRangeOperations.clampedVisibleRange(
            start: edit.start,
            end: edit.end,
            full: statisticsFullRange
        )
        let startMarkerIsA = markerA <= markerB

        if edit.swapped {
            if startMarkerIsA {
                statisticsMarkerA = range.end
                statisticsMarkerB = range.start
            } else {
                statisticsMarkerA = range.start
                statisticsMarkerB = range.end
            }
        } else if isStart {
            if startMarkerIsA {
                statisticsMarkerA = range.start
            } else {
                statisticsMarkerB = range.start
            }
        } else if startMarkerIsA {
            statisticsMarkerB = range.end
        } else {
            statisticsMarkerA = range.end
        }

        scheduleStatisticsRefresh()
    }

    private func performFullPreviewRefresh(generation: UInt) async {
        let fullRangeSnapshot = fullRange
        guard fullRangeSnapshot.length > 0 else { return }

        let statsRangeSnapshot = statisticsFullRange.length > 0 ? statisticsFullRange : fullRangeSnapshot
        let channelIDs = Set(plotGroups.flatMap(\.channelIDs))
        let displaySeries = await resolveDisplaySeriesSnapshot(for: channelIDs)

        let tasks = fullPreviewChannelTasks(
            groups: plotGroups,
            displaySeries: displaySeries,
            catalogByID: catalogByID,
            plotRange: fullRangeSnapshot,
            statisticsRange: statsRangeSnapshot
        )
        guard !tasks.isEmpty else { return }

        let store = plotSampleStore
        let merged = await ParallelWorkPolicy.measureAsync("performFullPreviewRefresh") {
            let parts = await ParallelWorkPolicy.map(inputs: tasks) { task in
                let samples = await store.samples(
                    series: task.series,
                    range: task.range,
                    maxPoints: Self.samplePreviewMaxPoints,
                    timeOffset: task.timeOffset,
                    valueScale: task.valueScale,
                    seriesName: task.seriesName,
                    smoothingWindow: 3
                )
                return (task.groupID, task.isStatistics, samples)
            }
            return mergeFullPreviewSamples(parts)
        }

        guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
        plotGroupFullPreviewSamples = merged.plot
        statisticsGroupFullPreviewSamples = merged.statistics
    }

    private func performPlotSampleRefresh(generation: UInt, maxPoints: Int) async {
        let channelIDs = Set(plotGroups.flatMap(\.channelIDs))
        let displaySeries = await resolveDisplaySeriesSnapshot(for: channelIDs)
        let tasks = channelSampleTasks(
            groups: plotGroups,
            displaySeries: displaySeries,
            catalogByID: catalogByID,
            range: visibleRange,
            maxPoints: maxPoints
        )

        let result: [UUID: [PlotSample]]
        if tasks.isEmpty {
            result = [:]
        } else {
            let store = plotSampleStore
            result = await ParallelWorkPolicy.measureAsync("performPlotSampleRefresh") {
                let parts = await ParallelWorkPolicy.map(inputs: tasks) { task in
                    let samples = await store.samples(
                        series: task.series,
                        range: task.range,
                        maxPoints: task.maxPoints,
                        timeOffset: task.timeOffset,
                        valueScale: task.valueScale,
                        seriesName: task.seriesName
                    )
                    return (task.groupID, samples)
                }
                return mergeGroupPlotSamples(parts)
            }
        }

        guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
        plotGroupSamples = result
    }

    private func performStatisticsPlotSampleRefresh(generation: UInt, maxPoints: Int) async {
        guard statisticsActiveRange != nil else {
            guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
            statisticsGroupSamples = [:]
            return
        }

        let channelIDs = Set(plotGroups.flatMap(\.channelIDs))
        let displaySeries = await resolveDisplaySeriesSnapshot(for: channelIDs)
        let tasks = channelSampleTasks(
            groups: plotGroups,
            displaySeries: displaySeries,
            catalogByID: catalogByID,
            range: statisticsVisibleRange,
            maxPoints: maxPoints
        )

        let plotSamples: [UUID: [PlotSample]]
        if tasks.isEmpty {
            plotSamples = [:]
        } else {
            let store = plotSampleStore
            plotSamples = await ParallelWorkPolicy.measureAsync("performStatisticsPlotSampleRefresh") {
                let parts = await ParallelWorkPolicy.map(inputs: tasks) { task in
                    let samples = await store.samples(
                        series: task.series,
                        range: task.range,
                        maxPoints: task.maxPoints,
                        timeOffset: task.timeOffset,
                        valueScale: task.valueScale,
                        seriesName: task.seriesName
                    )
                    return (task.groupID, samples)
                }
                return mergeGroupPlotSamples(parts)
            }
        }

        guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
        statisticsGroupSamples = plotSamples
    }

    private func performStatisticsOutputRefresh(generation: UInt) async {
        guard let range = statisticsActiveRange else {
            guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
            lastStatisticsOutputKey = nil
            cachedStatisticsOutput = .empty
            return
        }

        let outputKey = StatisticsOutputKey(
            mode: statisticsIntervalMode,
            range: range,
            markerA: statisticsMarkerA,
            markerB: statisticsMarkerB,
            dataGeneration: sampleCacheGeneration
        )
        if outputKey == lastStatisticsOutputKey, cachedStatisticsOutput.activeRange == range {
            return
        }

        let groupsSnapshot = plotGroups
        let seriesSnapshot = await resolveDisplaySeriesSnapshot(for: Set(groupsSnapshot.flatMap(\.channelIDs)))
        let catalogSnapshot = catalogByID
        let derivedSnapshot = derivedRecords
        let geoSnapshot = geoSamples

        let groupedLines = await Task.detached(priority: .userInitiated) {
            Self.computeGroupedSignalStatistics(
                groups: groupsSnapshot,
                displaySeries: seriesSnapshot,
                catalogByID: catalogSnapshot,
                derivedRecords: derivedSnapshot,
                range: range
            )
        }.value

        let geoSummary = await Task.detached(priority: .userInitiated) {
            guard let geoSnapshot else { return nil as GeoSegmentSummary? }
            return GeoSegmentResolver.summary(samples: geoSnapshot, range: range)
        }.value

        guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
        lastStatisticsOutputKey = outputKey
        cachedStatisticsOutput = CachedStatisticsOutput(
            groupedLines: groupedLines,
            geoSummary: geoSummary,
            activeRange: range
        )
    }

    private func performStatisticsRefresh(generation: UInt, maxPoints: Int, includeOutput: Bool) async {
        await performStatisticsPlotSampleRefresh(generation: generation, maxPoints: maxPoints)
        if includeOutput {
            await performStatisticsOutputRefresh(generation: generation)
        }
    }

    private nonisolated static func computeGroupedSignalStatistics(
        groups: [PlotGroup],
        displaySeries: [UUID: DataSeries],
        catalogByID: [UUID: ChannelDescriptor],
        derivedRecords: [UUID: DerivedChannelRecord],
        range: VisibleTimeRange
    ) -> [(displayTitle: String, lines: [String])] {
        groups.compactMap { group in
            guard !group.channelIDs.isEmpty else { return nil }
            let lines = group.channelIDs.compactMap { channelID -> String? in
                guard let series = displaySeries[channelID],
                      let descriptor = catalogByID[channelID] else { return nil }
                let label = statisticsLabel(
                    for: descriptor,
                    channelID: channelID,
                    derivedRecords: derivedRecords
                )
                return SignalStatisticsCalculator.compute(
                    series: series,
                    range: range,
                    timeOffset: 0,
                    valueScale: 1,
                    label: label
                ).formattedLine
            }
            guard !lines.isEmpty else { return nil }
            let displayTitle = PlotGroupDisplayNaming.title(
                for: group,
                catalogByID: catalogByID,
                derivedRecords: derivedRecords
            )
            return (displayTitle: displayTitle, lines: lines)
        }
    }

    private nonisolated static func statisticsLabel(
        for descriptor: ChannelDescriptor,
        channelID: UUID,
        derivedRecords: [UUID: DerivedChannelRecord]
    ) -> String {
        if let derived = derivedRecords[channelID] {
            return derived.displayName
        }
        if ChannelColumnNaming.usesVelocityKPHDisplayName(descriptor.columnName) {
            return ChannelColumnNaming.unifiedVelocityKPHDisplayName
        }
        return descriptor.columnName
    }

    private func invalidatePlotSampleCache() {
        sampleCacheGeneration += 1
        lastStatisticsOutputKey = nil
        plotSampleRefreshTask?.cancel()
        statisticsRefreshTask?.cancel()
        fullPreviewRefreshTask?.cancel()
        plotGroupFullPreviewSamples = [:]
        statisticsGroupFullPreviewSamples = [:]
        timelinePreviewSamples = []
        statisticsTimelinePreviewSamples = []
        derivedSeriesCache.removeAll()
        displaySeriesCache.removeAll()
        Task { await plotSampleStore.invalidateAll() }
        scheduleTimelinePreviewCacheRefresh()
    }

    private func scheduleTimelinePreviewCacheRefresh() {
        timelinePreviewRefreshTask?.cancel()
        timelinePreviewRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await refreshTimelinePreviewCache()
        }
    }

    private func refreshTimelinePreviewCache() async {
        let generation = sampleCacheGeneration
        let mainSeries = previewSeries
        let statsSeries = statisticsPreviewSeries
        let maxPoints = Self.timelinePreviewMaxPoints

        let computed = await Task.detached(priority: .userInitiated) {
            Self.computeTimelinePreviewCaches(
                mainSeries: mainSeries,
                statisticsSeries: statsSeries,
                maxPoints: maxPoints
            )
        }.value

        guard !Task.isCancelled, generation == sampleCacheGeneration else { return }
        timelinePreviewSamples = computed.main
        statisticsTimelinePreviewSamples = computed.statistics
    }

    private nonisolated static func computeTimelinePreviewCaches(
        mainSeries: DataSeries?,
        statisticsSeries: DataSeries?,
        maxPoints: Int
    ) -> (main: [(time: Double, value: Double)], statistics: [(time: Double, value: Double)]) {
        let main: [(time: Double, value: Double)]
        if let mainSeries {
            main = SeriesSampler.downsample(
                times: mainSeries.times,
                values: mainSeries.values,
                maxPoints: maxPoints
            )
        } else {
            main = []
        }

        let statistics: [(time: Double, value: Double)]
        if let statisticsSeries {
            statistics = SeriesSampler.downsample(
                times: statisticsSeries.times,
                values: statisticsSeries.values,
                maxPoints: maxPoints
            )
        } else {
            statistics = []
        }

        return (main, statistics)
    }

    private func seriesNameForSampling(channelID: UUID, descriptor: ChannelDescriptor) -> String {
        if let derived = derivedRecords[channelID] {
            return derived.displayName
        }
        if ChannelColumnNaming.usesVelocityKPHDisplayName(descriptor.columnName) {
            return ChannelColumnNaming.unifiedVelocityKPHDisplayName
        }
        return descriptor.columnName
    }

    private func channelSampleTasks(
        groups: [PlotGroup],
        displaySeries: [UUID: DataSeries],
        catalogByID: [UUID: ChannelDescriptor],
        range: VisibleTimeRange,
        maxPoints: Int
    ) -> [ChannelSampleTask] {
        var tasks: [ChannelSampleTask] = []
        for group in groups where !group.channelIDs.isEmpty {
            for channelID in group.channelIDs {
                guard let series = displaySeries[channelID],
                      let descriptor = catalogByID[channelID] else { continue }
                tasks.append(
                    ChannelSampleTask(
                        groupID: group.id,
                        series: series,
                        range: range,
                        maxPoints: maxPoints,
                        timeOffset: 0,
                        valueScale: 1,
                        seriesName: seriesNameForSampling(channelID: channelID, descriptor: descriptor)
                    )
                )
            }
        }
        return tasks
    }

    private func fullPreviewChannelTasks(
        groups: [PlotGroup],
        displaySeries: [UUID: DataSeries],
        catalogByID: [UUID: ChannelDescriptor],
        plotRange: VisibleTimeRange,
        statisticsRange: VisibleTimeRange
    ) -> [FullPreviewChannelTask] {
        var tasks: [FullPreviewChannelTask] = []
        for group in groups where !group.channelIDs.isEmpty {
            for channelID in group.channelIDs {
                guard let series = displaySeries[channelID],
                      let descriptor = catalogByID[channelID] else { continue }
                let name = seriesNameForSampling(channelID: channelID, descriptor: descriptor)
                tasks.append(
                    FullPreviewChannelTask(
                        groupID: group.id,
                        isStatistics: false,
                        series: series,
                        range: plotRange,
                        timeOffset: 0,
                        valueScale: 1,
                        seriesName: name
                    )
                )
                tasks.append(
                    FullPreviewChannelTask(
                        groupID: group.id,
                        isStatistics: true,
                        series: series,
                        range: statisticsRange,
                        timeOffset: 0,
                        valueScale: 1,
                        seriesName: name
                    )
                )
            }
        }
        return tasks
    }

    private func mergeGroupPlotSamples(_ parts: [(UUID, [PlotSample])]) -> [UUID: [PlotSample]] {
        var merged: [UUID: [PlotSample]] = [:]
        for (groupID, samples) in parts {
            merged[groupID, default: []] += samples
        }
        return merged
    }

    private func mergeFullPreviewSamples(
        _ parts: [(UUID, Bool, [PlotSample])]
    ) -> (plot: [UUID: [PlotSample]], statistics: [UUID: [PlotSample]]) {
        var plot: [UUID: [PlotSample]] = [:]
        var statistics: [UUID: [PlotSample]] = [:]
        for (groupID, isStatistics, samples) in parts {
            if isStatistics {
                statistics[groupID, default: []] += samples
            } else {
                plot[groupID, default: []] += samples
            }
        }
        return (plot, statistics)
    }

    private func replaceSecurityScopedURL(old: URL?, new: URL) {
        if let old, old.standardizedFileURL != new.standardizedFileURL {
            stopAccessingSecurityScopedResource(old)
        }
        guard old?.standardizedFileURL != new.standardizedFileURL else { return }
        if new.startAccessingSecurityScopedResource() {
            if !securityScopedURLs.contains(where: { $0.standardizedFileURL == new.standardizedFileURL }) {
                securityScopedURLs.append(new)
            }
        }
    }

    private func stopAccessingSecurityScopedResource(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
        securityScopedURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
    }

    private func resolvedCandidateIDsToAdd(from ids: [UUID]) -> [UUID] {
        let visibleCandidateIDs = Set(availableCandidates.map(\.id))
        var seen = Set(selectedChannelIDs)
        var resolved: [UUID] = []
        for id in ids where visibleCandidateIDs.contains(id) && !seen.contains(id) {
            resolved.append(id)
            seen.insert(id)
        }
        return resolved
    }

    private func pruneEmptyPlotGroups() {
        plotGroups.removeAll { $0.channelIDs.isEmpty }
        if let active = activeGroupID,
           !plotGroups.contains(where: { $0.id == active }) {
            activeGroupID = plotGroups.last?.id
        }
    }

    private func dissolveSingleSignalGroups() {
        for index in plotGroups.indices where plotGroups[index].channelIDs.count == 1 {
            plotGroups[index].name = ""
        }
        if let active = activeGroupID,
           let activeGroup = plotGroups.first(where: { $0.id == active }),
           activeGroup.channelIDs.count == 1 {
            activeGroupID = plotGroups.first(where: { $0.channelIDs.count >= 2 })?.id
        }
    }

    private func assignToNewGroup(_ ids: [UUID]) {
        for id in ids {
            for index in plotGroups.indices {
                plotGroups[index].channelIDs.removeAll { $0 == id }
            }
        }
        let group = PlotGroup(name: defaultMergedGroupName(for: ids), channelIDs: ids)
        plotGroups.append(group)
        activeGroupID = group.id
        syncSelectedChannelIDsFromPlotGroups()
        pruneEmptyPlotGroups()
        invalidatePlotSampleCache()
        schedulePlotSampleRefresh()
        scheduleStatisticsRefresh()
    }

    private func defaultMergedGroupName(for ids: [UUID]) -> String {
        if ids.count == 1 {
            return ""
        }
        let names = ids.compactMap { catalogByID[$0].map { friendlyName(for: $0) } }
        guard !names.isEmpty else {
            return "分组 \(plotGroups.count + 1)"
        }
        if let inferred = ChannelGroupNaming.inferredGroupName(from: names) {
            return inferred
        }
        if Set(names).count == 1, let single = names.first {
            return single
        }
        return joinedGroupName(from: names, totalCount: ids.count)
    }

    private func joinedGroupName(from names: [String], totalCount: Int) -> String {
        let preview = names.prefix(3)
        let joined = preview.joined(separator: "、")
        if totalCount > 3 {
            return "\(joined) 等\(totalCount)项"
        }
        return joined
    }

    private func applyInferredGroupNameIfAppropriate(for groupID: UUID) {
        guard let groupIndex = plotGroups.firstIndex(where: { $0.id == groupID }),
              plotGroups[groupIndex].channelIDs.count >= 2 else { return }

        let names = plotGroups[groupIndex].channelIDs.compactMap { catalogByID[$0].map { friendlyName(for: $0) } }
        guard names.count >= 2 else { return }

        let currentName = plotGroups[groupIndex].name
        let legacyJoined = joinedGroupName(from: names, totalCount: names.count)
        guard names.contains(currentName) || currentName == legacyJoined else { return }

        if let inferred = ChannelGroupNaming.inferredGroupName(from: names) {
            plotGroups[groupIndex].name = inferred
        } else if Set(names).count == 1, let single = names.first {
            plotGroups[groupIndex].name = single
        }
    }

    private func refreshLoadedSeriesAndRange(
        continuesLoadingSession: Bool = false,
        startingPhaseIndex: Int? = nil
    ) async {
        isLoading = true
        if continuesLoadingSession {
            if let startingPhaseIndex {
                loadingProgressEnterPhase(at: startingPhaseIndex)
            }
        } else {
            loadingProgress = LoadingProgressState(phaseLabel: ImportDurationEstimator.importingFileLabel, fraction: 0)
            let phases = ImportDurationEstimator.seriesLoadPhases(
                dataFileURL: dataFileURL,
                selectedChannelCount: selectedChannelIDs.count
            )
            beginLoadingProgress(phases: phases)
            loadingProgressEnterPhase(at: 0)
        }

        defer {
            finishLoadingProgress()
            isLoading = false
        }

        var updated: [UUID: DataSeries] = [:]
        var pending: [(UUID, ChannelDescriptor)] = []

        for channelID in selectedChannelIDs {
            guard let descriptor = catalogByID[channelID] else { continue }
            if derivedRecords[channelID] != nil { continue }
            if let cached = loadedSeries[channelID], cached.descriptor.id == descriptor.id {
                updated[channelID] = cached
            } else {
                pending.append((channelID, descriptor))
            }
        }

        if !pending.isEmpty {
            updateSeriesLoadingProgress(loaded: 0, total: pending.count)
            let total = pending.count
            let loaded = await loadSeriesConcurrently(pending) { loadedCount in
                self.updateSeriesLoadingProgress(loaded: loadedCount, total: total)
            }
            updateSeriesLoadingProgress(loaded: pending.count, total: pending.count)
            if let firstError = loaded.firstError {
                errorMessage = firstError
            }
            for (channelID, series) in loaded.seriesByID {
                updated[channelID] = series
            }
        }

        if continuesLoadingSession, let startingPhaseIndex {
            loadingProgressCompletePhase(at: startingPhaseIndex)
        } else if let phases = currentLoadingPhases(),
                  let seriesPhaseIndex = phases.firstIndex(where: { $0.id == "seriesLoad" }) {
            loadingProgressCompletePhase(at: seriesPhaseIndex)
        }

        loadedSeries = updated

        if let global = SeriesSampler.globalRange(for: Array(updated.values), timeOffsetFor: { _ in 0 }) {
            fullRange = global
            statisticsFullRange = global
            if visibleRange.start < global.start || visibleRange.end > global.end || visibleRange.length <= 0 {
                let end = min(global.end, global.start + max(60, global.length * 0.2))
                visibleRange = VisibleTimeRange(start: global.start, end: end)
            }
        }
        invalidatePlotSampleCache()
        refreshFullPreviewSamples()
        refreshPlotSamplesNow()
        refreshStatisticsNow()
        scheduleTimelinePreviewCacheRefresh()
    }

    private struct ConcurrentSeriesLoadResult {
        var seriesByID: [UUID: DataSeries]
        var firstError: String?
    }

    private func loadSeriesConcurrently(
        _ pending: [(UUID, ChannelDescriptor)],
        onProgress: ((Int) -> Void)? = nil
    ) async -> ConcurrentSeriesLoadResult {
        guard !pending.isEmpty else { return ConcurrentSeriesLoadResult(seriesByID: [:], firstError: nil) }
        guard let fileURL = dataFileURL else {
            return ConcurrentSeriesLoadResult(
                seriesByID: [:],
                firstError: LoadError.missingDataFile.localizedDescription
            )
        }

        var seriesByID: [UUID: DataSeries] = [:]
        var firstError: String?

        do {
            let indices = pending.map(\.1.columnIndex)
            let loaded = try await Task.detached {
                try TabularTextParser.loadColumns(from: fileURL, columnIndices: indices)
            }.value
            for (item, series) in zip(pending, loaded) {
                seriesByID[item.0] = series
            }
            onProgress?(pending.count)
        } catch {
            firstError = error.localizedDescription
        }

        return ConcurrentSeriesLoadResult(seriesByID: seriesByID, firstError: firstError)
    }

    private func loadSeries(for descriptor: ChannelDescriptor) async throws -> DataSeries {
        let result = await loadSeriesConcurrently([(descriptor.id, descriptor)])
        if let series = result.seriesByID[descriptor.id] {
            return series
        }
        if let firstError = result.firstError {
            throw LoadError.loadFailed(firstError)
        }
        throw LoadError.seriesUnavailable
    }

    enum LoadError: LocalizedError {
        case missingDataFile
        case loadFailed(String)
        case seriesUnavailable

        var errorDescription: String? {
            switch self {
            case .missingDataFile: "未打开数据文件"
            case .loadFailed(let message): message
            case .seriesUnavailable: "无法加载信号数据"
            }
        }
    }

    private var activeLoadingPhases: [LoadingPhase] = []

    private func beginLoadingProgress(phases: [LoadingPhase]) {
        activeLoadingPhases = phases
        loadingProgressSimulator.onStateChange = { [weak self] state in
            self?.loadingProgress = state
        }
        loadingProgressSimulator.begin(phases: phases)
        loadingProgress = loadingProgressSimulator.state
    }

    private func loadingProgressEnterPhase(at index: Int, labelOverride: String? = nil) {
        loadingProgressSimulator.enterPhase(at: index, labelOverride: labelOverride)
        loadingProgress = loadingProgressSimulator.state
    }

    private func loadingProgressCompletePhase(at index: Int) {
        loadingProgressSimulator.completePhase(at: index)
        loadingProgress = loadingProgressSimulator.state
    }

    private func finishLoadingProgress() {
        loadingProgressSimulator.onStateChange = nil
        loadingProgressSimulator.finish()
        loadingProgress = nil
        activeLoadingPhases = []
    }

    private func currentLoadingPhases() -> [LoadingPhase]? {
        activeLoadingPhases.isEmpty ? nil : activeLoadingPhases
    }

    private func updateSeriesLoadingProgress(loaded: Int, total: Int) {
        guard total > 0 else { return }
        if activeLoadingPhases.contains(where: { $0.id == "seriesLoad" }) {
            loadingProgressSimulator.updateSeriesProgress(loaded: loaded, total: total)
            loadingProgress = loadingProgressSimulator.state
        } else if var progress = loadingProgress {
            progress.phaseLabel = LoadingProgressSimulator.seriesLoadingLabel(loaded: loaded, total: total)
            loadingProgress = progress
        }
    }
}

