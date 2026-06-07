import Foundation

nonisolated enum SeriesSampler {
    static func downsample(
        times: [Double],
        values: [Double],
        maxPoints: Int,
        timeOffset: Double = 0
    ) -> [(time: Double, value: Double)] {
        guard !times.isEmpty, maxPoints > 0 else { return [] }

        if timeOffset == 0 {
            guard times.count > maxPoints else {
                return zip(times, values).map { ($0, $1) }
            }
            return downsampleIndexed(times: times, values: values, lo: 0, hi: times.count, maxPoints: maxPoints, timeOffset: 0)
        }

        guard times.count > maxPoints else {
            return zip(times, values).map { ($0 + timeOffset, $1) }
        }
        return downsampleIndexed(times: times, values: values, lo: 0, hi: times.count, maxPoints: maxPoints, timeOffset: timeOffset)
    }

    static func samples(
        in range: VisibleTimeRange,
        from series: DataSeries,
        maxPoints: Int = 4_000,
        timeOffset: Double = 0,
        valueScale: Double = 1,
        seriesName: String? = nil,
        smoothingWindow: Int = 0
    ) -> [PlotSample] {
        guard !series.times.isEmpty else { return [] }

        let lo = lowerBound(in: series.times, value: range.start - timeOffset)
        let hi = upperBound(in: series.times, value: range.end - timeOffset)
        guard lo < hi else { return [] }

        let label = seriesName ?? series.descriptor.qualifiedName
        let downsampled = downsampleIndexed(
            times: series.times,
            values: series.values,
            lo: lo,
            hi: hi,
            maxPoints: maxPoints,
            timeOffset: timeOffset,
            valueScale: valueScale,
            smoothingWindow: smoothingWindow
        )
        return downsampled.map { PlotSample(time: $0.time, value: $0.value, seriesName: label) }
    }

    static func valueAtPlotTime(
        _ plotTime: Double,
        series: DataSeries,
        timeOffset: Double,
        valueScale: Double = 1
    ) -> Double? {
        guard valueScale.isFinite, !series.times.isEmpty, series.times.count == series.values.count else {
            return nil
        }

        let rawTime = plotTime - timeOffset
        guard let first = series.times.first, let last = series.times.last,
              rawTime >= first, rawTime <= last else {
            return nil
        }

        let index = lowerBound(in: series.times, value: rawTime)
        if index < series.times.count, series.times[index] == rawTime {
            let value = series.values[index]
            return value.isFinite ? value * valueScale : nil
        }
        if index == 0 {
            let value = series.values[0]
            return value.isFinite ? value * valueScale : nil
        }

        let i0 = index - 1
        let i1 = index
        let t0 = series.times[i0]
        let t1 = series.times[i1]
        let v0 = series.values[i0]
        let v1 = series.values[i1]
        guard t1 > t0 else {
            if v0.isFinite { return v0 * valueScale }
            if v1.isFinite { return v1 * valueScale }
            return nil
        }
        guard v0.isFinite, v1.isFinite else { return nil }
        let fraction = (rawTime - t0) / (t1 - t0)
        return (v0 + fraction * (v1 - v0)) * valueScale
    }

    private static func downsampleIndexed(
        times: [Double],
        values: [Double],
        lo: Int,
        hi: Int,
        maxPoints: Int,
        timeOffset: Double,
        valueScale: Double = 1,
        smoothingWindow: Int = 0
    ) -> [(time: Double, value: Double)] {
        let count = hi - lo
        guard count > 0, maxPoints > 0 else { return [] }
        let scale = valueScale.isFinite ? valueScale : 1

        if count <= maxPoints {
            var result: [(Double, Double)] = []
            result.reserveCapacity(count)
            for index in lo..<hi {
                let v = smoothingWindow > 1 ? smoothedValue(values: values, index: index, window: smoothingWindow) : values[index]
                result.append((times[index] + timeOffset, v * scale))
            }
            return result
        }

        if maxPoints == 1 {
            let v = smoothingWindow > 1 ? smoothedValue(values: values, index: hi - 1, window: smoothingWindow) : values[hi - 1]
            return [(times[hi - 1] + timeOffset, v * scale)]
        }
        if maxPoints == 2 {
            let v0 = smoothingWindow > 1 ? smoothedValue(values: values, index: lo, window: smoothingWindow) : values[lo]
            let v1 = smoothingWindow > 1 ? smoothedValue(values: values, index: hi - 1, window: smoothingWindow) : values[hi - 1]
            return [
                (times[lo] + timeOffset, v0 * scale),
                (times[hi - 1] + timeOffset, v1 * scale)
            ]
        }

        return downsampleLTTB(
            times: times, values: values, lo: lo, hi: hi,
            maxPoints: maxPoints, timeOffset: timeOffset, valueScale: scale,
            smoothingWindow: smoothingWindow
        )
    }

    private static func smoothedValue(values: [Double], index: Int, window: Int) -> Double {
        guard window > 1, index >= 0, index < values.count else { return values[index] }
        let half = window / 2
        let start = max(0, index - half)
        let end = min(values.count - 1, index + half)
        var sum = 0.0
        var count = 0
        for j in start...end {
            guard values[j].isFinite else { continue }
            sum += values[j]
            count += 1
        }
        return count > 0 ? sum / Double(count) : values[index]
    }

    private static func downsampleLTTB(
        times: [Double],
        values: [Double],
        lo: Int,
        hi: Int,
        maxPoints: Int,
        timeOffset: Double,
        valueScale: Double,
        smoothingWindow: Int = 0
    ) -> [(time: Double, value: Double)] {
        let count = hi - lo
        let bucketSize = Double(count - 2) / Double(maxPoints - 2)

        var result: [(Double, Double)] = []
        result.reserveCapacity(maxPoints)

        func v(_ i: Int, cache: inout [Int: Double]) -> Double {
            if let cached = cache[i] { return cached }
            let val = smoothingWindow > 1
                ? smoothedValue(values: values, index: i, window: smoothingWindow)
                : values[i]
            cache[i] = val
            return val
        }

        var bucketCache: [Int: Double] = [:]
        bucketCache.reserveCapacity(hi - lo)

        let firstTime = times[lo] + timeOffset
        let firstValue = v(lo, cache: &bucketCache) * valueScale
        result.append((firstTime, firstValue))
        var prev = result[0]

        for i in 1..<maxPoints - 1 {
            bucketCache.removeAll(keepingCapacity: true)

            let avgStart = lo + Int((Double(i) * bucketSize).rounded(.down)) + 1
            let avgEnd   = lo + Int((Double(i + 1) * bucketSize).rounded(.down)) + 1
            let clampedAvgEnd = min(max(avgEnd, avgStart + 1), hi)

            var avgTime = 0.0
            var avgValue = 0.0
            var avgCount = 0
            for j in avgStart..<clampedAvgEnd {
                let vj = v(j, cache: &bucketCache)
                guard vj.isFinite else { continue }
                avgTime += times[j]
                avgValue += vj
                avgCount += 1
            }
            if avgCount == 0 {
                let mid = (avgStart + clampedAvgEnd - 1) / 2
                avgTime = times[mid]
                avgValue = v(mid, cache: &bucketCache)
                avgCount = 1
            } else {
                avgTime /= Double(avgCount)
                avgValue /= Double(avgCount)
            }

            let rangeStart = lo + Int((Double(i - 1) * bucketSize).rounded(.down)) + 1
            let rangeEnd   = lo + Int((Double(i) * bucketSize).rounded(.down)) + 1
            let clampedRangeEnd = min(rangeEnd, hi)

            var bestIdx = rangeStart
            var bestArea = -1.0
            let prevTime = prev.0
            let prevVal  = prev.1

            for j in rangeStart..<clampedRangeEnd {
                let vj = v(j, cache: &bucketCache)
                guard vj.isFinite else { continue }
                let t = times[j]
                let area = abs((prevTime - avgTime) * (vj - prevVal)
                             - (prevTime - t) * (avgValue - prevVal))
                if area > bestArea {
                    bestArea = area
                    bestIdx = j
                }
            }

            let bestVal = v(bestIdx, cache: &bucketCache) * valueScale
            let pt = (times[bestIdx] + timeOffset, bestVal)
            result.append(pt)
            prev = pt
        }

        var lastCache: [Int: Double] = [:]
        result.append((times[hi - 1] + timeOffset, v(hi - 1, cache: &lastCache) * valueScale))

        return result
    }

    static func yRange(for samples: [PlotSample], in range: VisibleTimeRange) -> ClosedRange<Double> {
        var minValue: Double?
        var maxValue: Double?
        for sample in samples where sample.time >= range.start && sample.time <= range.end && sample.value.isFinite {
            minValue = minValue.map { min($0, sample.value) } ?? sample.value
            maxValue = maxValue.map { max($0, sample.value) } ?? sample.value
        }
        guard let minValue, let maxValue else {
            return 0...1
        }
        if minValue == maxValue {
            return (minValue - 1)...(maxValue + 1)
        }
        let padding = (maxValue - minValue) * 0.08
        return (minValue - padding)...(maxValue + padding)
    }

    static func globalRange(for seriesList: [DataSeries], timeOffsetFor: (DataSeries) -> Double = { _ in 0 }) -> VisibleTimeRange? {
        var starts: [Double] = []
        var ends: [Double] = []
        for series in seriesList {
            guard let first = series.times.first, let last = series.times.last else { continue }
            let offset = timeOffsetFor(series)
            starts.append(first + offset)
            ends.append(last + offset)
        }
        guard let minStart = starts.min(), let maxEnd = ends.max(), maxEnd > minStart else { return nil }
        return VisibleTimeRange(start: minStart, end: maxEnd)
    }

    static func lowerBound(in times: [Double], value: Double) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    static func upperBound(in times: [Double], value: Double) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if times[mid] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
