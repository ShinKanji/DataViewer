import Accelerate
import Foundation

nonisolated enum SignalStatisticsCalculator {
    static func compute(
        series: DataSeries,
        range: VisibleTimeRange,
        timeOffset: Double = 0,
        valueScale: Double = 1,
        label: String? = nil
    ) -> SignalStatistics {
        let scale = valueScale.isFinite ? valueScale : 1

        let adjustedStart = range.start - timeOffset
        let adjustedEnd = range.end - timeOffset
        let lo = SeriesSampler.lowerBound(in: series.times, value: adjustedStart)
        let hi = SeriesSampler.upperBound(in: series.times, value: adjustedEnd)
        guard lo < hi else {
            return SignalStatistics(
                max: nil, min: nil, mean: nil, variance: nil, std: nil,
                peakToPeak: nil, isAllNaN: true,
                formattedLine: "该信号: 全NaN"
            )
        }

        let slice = series.values[lo..<hi]
        var validValues = [Double]()
        validValues.reserveCapacity(slice.count)
        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude

        for v in slice {
            guard v.isFinite else { continue }
            let scaled = v * scale
            validValues.append(scaled)
            if scaled < minValue { minValue = scaled }
            if scaled > maxValue { maxValue = scaled }
        }

        guard !validValues.isEmpty, let minValue = minValue.isFinite ? minValue : nil, let maxValue = maxValue.isFinite ? maxValue : nil else {
            return SignalStatistics(
                max: nil, min: nil, mean: nil, variance: nil, std: nil,
                peakToPeak: nil, isAllNaN: true,
                formattedLine: "该信号: 全NaN"
            )
        }

        let count = validValues.count
        var mean = 0.0
        var stdDev = 0.0
        vDSP_normalizeD(validValues, 1, nil, 1, &mean, &stdDev, vDSP_Length(count))

        let variance = stdDev * stdDev
        let peakToPeak = maxValue - minValue

        let signalLabel = label ?? series.descriptor.columnName
        let line = String(
            format: "%@ max=%.6g min=%.6g mean=%.6g var=%.6g std=%.6g p2p=%.6g",
            signalLabel,
            maxValue,
            minValue,
            mean,
            variance,
            stdDev,
            peakToPeak
        )

        return SignalStatistics(
            max: maxValue,
            min: minValue,
            mean: mean,
            variance: variance,
            std: stdDev,
            peakToPeak: peakToPeak,
            isAllNaN: false,
            formattedLine: line
        )
    }
}
