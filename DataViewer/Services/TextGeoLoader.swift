import Foundation

nonisolated enum TextGeoLoader {
    static func load(from url: URL) throws -> [GeoCoordinateSample]? {
        let samples = try TabularTextParser.geoSamples(from: url)
        guard let samples, !samples.isEmpty else { return nil }
        return samples
    }
}
