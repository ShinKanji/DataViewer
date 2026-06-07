import Foundation

nonisolated struct LoadingPhase: Equatable, Sendable {
    let id: String
    let label: String
    let weight: Double
    let estimatedDuration: TimeInterval
}

nonisolated enum ImportDurationEstimator {
    static let importingFileLabel = String(localized: "正在导入文件", comment: "Import file progress label")
    static let seriesLoadingLabel = String(localized: "正在加载曲线数据", comment: "Series loading progress label")

    static let catalogDuration: TimeInterval = 0.03
    static let clockTimeBaseSeconds: TimeInterval = 0.05
    static let clockTimePerMegabyte: TimeInterval = 0.04

    static func phases(dataFileURL: URL?, selectedChannelCount: Int) -> [LoadingPhase] {
        weightedPhases(
            candidates: catalogPhase(dataFileURL: dataFileURL)
                + clockTimePhase(dataFileURL: dataFileURL)
                + seriesPhase(dataFileURL: dataFileURL, selectedChannelCount: selectedChannelCount)
        )
    }

    static func seriesLoadPhases(dataFileURL: URL?, selectedChannelCount: Int) -> [LoadingPhase] {
        let channelCount = max(selectedChannelCount, 1)
        let duration = estimatedSeriesLoadDuration(
            dataFileURL: dataFileURL,
            selectedChannelCount: channelCount
        )
        return [
            LoadingPhase(
                id: "seriesLoad",
                label: seriesLoadingLabel,
                weight: 1,
                estimatedDuration: duration
            )
        ]
    }

    static func estimatedClockTimeParseDuration(fileSizeMegabytes sizeMB: Double) -> TimeInterval {
        max(0.08, clockTimeBaseSeconds + clockTimePerMegabyte * sizeMB)
    }

    static func totalEstimatedDuration(for phases: [LoadingPhase]) -> TimeInterval {
        phases.reduce(0) { $0 + $1.estimatedDuration }
    }

    private static func catalogPhase(dataFileURL: URL?) -> [(LoadingPhase, TimeInterval)] {
        guard dataFileURL != nil else { return [] }
        let duration = max(0.02, catalogDuration)
        return [(
            LoadingPhase(
                id: "catalog",
                label: importingFileLabel,
                weight: 0,
                estimatedDuration: duration
            ),
            duration
        )]
    }

    private static func clockTimePhase(dataFileURL: URL?) -> [(LoadingPhase, TimeInterval)] {
        guard let dataFileURL else { return [] }
        let sizeMB = fileSizeMegabytes(at: dataFileURL)
        let duration = estimatedClockTimeParseDuration(fileSizeMegabytes: sizeMB)
        return [(
            LoadingPhase(
                id: "clockTime",
                label: importingFileLabel,
                weight: 0,
                estimatedDuration: duration
            ),
            duration
        )]
    }

    private static func seriesPhase(
        dataFileURL: URL?,
        selectedChannelCount: Int
    ) -> [(LoadingPhase, TimeInterval)] {
        guard selectedChannelCount > 0 else { return [] }
        let duration = estimatedSeriesLoadDuration(
            dataFileURL: dataFileURL,
            selectedChannelCount: selectedChannelCount
        )
        return [(
            LoadingPhase(
                id: "seriesLoad",
                label: seriesLoadingLabel,
                weight: 0,
                estimatedDuration: duration
            ),
            duration
        )]
    }

    private static func weightedPhases(candidates: [(LoadingPhase, TimeInterval)]) -> [LoadingPhase] {
        guard !candidates.isEmpty else {
            return [
                LoadingPhase(
                    id: "generic",
                    label: importingFileLabel,
                    weight: 1,
                    estimatedDuration: 0.15
                )
            ]
        }

        let totalDuration = candidates.reduce(0) { $0 + $1.1 }
        guard totalDuration > 0 else { return candidates.map(\.0) }

        return candidates.map { phase, duration in
            LoadingPhase(
                id: phase.id,
                label: phase.label,
                weight: duration / totalDuration,
                estimatedDuration: duration
            )
        }
    }

    private static func estimatedSeriesLoadDuration(
        dataFileURL: URL?,
        selectedChannelCount: Int
    ) -> TimeInterval {
        let fileMB = fileSizeMegabytes(at: dataFileURL)
        return max(0.2, 0.2 + Double(selectedChannelCount) * 0.04 + fileMB * 0.01)
    }

    private static func fileSizeMegabytes(at url: URL?) -> Double {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else {
            return 0
        }
        return Double(bytes) / (1_024 * 1_024)
    }
}
