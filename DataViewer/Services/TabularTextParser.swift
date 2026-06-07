import Foundation

nonisolated enum TabularTextParser {
    private struct ParsedFile {
        let headers: [String]
        let times: [Double]
        let rawLines: [String]
    }

    private static var parsedCache: [URL: ParsedFile] = [:]
    private static var columnValueCache: [URL: [Int: [Double]]] = [:]
    private static let cacheQueue = DispatchQueue(label: "TabularTextParser.cache")

    static func invalidateCache(for url: URL? = nil) {
        cacheQueue.sync {
            if let url {
                let key = url.standardizedFileURL
                parsedCache.removeValue(forKey: key)
                columnValueCache.removeValue(forKey: key)
            } else {
                parsedCache.removeAll(keepingCapacity: false)
                columnValueCache.removeAll(keepingCapacity: false)
            }
        }
    }

    static func estimatedDataRowCount(from url: URL) throws -> (columnCount: Int, estimatedRows: Int) {
        let headerLine = try readFirstLine(from: url)
        let columnCount = max(1, splitColumns(headerLine).count)
        let fileBytes = fileByteCount(at: url)
        let headerBytes = headerLine.utf8.count + 1
        let prefixBytes = min(fileBytes, 256 * 1024)
        let prefix = try readPrefixBytes(from: url, upTo: prefixBytes)
        let newlines = prefix.reduce(into: 0) { count, byte in
            if byte == 0x0A || byte == 0x0D { count += 1 }
        }
        let linesInPrefix = max(1, newlines)
        let bytesPerLine = max(1, prefixBytes / linesInPrefix)
        let remainingBytes = max(0, fileBytes - headerBytes)
        let estimatedRows = max(1, remainingBytes / bytesPerLine)
        return (columnCount, estimatedRows)
    }

    static func benchmarkParseDataLines(from url: URL, maxDataLines: Int) throws -> TimeInterval {
        let limit = max(1, maxDataLines)
        let started = CFAbsoluteTimeGetCurrent()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        var headerConsumed = false
        var parsedLines = 0

        while parsedLines < limit {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                if buffer.first == 0x0D {
                    buffer.removeFirst()
                }
                guard let line = decodeLine(lineData), !line.isEmpty else { continue }
                if !headerConsumed {
                    headerConsumed = true
                    continue
                }
                _ = splitColumns(line)
                parsedLines += 1
                if parsedLines >= limit { break }
            }
        }
        return CFAbsoluteTimeGetCurrent() - started
    }

    static func parseCatalog(from url: URL) throws -> [ChannelDescriptor] {
        let headerLine = try readFirstLine(from: url)
        let headers = splitColumns(headerLine)
        guard !headers.isEmpty else { throw ParseError.emptyFile }

        return headers.enumerated().compactMap { index, name in
            guard !ChannelColumnNaming.isTimeColumn(name) else { return nil }
            return ChannelDescriptor(
                containerName: url.lastPathComponent,
                columnName: name,
                columnIndex: index
            )
        }
    }

    static func loadColumn(
        from url: URL,
        columnIndex: Int,
        timeColumnIndex: Int = 0
    ) throws -> DataSeries {
        try extractSeries(
            from: try cachedParsedFile(for: url),
            url: url,
            columnIndex: columnIndex
        )
    }

    static func geoSamples(from url: URL) throws -> [GeoCoordinateSample]? {
        let parsed = try cachedParsedFile(for: url)
        guard let indices = GeoCoordinateDecoder.decimalColumnIndices(in: parsed.headers) else {
            return nil
        }

        let batch = cachedColumnValuesBatch(for: url, from: parsed, columnIndices: [indices.longitude, indices.latitude])
        let longitudeValues = batch[0]
        let latitudeValues = batch[1]
        var samples: [GeoCoordinateSample] = []
        samples.reserveCapacity(parsed.times.count)

        for index in parsed.times.indices {
            samples.append(
                GeoCoordinateSample(
                    time: parsed.times[index],
                    latitude: latitudeValues[index],
                    longitude: longitudeValues[index]
                )
            )
        }
        return samples
    }

    static func loadColumns(
        from url: URL,
        columnIndices: [Int],
        timeColumnIndex: Int = 0
    ) throws -> [DataSeries] {
        let parsed = try cachedParsedFile(for: url)
        let allColumnValues = cachedColumnValuesBatch(for: url, from: parsed, columnIndices: columnIndices)
        let timesRef = parsed.times
        let headersRef = parsed.headers
        let urlRef = url

        return try ParallelWorkPolicy.measure("TabularTextParser.loadColumns") {
            try ParallelWorkPolicy.mapIndexedThrowing(count: columnIndices.count) { index in
                let columnIndex = columnIndices[index]
                guard columnIndex < headersRef.count else { throw ParseError.columnOutOfRange }
                let columnValues = allColumnValues[index]

                var times: [Double] = []
                var values: [Double] = []
                times.reserveCapacity(columnValues.count)
                values.reserveCapacity(columnValues.count)

                for i in timesRef.indices {
                    let value = columnValues[i]
                    guard value.isFinite else { continue }
                    times.append(timesRef[i])
                    values.append(value)
                }

                let descriptor = ChannelDescriptor(
                    containerName: urlRef.lastPathComponent,
                    columnName: headersRef[columnIndex],
                    columnIndex: columnIndex
                )
                return DataSeries(id: descriptor.id, descriptor: descriptor, times: times, values: values)
            }
        }
    }

    private static func extractSeries(
        from parsed: ParsedFile,
        url: URL,
        columnIndex: Int
    ) throws -> DataSeries {
        guard columnIndex < parsed.headers.count else { throw ParseError.columnOutOfRange }

        let columnValues = cachedColumnValues(for: url, from: parsed, columnIndex: columnIndex)
        var times: [Double] = []
        var values: [Double] = []
        times.reserveCapacity(columnValues.count)
        values.reserveCapacity(columnValues.count)

        for index in parsed.times.indices {
            let value = columnValues[index]
            guard value.isFinite else { continue }
            times.append(parsed.times[index])
            values.append(value)
        }

        let descriptor = ChannelDescriptor(
            containerName: url.lastPathComponent,
            columnName: parsed.headers[columnIndex],
            columnIndex: columnIndex
        )
        return DataSeries(id: descriptor.id, descriptor: descriptor, times: times, values: values)
    }

    private static func cachedColumnValues(for url: URL, from parsed: ParsedFile, columnIndex: Int) -> [Double] {
        cachedColumnValuesBatch(for: url, from: parsed, columnIndices: [columnIndex])[0]
    }

    private static func cachedColumnValuesBatch(
        for url: URL,
        from parsed: ParsedFile,
        columnIndices: [Int]
    ) -> [[Double]] {
        let key = url.standardizedFileURL
        return cacheQueue.sync {
            var uncached: [Int] = []
            for idx in columnIndices {
                if columnValueCache[key]?[idx] == nil {
                    uncached.append(idx)
                }
            }

            if !uncached.isEmpty {
                let count = parsed.rawLines.count
                var results: [Int: [Double]] = [:]
                for idx in uncached {
                    var arr: [Double] = []
                    arr.reserveCapacity(count)
                    results[idx] = arr
                }
                for line in parsed.rawLines {
                    let cols = splitColumns(line)
                    for idx in uncached {
                        let value: Double
                        if idx < cols.count, let v = Double(cols[idx]) {
                            value = v
                        } else {
                            value = .nan
                        }
                        results[idx]!.append(value)
                    }
                }
                for (idx, values) in results {
                    columnValueCache[key, default: [:]][idx] = values
                }
            }

            return columnIndices.map { idx in
                columnValueCache[key]?[idx] ?? []
            }
        }
    }

    static func splitColumns(_ line: String) -> [String] {
        line.split(separator: "\t", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func cachedParsedFile(for url: URL) throws -> ParsedFile {
        let key = url.standardizedFileURL
        return try cacheQueue.sync {
            if let cached = parsedCache[key] {
                return cached
            }
            let parsed = try parseFile(from: url, timeColumnIndex: 0)
            parsedCache[key] = parsed
            return parsed
        }
    }

    private static let smallFileThreshold: UInt64 = 10 * 1024 * 1024  // 10 MB

    private static func parseFile(from url: URL, timeColumnIndex: Int = 0) throws -> ParsedFile {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize < smallFileThreshold {
            return try parseFileSmall(url: url, timeColumnIndex: timeColumnIndex)
        }
        return try parseFileStreaming(url: url, timeColumnIndex: timeColumnIndex)
    }

    private static func parseFileSmall(url: URL, timeColumnIndex: Int) throws -> ParsedFile {
        let content = try readText(from: url)
        let lines = content.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else { throw ParseError.emptyFile }

        let headers = splitColumns(String(lines[0]))
        guard !headers.isEmpty else { throw ParseError.emptyFile }

        var times: [Double] = []
        var rawLines: [String] = []
        times.reserveCapacity(lines.count - 1)
        rawLines.reserveCapacity(lines.count - 1)

        for line in lines.dropFirst() {
            let lineStr = String(line)
            let cols = splitColumns(lineStr)
            guard timeColumnIndex < cols.count, let time = Double(cols[timeColumnIndex]) else { continue }
            times.append(time)
            rawLines.append(lineStr)
        }

        return ParsedFile(headers: headers, times: times, rawLines: rawLines)
    }

    private static func parseFileStreaming(url: URL, timeColumnIndex: Int) throws -> ParsedFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        var headerConsumed = false
        var headers: [String] = []
        var times: [Double] = []
        var rawLines: [String] = []
        times.reserveCapacity(4096)
        rawLines.reserveCapacity(4096)

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
                guard let line = decodeLine(lineData), !line.isEmpty else { continue }

                if !headerConsumed {
                    headers = splitColumns(line)
                    guard !headers.isEmpty else { throw ParseError.emptyFile }
                    headerConsumed = true
                    continue
                }

                let cols = splitColumns(line)
                guard timeColumnIndex < cols.count, let time = Double(cols[timeColumnIndex]) else { continue }
                times.append(time)
                rawLines.append(line)
            }
        }

        guard headerConsumed else { throw ParseError.emptyFile }
        return ParsedFile(headers: headers, times: times, rawLines: rawLines)
    }

    private static func fileByteCount(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func readPrefixBytes(from url: URL, upTo limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: max(1, limit)) ?? Data()
    }

    private static func decodeLine(_ data: Data.SubSequence) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let gb = String(data: data, encoding: .gb18030) { return gb }
        return nil
    }

    static func readFirstLineForBenchmark(from url: URL) throws -> String {
        try readFirstLine(from: url)
    }

    private static func readFirstLine(from url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            let chunk = try handle.read(upToCount: 4096) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
            if chunk.contains(0x0A) || chunk.contains(0x0D) { break }
            if data.count > 65_536 { break }
        }
        guard !data.isEmpty else { throw ParseError.emptyFile }
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let gb = String(data: data, encoding: .gb18030) {
            text = gb
        } else {
            throw ParseError.unsupportedEncoding
        }
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let gb = String(data: data, encoding: .gb18030) { return gb }
        throw ParseError.unsupportedEncoding
    }

    enum ParseError: LocalizedError {
        case emptyFile
        case columnOutOfRange
        case unsupportedEncoding

        var errorDescription: String? {
            switch self {
            case .emptyFile: String(localized: "表格文本文件为空", comment: "Empty file error")
            case .columnOutOfRange: String(localized: "列索引超出范围", comment: "Column out of range error")
            case .unsupportedEncoding: String(localized: "无法识别表格文本文件编码", comment: "Unsupported encoding error")
            }
        }
    }
}
