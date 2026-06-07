import Foundation

nonisolated struct SampleCacheKey: Hashable, Sendable {
    let seriesID: UUID
    let rangeStartMillis: Int
    let rangeEndMillis: Int
    let maxPoints: Int
    let timeOffsetMicros: Int
    let valueScaleMicros: Int
    let smoothingWindow: UInt8
}

actor PlotSampleStore {
    static let defaultMaxCacheEntries = 256

    private var cache: [SampleCacheKey: [PlotSample]] = [:]
    private var lruOrder: [SampleCacheKey] = []
    private let maxEntries: Int
    private(set) var generation: UInt = 0

    init(maxEntries: Int = PlotSampleStore.defaultMaxCacheEntries) {
        self.maxEntries = max(1, maxEntries)
    }

    @discardableResult
    func invalidateAll() -> UInt {
        generation += 1
        cache.removeAll(keepingCapacity: false)
        lruOrder.removeAll(keepingCapacity: false)
        return generation
    }

    struct SampleRequest: Sendable {
        let series: DataSeries
        let range: VisibleTimeRange
        let maxPoints: Int
        let timeOffset: Double
        let valueScale: Double
        let seriesName: String
        var smoothingWindow: Int = 0
    }

    func samplesBatch(_ requests: [SampleRequest]) async -> [[PlotSample]] {
        guard !requests.isEmpty else { return [] }

        var results: [[PlotSample]] = []
        results.reserveCapacity(requests.count)
        var uncachedIndices: [Int] = []
        var uncachedRequests: [SampleRequest] = []

        for (index, request) in requests.enumerated() {
            let key = Self.cacheKey(
                seriesID: request.series.id,
                range: request.range,
                maxPoints: request.maxPoints,
                timeOffset: request.timeOffset,
                valueScale: request.valueScale,
                smoothingWindow: request.smoothingWindow
            )
            if let cached = cache[key] {
                results.append(cached)
                touch(key)
            } else {
                results.append([])
                uncachedIndices.append(index)
                uncachedRequests.append(request)
            }
        }

        guard !uncachedRequests.isEmpty else { return results }

        let computed = await withTaskGroup(of: (Int, SampleCacheKey, [PlotSample]).self) { group in
            for (offset, request) in uncachedRequests.enumerated() {
                let key = Self.cacheKey(
                    seriesID: request.series.id,
                    range: request.range,
                    maxPoints: request.maxPoints,
                    timeOffset: request.timeOffset,
                    valueScale: request.valueScale,
                    smoothingWindow: request.smoothingWindow
                )
                group.addTask {
                    let samples = SeriesSampler.samples(
                        in: request.range,
                        from: request.series,
                        maxPoints: request.maxPoints,
                        timeOffset: request.timeOffset,
                        valueScale: request.valueScale,
                        seriesName: request.seriesName,
                        smoothingWindow: request.smoothingWindow
                    )
                    return (offset, key, samples)
                }
            }

            var collected: [(Int, SampleCacheKey, [PlotSample])] = []
            collected.reserveCapacity(uncachedRequests.count)
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (offset, key, samples) in computed {
            let originalIndex = uncachedIndices[offset]
            results[originalIndex] = samples
            insert(key, samples)
        }

        return results
    }

    func samples(
        series: DataSeries,
        range: VisibleTimeRange,
        maxPoints: Int,
        timeOffset: Double,
        valueScale: Double = 1,
        seriesName: String,
        smoothingWindow: Int = 0
    ) async -> [PlotSample] {
        let key = Self.cacheKey(
            seriesID: series.id,
            range: range,
            maxPoints: maxPoints,
            timeOffset: timeOffset,
            valueScale: valueScale,
            smoothingWindow: smoothingWindow
        )

        if let cached = cache[key] {
            touch(key)
            return cached
        }

        let computed = await Task.detached(priority: .userInitiated) {
            SeriesSampler.samples(
                in: range,
                from: series,
                maxPoints: maxPoints,
                timeOffset: timeOffset,
                valueScale: valueScale,
                seriesName: seriesName,
                smoothingWindow: smoothingWindow
            )
        }.value

        insert(key, computed)
        return computed
    }

    private static func cacheKey(
        seriesID: UUID,
        range: VisibleTimeRange,
        maxPoints: Int,
        timeOffset: Double,
        valueScale: Double,
        smoothingWindow: Int = 0
    ) -> SampleCacheKey {
        SampleCacheKey(
            seriesID: seriesID,
            rangeStartMillis: millis(range.start),
            rangeEndMillis: millis(range.end),
            maxPoints: maxPoints,
            timeOffsetMicros: micros(timeOffset),
            valueScaleMicros: scaleMicros(valueScale),
            smoothingWindow: UInt8(clamping: smoothingWindow)
        )
    }

    private static func scaleMicros(_ scale: Double) -> Int {
        Int((scale * 1_000_000).rounded())
    }

    private static func millis(_ seconds: Double) -> Int {
        Int((seconds * 1_000).rounded())
    }

    private static func micros(_ seconds: Double) -> Int {
        Int((seconds * 1_000_000).rounded())
    }

    private func touch(_ key: SampleCacheKey) {
        guard let index = lruOrder.firstIndex(of: key) else { return }
        lruOrder.remove(at: index)
        lruOrder.append(key)
    }

    private func insert(_ key: SampleCacheKey, _ samples: [PlotSample]) {
        if cache[key] != nil {
            touch(key)
        } else {
            lruOrder.append(key)
        }
        cache[key] = samples
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while lruOrder.count > maxEntries {
            let oldest = lruOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
