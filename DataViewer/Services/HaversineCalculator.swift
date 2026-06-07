import Foundation

nonisolated enum HaversineCalculator {
    private static let earthRadiusMeters = 6_371_000.0

    static func distanceMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double? {
        guard latitude1.isFinite, longitude1.isFinite, latitude2.isFinite, longitude2.isFinite else {
            return nil
        }

        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (longitude2 - longitude1) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}
