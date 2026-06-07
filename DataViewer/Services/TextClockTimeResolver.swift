import Foundation

nonisolated struct ClockTime: Equatable, Sendable {
    let hour: Int
    let minute: Int
    let second: Int

    var formatted: String {
        String(format: "%02d:%02d:%02d", hour, minute, second)
    }
}

nonisolated struct StatisticsTimeEndpoint: Equatable, Sendable {
    let seconds: Double
    let clockTime: ClockTime?
}

nonisolated struct TextClockTimeTable: Sendable {
    let times: [Double]
    let hours: [Double]
    let minutes: [Double]
    let seconds: [Double]

    func clockTime(atDisplaySeconds displayTime: Double) -> ClockTime? {
        guard !times.isEmpty else { return nil }
        let index = nearestIndex(for: displayTime)
        let hour = Int(hours[index].rounded())
        let minute = Int(minutes[index].rounded())
        let second = Int(seconds[index].rounded())
        return ClockTime(hour: hour, minute: minute, second: second)
    }

    private func nearestIndex(for target: Double) -> Int {
        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low > 0 {
            let previousDelta = abs(times[low - 1] - target)
            let currentDelta = abs(times[low] - target)
            if previousDelta < currentDelta {
                return low - 1
            }
        }
        return low
    }
}

nonisolated enum TextClockTimeResolver {
    static func load(from url: URL) throws -> TextClockTimeTable? {
        let headerLine = try TabularTextParser.readFirstLineForBenchmark(from: url)
        let headers = TabularTextParser.splitColumns(headerLine)
        guard let indices = clockTimeColumnIndices(in: headers) else { return nil }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        var headerConsumed = false
        var times: [Double] = []
        var hours: [Double] = []
        var minutes: [Double] = []
        var seconds: [Double] = []
        times.reserveCapacity(8192)
        hours.reserveCapacity(8192)
        minutes.reserveCapacity(8192)
        seconds.reserveCapacity(8192)

        while true {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                if buffer.first == 0x0D {
                    buffer.removeFirst()
                }
                guard let line = decodeLine(lineData) else { continue }

                if !headerConsumed {
                    headerConsumed = true
                    continue
                }

                let cols = TabularTextParser.splitColumns(line)
                guard indices.time < cols.count,
                      indices.hour < cols.count,
                      indices.minute < cols.count,
                      indices.second < cols.count,
                      let time = Double(cols[indices.time]),
                      let hour = Double(cols[indices.hour]),
                      let minute = Double(cols[indices.minute]),
                      let second = Double(cols[indices.second]) else { continue }
                times.append(time)
                hours.append(hour)
                minutes.append(minute)
                seconds.append(second)
            }
        }

        guard !times.isEmpty else { return nil }
        return TextClockTimeTable(
            times: times,
            hours: hours,
            minutes: minutes,
            seconds: seconds
        )
    }

    static func clockTimeColumnIndices(in headers: [String]) -> (time: Int, hour: Int, minute: Int, second: Int)? {
        var timeIndex: Int?
        var hourIndex: Int?
        var minuteIndex: Int?
        var secondIndex: Int?

        for (index, rawName) in headers.enumerated() {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if ChannelColumnNaming.isTimeColumn(name) {
                timeIndex = index
                continue
            }
            guard name.contains("时钟") || name.contains("北京时间") else { continue }
            if matchesClockComponent(name, suffixes: ["-时", "时", "Hour", "HOUR"]) {
                hourIndex = index
            } else if matchesClockComponent(name, suffixes: ["-分", "分", "Minute", "MINUTE"]) {
                minuteIndex = index
            } else if matchesClockComponent(name, suffixes: ["-秒", "秒", "Second", "SECOND"]) {
                secondIndex = index
            }
        }

        guard let timeIndex, let hourIndex, let minuteIndex, let secondIndex else { return nil }
        return (timeIndex, hourIndex, minuteIndex, secondIndex)
    }

    private static func matchesClockComponent(_ name: String, suffixes: [String]) -> Bool {
        suffixes.contains { name.hasSuffix($0) }
    }

    private static func decodeLine(_ data: Data.SubSequence) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let gb = String(data: data, encoding: .gb18030) { return gb }
        return nil
    }
}
