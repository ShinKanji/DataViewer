import Accelerate
import Foundation

nonisolated enum SignalTransform {
    static func derivative(times: [Double], values: [Double]) -> [Double] {
        let count = min(times.count, values.count)
        guard count > 0 else { return [] }
        if count == 1 { return [0] }

        var result = [Double](repeating: 0, count: count)

        let dt0 = times[1] - times[0]
        if dt0 != 0, values[0].isFinite, values[1].isFinite {
            result[0] = (values[1] - values[0]) / dt0
        } else {
            result[0] = .nan
        }

        let dtEnd = times[count - 1] - times[count - 2]
        if dtEnd != 0, values[count - 1].isFinite, values[count - 2].isFinite {
            result[count - 1] = (values[count - 1] - values[count - 2]) / dtEnd
        } else {
            result[count - 1] = .nan
        }

        if count > 2 {
            let innerCount = count - 2
            var dt = [Double](repeating: 0, count: innerCount)
            var dv = [Double](repeating: 0, count: innerCount)
            for i in 1..<count - 1 {
                let denominator = times[i + 1] - times[i - 1]
                guard denominator != 0, values[i + 1].isFinite, values[i - 1].isFinite else {
                    dv[i - 1] = .nan
                    dt[i - 1] = 1
                    continue
                }
                dv[i - 1] = values[i + 1] - values[i - 1]
                dt[i - 1] = denominator
            }
            var divResult = [Double](repeating: 0, count: innerCount)
            vDSP_vdivD(dt, 1, dv, 1, &divResult, 1, vDSP_Length(innerCount))
            for i in 0..<innerCount {
                result[i + 1] = divResult[i]
            }
        }

        return result
    }

    static func integrate(times: [Double], values: [Double]) -> [Double] {
        let count = min(times.count, values.count)
        guard count > 0 else { return [] }
        if count == 1 { return [0] }

        let n = count - 1
        var increments = [Double](repeating: 0, count: n)
        for i in 1...n {
            let dt = times[i] - times[i - 1]
            let v0 = values[i - 1]
            let v1 = values[i]
            guard dt.isFinite, v0.isFinite, v1.isFinite else {
                increments[i - 1] = 0
                continue
            }
            increments[i - 1] = 0.5 * (v0 + v1) * dt
        }

        var result = [Double](repeating: 0, count: count)
        for i in 0..<n {
            result[i + 1] = result[i] + increments[i]
        }

        return result
    }

    static func movingAverage(values: [Double], windowSamples: Int) -> [Double] {
        guard windowSamples >= 1 else { return [] }
        guard !values.isEmpty else { return [] }

        var result = [Double](repeating: .nan, count: values.count)
        var runningSum = 0.0
        var runningCount = 0

        for index in values.indices {
            let entering = values[index]
            if entering.isFinite {
                runningSum += entering
                runningCount += 1
            }

            let removeIndex = index - windowSamples
            if removeIndex >= 0 {
                let leaving = values[removeIndex]
                if leaving.isFinite {
                    runningSum -= leaving
                    runningCount -= 1
                }
            }

            if runningCount > 0 {
                result[index] = runningSum / Double(runningCount)
            }
        }

        return result
    }

    static func estimateJumpThreshold(
        values: [Double],
        sigmaMultiplier: Double = 5.0
    ) -> Double? {
        let diffs = consecutiveAbsoluteDifferences(values)
        guard diffs.count >= 2 else { return nil }
        let maxDiff = diffs.max() ?? 0
        let minDiff = diffs.min() ?? 0
        guard maxDiff > 0 else { return nil }
        if maxDiff <= minDiff + 1e-12 * max(maxDiff, 1) {
            return nil
        }

        let zeroFraction = Double(diffs.filter { $0 <= 1e-12 * max(maxDiff, 1) }.count) / Double(diffs.count)
        if zeroFraction >= 0.5 {
            return maxDiff * 0.6
        }

        guard let medianDiff = medianValue(diffs) else { return nil }
        let madValue = medianAbsoluteDeviation(diffs, median: medianDiff)
        let scale = max(medianDiff, 1e-12)

        if madValue.isFinite, madValue > 1e-12 * scale {
            let threshold = medianDiff + sigmaMultiplier * 1.4826 * madValue
            return threshold.isFinite && threshold > 0 ? threshold : nil
        }

        return nil
    }

    static func removeJumpPoints(
        values: [Double],
        threshold: Double? = nil
    ) -> (values: [Double], thresholdUsed: Double?, removedCount: Int) {
        guard !values.isEmpty else { return (values, threshold, 0) }

        let effectiveThreshold: Double?
        if let threshold, threshold.isFinite, threshold > 0 {
            effectiveThreshold = threshold
        } else {
            effectiveThreshold = estimateJumpThreshold(values: values)
        }

        guard let thresholdUsed = effectiveThreshold else {
            return (values, nil, 0)
        }

        var marked = values
        var removedCount = 0
        for index in values.indices {
            guard isJumpPoint(at: index, values: values, threshold: thresholdUsed) else { continue }
            if marked[index].isFinite {
                marked[index] = .nan
                removedCount += 1
            }
        }

        let cleaned = linearlyInterpolateNaNRuns(marked)
        return (cleaned, thresholdUsed, removedCount)
    }

    static func unwrapHeadingAngle(values: [Double], period: Double = 360) -> [Double] {
        guard !values.isEmpty else { return [] }
        var result = values
        var lastFiniteIndex: Int?

        for index in values.indices {
            guard values[index].isFinite else {
                result[index] = .nan
                continue
            }
            guard let previousIndex = lastFiniteIndex else {
                result[index] = values[index]
                lastFiniteIndex = index
                continue
            }
            let delta = shortestAngularDelta(
                from: values[previousIndex],
                to: values[index],
                period: period
            )
            result[index] = result[previousIndex] + delta
            lastFiniteIndex = index
        }

        return result
    }

    static func apply(
        op: DerivedOpKind,
        times: [Double],
        values: [Double],
        windowSamples: Int? = nil
    ) -> [Double] {
        switch op {
        case .deriv:
            return derivative(times: times, values: values)
        case .integ:
            return integrate(times: times, values: values)
        case .movmean:
            guard let window = windowSamples, window >= 1 else { return [] }
            return movingAverage(values: values, windowSamples: window)
        }
    }

    private static func shortestAngularDelta(from: Double, to: Double, period: Double) -> Double {
        let halfPeriod = period / 2
        var delta = (to - from).truncatingRemainder(dividingBy: period)
        if delta > halfPeriod {
            delta -= period
        } else if delta <= -halfPeriod {
            delta += period
        }
        return delta
    }

    private static func consecutiveAbsoluteDifferences(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return [] }
        var diffs: [Double] = []
        diffs.reserveCapacity(values.count - 1)
        for index in 1..<values.count {
            let previous = values[index - 1]
            let current = values[index]
            guard previous.isFinite, current.isFinite else { continue }
            diffs.append(abs(current - previous))
        }
        return diffs
    }

    private static func medianValue(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func medianAbsoluteDeviation(_ values: [Double], median baseline: Double) -> Double {
        let deviations = values.map { abs($0 - baseline) }
        return medianValue(deviations) ?? 0
    }

    private static func absoluteDifference(_ lhs: Double, _ rhs: Double) -> Double? {
        guard lhs.isFinite, rhs.isFinite else { return nil }
        return abs(rhs - lhs)
    }

    private static func isJumpPoint(at index: Int, values: [Double], threshold: Double) -> Bool {
        let count = values.count
        guard count > 0, values[index].isFinite else { return false }

        let diffBefore = index > 0
            ? absoluteDifference(values[index - 1], values[index])
            : nil
        let diffAfter = index < count - 1
            ? absoluteDifference(values[index], values[index + 1])
            : nil

        if let diffBefore, let diffAfter, diffBefore > threshold, diffAfter > threshold {
            return true
        }

        if index == 0, let diffAfter, diffAfter > threshold {
            if count < 3 { return true }
            if let nextDiff = absoluteDifference(values[1], values[2]), nextDiff <= threshold {
                return true
            }
        }

        if index == count - 1, let diffBefore, diffBefore > threshold {
            if count < 3 { return true }
            if let previousDiff = absoluteDifference(values[count - 3], values[count - 2]),
               previousDiff <= threshold {
                return true
            }
        }

        return false
    }

    private static func linearlyInterpolateNaNRuns(_ values: [Double]) -> [Double] {
        var result = values
        let count = result.count
        var index = 0
        while index < count {
            if result[index].isFinite {
                index += 1
                continue
            }

            let runStart = index
            while index < count, !result[index].isFinite {
                index += 1
            }
            let runEnd = index

            let leftIndex = runStart - 1
            let rightIndex = runEnd
            guard leftIndex >= 0, rightIndex < count else { continue }
            guard result[leftIndex].isFinite, result[rightIndex].isFinite else { continue }

            let leftValue = result[leftIndex]
            let rightValue = result[rightIndex]
            let span = rightIndex - leftIndex
            guard span > 0 else { continue }

            for fillIndex in runStart..<runEnd {
                let fraction = Double(fillIndex - leftIndex) / Double(span)
                result[fillIndex] = leftValue + fraction * (rightValue - leftValue)
            }
        }
        return result
    }
}
