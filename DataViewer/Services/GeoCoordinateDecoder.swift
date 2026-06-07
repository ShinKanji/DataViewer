import Foundation

nonisolated enum GeoCoordinateDecoder {
    struct CoordinateColumnGroup {
        let prefix: String
        let degreeColumns: [(name: String, placeValue: Double)]
        let minuteColumns: [(name: String, placeValue: Double)]
    }

    static let longitudePrefix = "LONGITUDE"
    static let latitudePrefix = "LATITUDE"
    static let degreesMarker = "DEGREES"
    static let minutesMarker = "MINUTES"

    static func columnGroups(from columnNames: [String]) -> (longitude: CoordinateColumnGroup?, latitude: CoordinateColumnGroup?) {
        let longitude = group(prefix: longitudePrefix, in: columnNames)
        let latitude = group(prefix: latitudePrefix, in: columnNames)
        return (longitude, latitude)
    }

    static func hasGeoColumns(in columnNames: [String]) -> Bool {
        hasSplitDigitGeoColumns(in: columnNames) || hasDecimalGeoColumns(in: columnNames)
    }

    static func hasSplitDigitGeoColumns(in columnNames: [String]) -> Bool {
        columnNames.contains("\(longitudePrefix)_\(degreesMarker)_1")
            && columnNames.contains("\(latitudePrefix)_\(degreesMarker)_1")
    }

    static func hasDecimalGeoColumns(in columnNames: [String]) -> Bool {
        decimalColumnIndices(in: columnNames) != nil
    }

    static func isDecimalGeoColumnName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        return trimmed == "经度" || trimmed == "纬度" || upper == "LONGITUDE" || upper == "LATITUDE"
    }

    static func decimalColumnIndices(in columnNames: [String]) -> (longitude: Int, latitude: Int)? {
        var longitudeIndex: Int?
        var latitudeIndex: Int?
        for (index, name) in columnNames.enumerated() where isDecimalGeoColumnName(name) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = trimmed.uppercased()
            if trimmed == "经度" || upper == "LONGITUDE" {
                longitudeIndex = index
            } else if trimmed == "纬度" || upper == "LATITUDE" {
                latitudeIndex = index
            }
        }
        guard let longitudeIndex, let latitudeIndex else { return nil }
        return (longitudeIndex, latitudeIndex)
    }

    static func isGeoColumnName(_ name: String) -> Bool {
        let upper = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return upper.hasPrefix("\(longitudePrefix)_") || upper.hasPrefix("\(latitudePrefix)_")
    }

    static func decode(
        longitudeGroup: CoordinateColumnGroup?,
        latitudeGroup: CoordinateColumnGroup?,
        row: [String: String],
        columnLetterByName: [String: String]
    ) -> (latitude: Double, longitude: Double) {
        let lon = decodeCoordinate(group: longitudeGroup, row: row, columnLetterByName: columnLetterByName)
        let lat = decodeCoordinate(group: latitudeGroup, row: row, columnLetterByName: columnLetterByName)
        return (lat, lon)
    }

    private static func group(prefix: String, in columnNames: [String]) -> CoordinateColumnGroup? {
        let matching = columnNames.filter { $0.hasPrefix("\(prefix)_") }
        guard !matching.isEmpty else { return nil }

        var degreeColumns: [(String, Double)] = []
        var minuteColumns: [(String, Double)] = []
        for name in matching {
            if name.contains("_\(degreesMarker)_") {
                let suffix = suffix(after: "\(prefix)_\(degreesMarker)_", in: name)
                degreeColumns.append((name, placeValue(from: suffix)))
            } else if name.contains("_\(minutesMarker)_") {
                let suffix = suffix(after: "\(prefix)_\(minutesMarker)_", in: name)
                minuteColumns.append((name, placeValue(from: suffix)))
            }
        }
        guard !degreeColumns.isEmpty else { return nil }
        degreeColumns.sort(by: { $0.1 > $1.1 })
        minuteColumns.sort(by: { $0.1 > $1.1 })
        return CoordinateColumnGroup(prefix: prefix, degreeColumns: degreeColumns, minuteColumns: minuteColumns)
    }

    private static func suffix(after marker: String, in name: String) -> String {
        guard let range = name.range(of: marker) else { return "" }
        return String(name[range.upperBound...])
    }

    private static func placeValue(from suffix: String) -> Double {
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return 0 }
        // 前导零后缀表示分的小数位权，如 _01 → 0.1，_001 → 0.01。
        if suffix.hasPrefix("0"), suffix.count > 1 {
            return pow(10.0, Double(-(suffix.count - 1)))
        }
        return Double(Int(suffix) ?? 0)
    }

    private static func decodeCoordinate(
        group: CoordinateColumnGroup?,
        row: [String: String],
        columnLetterByName: [String: String]
    ) -> Double {
        guard let group else { return .nan }

        var degrees = 0.0
        for column in group.degreeColumns {
            guard let digit = digitValue(row: row, name: column.name, columnLetterByName: columnLetterByName) else {
                return .nan
            }
            degrees += Double(digit) * column.placeValue
        }

        var minutes = 0.0
        for column in group.minuteColumns {
            guard let digit = digitValue(row: row, name: column.name, columnLetterByName: columnLetterByName) else {
                return .nan
            }
            minutes += Double(digit) * column.placeValue
        }

        return degrees + minutes / 60.0
    }

    private static func digitValue(
        row: [String: String],
        name: String,
        columnLetterByName: [String: String]
    ) -> Int? {
        guard let letter = columnLetterByName[name], let text = row[letter] else { return nil }
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        guard value.rounded() == value else { return nil }
        let digit = Int(value)
        guard digit >= 0, digit <= 9 else { return nil }
        return digit
    }
}
