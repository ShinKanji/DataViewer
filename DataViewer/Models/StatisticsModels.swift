import Foundation

enum StatisticsIntervalMode: String, CaseIterable, Identifiable {
    case currentWindow
    case abInterval

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .currentWindow:
            String(localized: "当前时间窗", comment: "Current window interval mode")
        case .abInterval:
            String(localized: "A/B 区间", comment: "A/B interval mode")
        }
    }

    var segmentedTitle: String {
        switch self {
        case .currentWindow:
            String(localized: "时间窗", comment: "Short current window mode label for segmented control")
        case .abInterval:
            String(localized: "A/B", comment: "Short A/B interval mode label for segmented control")
        }
    }
}

enum GeoLoadState: Equatable {
    case idle
    case loading
    case unavailable
    case ready
}

nonisolated struct SignalStatistics: Equatable {
    var max, min, mean, variance, std, peakToPeak: Double?
    var isAllNaN: Bool
    var formattedLine: String
}

nonisolated struct GeoCoordinateSample: Equatable {
    var time: Double
    var latitude: Double
    var longitude: Double
}

nonisolated struct GeoSegmentSummary: Equatable {
    var startLatitude, startLongitude: Double?
    var endLatitude, endLongitude: Double?
    var haversineMeters: Double?
    var isAvailable: Bool
}

struct CachedStatisticsOutput {
    var groupedLines: [(displayTitle: String, lines: [String])]
    var geoSummary: GeoSegmentSummary?
    var activeRange: VisibleTimeRange?

    static let empty = CachedStatisticsOutput(
        groupedLines: [],
        geoSummary: nil,
        activeRange: nil
    )
}
