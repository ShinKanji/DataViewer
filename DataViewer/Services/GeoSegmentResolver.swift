import Foundation

nonisolated enum GeoSegmentResolver {
    static func summary(samples: [GeoCoordinateSample], range: VisibleTimeRange) -> GeoSegmentSummary {
        let inRange = samples.filter { $0.time >= range.start && $0.time <= range.end }
        let start = firstValid(in: inRange)
        let end = lastValid(in: inRange)

        guard let start, let end else {
            return GeoSegmentSummary(
                startLatitude: nil,
                startLongitude: nil,
                endLatitude: nil,
                endLongitude: nil,
                haversineMeters: nil,
                isAvailable: false
            )
        }

        let distance = HaversineCalculator.distanceMeters(
            latitude1: start.latitude,
            longitude1: start.longitude,
            latitude2: end.latitude,
            longitude2: end.longitude
        )

        return GeoSegmentSummary(
            startLatitude: start.latitude,
            startLongitude: start.longitude,
            endLatitude: end.latitude,
            endLongitude: end.longitude,
            haversineMeters: distance,
            isAvailable: distance != nil
        )
    }

    private static func firstValid(in samples: [GeoCoordinateSample]) -> GeoCoordinateSample? {
        samples.first { isValid($0) }
    }

    private static func lastValid(in samples: [GeoCoordinateSample]) -> GeoCoordinateSample? {
        samples.last { isValid($0) }
    }

    private static func isValid(_ sample: GeoCoordinateSample) -> Bool {
        sample.latitude.isFinite && sample.longitude.isFinite
    }
}
