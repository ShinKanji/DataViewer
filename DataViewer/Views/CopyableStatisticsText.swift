import SwiftUI
import UIKit

enum StatisticsClipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

struct CopyableStatisticsText: View {
    let text: String
    var font: Font = .callout.monospaced()

    var body: some View {
        Text(text)
            .font(font)
            .textSelection(.enabled)
            .contextMenu {
                Button(String(localized: "复制", comment: "Copy to clipboard button"), systemImage: "doc.on.doc") {
                    StatisticsClipboard.copy(text)
                }
            }
    }
}

enum StatisticsExportFormatter {
    static func intervalSummaryLines(
        mode: StatisticsIntervalMode,
        start: StatisticsTimeEndpoint,
        end: StatisticsTimeEndpoint
    ) -> [String] {
        [
            intervalModeLine(mode: mode, start: start, end: end),
            statisticsRangeLine(start: start, end: end),
        ]
    }

    static func intervalModeLine(
        mode: StatisticsIntervalMode,
        start: StatisticsTimeEndpoint,
        end: StatisticsTimeEndpoint
    ) -> String {
        switch mode {
        case .currentWindow:
            return String(localized: "区间模式: 当前时间窗", comment: "Current window mode label")
        case .abInterval:
            let delta = end.seconds - start.seconds
            return String(format: String(localized: "区间模式: A/B 区间（Δt = %.2fs）", comment: "AB interval mode label with delta"), delta)
        }
    }

    static func statisticsRangeLine(start: StatisticsTimeEndpoint, end: StatisticsTimeEndpoint) -> String {
        let startData = formatDataTimeSeconds(start.seconds)
        let endData = formatDataTimeSeconds(end.seconds)
        var line = String(localized: "统计范围", comment: "Statistics range label")
        line += ": \(startData) - \(endData)"
        if start.clockTime != nil || end.clockTime != nil {
            let startClock = start.clockTime?.formatted ?? "—"
            let endClock = end.clockTime?.formatted ?? "—"
            line += "（\(startClock) - \(endClock)）"
        }
        return line
    }

    static func text(
        groupedLines: [(displayTitle: String, lines: [String])],
        geoSummary: GeoSegmentSummary?,
        headerLines: [String] = []
    ) -> String {
        var lines = headerLines.filter { !$0.isEmpty }
        if let geoSummary, geoSummary.isAvailable {
            lines.append(contentsOf: geoLines(from: geoSummary))
        }
        for item in groupedLines {
            if !item.displayTitle.isEmpty {
                lines.append("[\(item.displayTitle)]")
            }
            lines.append(contentsOf: item.lines)
        }
        return lines.joined(separator: "\n")
    }

    static func signalSectionText(
        groupedLines: [(displayTitle: String, lines: [String])]
    ) -> String {
        text(groupedLines: groupedLines, geoSummary: nil, headerLines: [])
    }

    static func geoSectionText(from summary: GeoSegmentSummary) -> String {
        geoLines(from: summary).joined(separator: "\n")
    }

    static func geoLines(from summary: GeoSegmentSummary) -> [String] {
        var lines: [String] = []
        if let lat = summary.startLatitude, let lon = summary.startLongitude {
            lines.append(String(format: String(localized: "起点: lat=%.6g°  lon=%.6g°", comment: "Start point geo coordinates"), lat, lon))
        }
        if let lat = summary.endLatitude, let lon = summary.endLongitude {
            lines.append(String(format: String(localized: "终点: lat=%.6g°  lon=%.6g°", comment: "End point geo coordinates"), lat, lon))
        }
        if let meters = summary.haversineMeters {
            lines.append(String(format: String(localized: "路径长度: %.2f m", comment: "Segment length in meters"), meters))
        }
        return lines
    }

    private static func formatDataTimeSeconds(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }
}
