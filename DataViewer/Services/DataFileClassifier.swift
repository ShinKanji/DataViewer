import Foundation

enum DataFileValidation: Equatable, Sendable {
    case valid
    case unsupportedExtension
    case unreadable
    case empty
    case insufficientStructure
}

nonisolated enum DataFileClassifier {
    private static let identifyThreshold = 3

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "txt" || ext == "csv"
    }

    static func validate(_ url: URL) -> DataFileValidation {
        guard isSupported(url) else { return .unsupportedExtension }
        guard let sample = readTextSample(from: url) else { return .unreadable }

        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard headerContentScore(sample) >= identifyThreshold else { return .insufficientStructure }
        return .valid
    }

    private static func headerContentScore(_ text: String) -> Int {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first else { return 0 }

        var score = 0
        let columns = splitDelimitedColumns(headerLine)
        let nonEmptyColumns = columns.filter { !$0.isEmpty }

        if nonEmptyColumns.count >= 2 { score += 2 }
        if nonEmptyColumns.count >= 5 { score += 1 }
        if let first = nonEmptyColumns.first, ChannelColumnNaming.isTimeColumn(first) { score += 3 }

        let namedHeaders = nonEmptyColumns.filter { Double($0) == nil }.count
        if namedHeaders >= 3 { score += 1 }
        if headerLine.contains("\t") { score += 1 }

        var numericDataRows = 0
        for line in lines.dropFirst().prefix(12) {
            let cols = splitDelimitedColumns(line).filter { !$0.isEmpty }
            guard cols.count >= 2 else { continue }
            let numericCount = cols.filter { Double($0.trimmingCharacters(in: .whitespaces)) != nil }.count
            if numericCount >= 2 { numericDataRows += 1 }
        }
        if numericDataRows >= 3 { score += 3 }
        else if numericDataRows >= 1 { score += 2 }

        return score
    }

    private static func splitDelimitedColumns(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        for separator in ["\t", ",", ";"] {
            let columns = split(line, separator: Character(separator))
            if columns.count >= 2 { return columns }
        }

        let whitespaceColumns = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return whitespaceColumns.count >= 2 ? whitespaceColumns : [trimmed]
    }

    private static func split(_ line: String, separator: Character) -> [String] {
        line.split(separator: separator, omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func readTextSample(from url: URL, maxBytes: Int = 256_000) -> String? {
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: maxBytes), !data.isEmpty {
                return decodeText(from: data)
            }
        }

        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var buffer = Data(count: maxBytes)
        let bytesRead = buffer.withUnsafeMutableBytes { ptr in
            stream.read(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: maxBytes)
        }
        guard bytesRead > 0 else { return nil }
        buffer.count = bytesRead
        return decodeText(from: buffer)
    }

    private static func decodeText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let gb = String(data: data, encoding: .gb18030) { return gb }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return nil
    }
}
