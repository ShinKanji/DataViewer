import Foundation

nonisolated enum ChannelColumnNaming {
    private static let classificationCacheLock = NSLock()
    private static var excludedFromCandidateCache: [String: Bool] = [:]
    private static var geoColumnCache: [String: Bool] = [:]
    private static var splitVelocityKPHCache: [String: Bool] = [:]
    private static var unifiedVelocityKPHCache: [String: Bool] = [:]
    private static var usesVelocityKPHCache: [String: Bool] = [:]

    static func isTimeColumn(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "TIME" { return true }
        return trimmed == "时间"
    }

    static func isExcludedFromCandidateList(_ name: String) -> Bool {
        classificationCacheLock.lock()
        if let cached = excludedFromCandidateCache[name] {
            classificationCacheLock.unlock()
            return cached
        }
        classificationCacheLock.unlock()
        let result = isGeoCoordinateColumn(name) || isSplitVelocityKPHColumn(name)
        classificationCacheLock.lock()
        excludedFromCandidateCache[name] = result
        classificationCacheLock.unlock()
        return result
    }

    static func isGeoCoordinateColumn(_ name: String) -> Bool {
        classificationCacheLock.lock()
        if let cached = geoColumnCache[name] {
            classificationCacheLock.unlock()
            return cached
        }
        classificationCacheLock.unlock()
        let result = GeoCoordinateDecoder.isGeoColumnName(name) || GeoCoordinateDecoder.isDecimalGeoColumnName(name)
        classificationCacheLock.lock()
        geoColumnCache[name] = result
        classificationCacheLock.unlock()
        return result
    }

    static func isSplitVelocityKPHColumn(_ name: String) -> Bool {
        classificationCacheLock.lock()
        if let cached = splitVelocityKPHCache[name] {
            classificationCacheLock.unlock()
            return cached
        }
        classificationCacheLock.unlock()

        let upper = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.contains("VELOCITY"), upper.contains("KPH") else {
            classificationCacheLock.lock()
            splitVelocityKPHCache[name] = false
            classificationCacheLock.unlock()
            return false
        }

        let result: Bool
        if let underscore = upper.lastIndex(of: "_") {
            let suffix = upper[upper.index(after: underscore)...]
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                result = true
            } else {
                result = false
            }
        } else if let kphRange = upper.range(of: "KPH") {
            let suffix = upper[kphRange.upperBound...]
            result = !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
        } else {
            result = false
        }

        classificationCacheLock.lock()
        splitVelocityKPHCache[name] = result
        classificationCacheLock.unlock()
        return result
    }

    static func isUnifiedVelocityKPHColumn(_ name: String) -> Bool {
        classificationCacheLock.lock()
        if let cached = unifiedVelocityKPHCache[name] {
            classificationCacheLock.unlock()
            return cached
        }
        classificationCacheLock.unlock()

        let upper = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.contains("VELOCITY"), upper.contains("KPH"), !isSplitVelocityKPHColumn(name) else {
            classificationCacheLock.lock()
            unifiedVelocityKPHCache[name] = false
            classificationCacheLock.unlock()
            return false
        }

        classificationCacheLock.lock()
        unifiedVelocityKPHCache[name] = true
        classificationCacheLock.unlock()
        return true
    }

    static let unifiedVelocityKPHDisplayName = "VELOCITYKPH"

    static func usesVelocityKPHDisplayName(_ name: String) -> Bool {
        classificationCacheLock.lock()
        if let cached = usesVelocityKPHCache[name] {
            classificationCacheLock.unlock()
            return cached
        }
        classificationCacheLock.unlock()
        let result = isUnifiedVelocityKPHColumn(name) || isSplitVelocityKPHColumn(name)
        classificationCacheLock.lock()
        usesVelocityKPHCache[name] = result
        classificationCacheLock.unlock()
        return result
    }

    static func candidateListChannels(from descriptors: [ChannelDescriptor]) -> [ChannelDescriptor] {
        descriptors.filter { !isExcludedFromCandidateList($0.columnName) }
    }
}

nonisolated enum ChannelGroupNaming {
    static func numberedSeriesParts(from name: String) -> (base: String, indexDigits: String)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var digitStart = trimmed.endIndex
        while digitStart > trimmed.startIndex {
            let index = trimmed.index(before: digitStart)
            guard trimmed[index].isNumber else { break }
            digitStart = index
        }
        guard digitStart < trimmed.endIndex else { return nil }

        var baseEnd = digitStart
        if baseEnd > trimmed.startIndex {
            let separator = trimmed[trimmed.index(before: baseEnd)]
            if separator == "_" || separator == "-" || separator == " " {
                baseEnd = trimmed.index(before: baseEnd)
            }
        }

        let base = String(trimmed[..<baseEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.allSatisfy(\.isNumber) else { return nil }

        let indexDigits = String(trimmed[digitStart...])
        return (base, indexDigits)
    }

    static func inferredGroupName(from names: [String]) -> String? {
        guard names.count >= 2 else { return nil }
        var sharedBase: String?
        for name in names {
            guard let parts = numberedSeriesParts(from: name) else { return nil }
            if let sharedBase {
                if sharedBase != parts.base { return nil }
            } else {
                sharedBase = parts.base
            }
        }
        return sharedBase
    }
}

nonisolated struct ChannelDescriptor: Identifiable, Hashable, Sendable {
    let id: UUID
    let containerName: String
    let columnName: String
    let columnIndex: Int

    var displayName: String { columnName }
    var qualifiedName: String { columnName }

    init(
        id: UUID = UUID(),
        containerName: String,
        columnName: String,
        columnIndex: Int
    ) {
        self.id = id
        self.containerName = containerName
        self.columnName = columnName
        self.columnIndex = columnIndex
    }
}

nonisolated struct DataSeries: Identifiable, Sendable {
    let id: UUID
    let descriptor: ChannelDescriptor
    let times: [Double]
    let values: [Double]

    var duration: Double {
        guard let first = times.first, let last = times.last else { return 0 }
        return last - first
    }
}

struct PlotGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var channelIDs: [UUID]

    init(id: UUID = UUID(), name: String, channelIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.channelIDs = channelIDs
    }
}

nonisolated struct VisibleTimeRange: Equatable, Hashable {
    var start: Double
    var end: Double

    var length: Double { max(0, end - start) }

    static func spanning(_ min: Double, _ max: Double) -> VisibleTimeRange {
        VisibleTimeRange(start: min, end: max)
    }
}

nonisolated struct ChartSelectionSample: Identifiable, Equatable, Sendable {
    let channelID: UUID
    let seriesName: String
    let scaledValue: Double
    let plotTime: Double
    let colorIndex: Int

    var id: UUID { channelID }
}

nonisolated struct PlotSample: Identifiable, Equatable, Hashable {
    let id: UInt64
    let time: Double
    let value: Double
    let seriesName: String

    init(time: Double, value: Double, seriesName: String) {
        self.time = time
        self.value = value
        self.seriesName = seriesName
        self.id = Self.stableID(time: time, seriesName: seriesName)
    }

    private static func stableID(time: Double, seriesName: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(time.bitPattern)
        hasher.combine(seriesName)
        return UInt64(bitPattern: Int64(truncatingIfNeeded: hasher.finalize()))
    }
}

nonisolated enum DerivedOpKind: String, Codable, Sendable, CaseIterable {
    case deriv
    case integ
    case movmean

    var displayTitle: String {
        switch self {
        case .deriv: return "求导 d/dt"
        case .integ: return "积分 ∫dt"
        case .movmean: return "滑动平均"
        }
    }
}

nonisolated struct DerivedChannelRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let parentID: UUID
    let op: DerivedOpKind
    let windowSamples: Int?
    let displayName: String

    init(
        id: UUID = UUID(),
        parentID: UUID,
        op: DerivedOpKind,
        windowSamples: Int? = nil,
        displayName: String
    ) {
        self.id = id
        self.parentID = parentID
        self.op = op
        self.windowSamples = windowSamples
        self.displayName = displayName
    }
}

nonisolated enum DerivedChannelNaming {
    static let internalPrefix = "__derived__"

    static func isDerivedColumnName(_ name: String) -> Bool {
        name.hasPrefix(internalPrefix)
    }

    static func internalColumnName(displayName: String) -> String {
        internalPrefix + displayName
    }
}
