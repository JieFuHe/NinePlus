import Foundation

struct NinebotCoordinatePair: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

enum NinebotCoordinateTransform {
    static func gcj02Coordinate(latitude: Double, longitude: Double) -> NinebotCoordinatePair {
        guard isInsideMainlandChina(latitude: latitude, longitude: longitude) else {
            return NinebotCoordinatePair(latitude: latitude, longitude: longitude)
        }

        var latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0)
        var longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radianLatitude = latitude / 180.0 * .pi
        var magic = sin(radianLatitude)
        magic = 1 - earthEccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        latitudeDelta = (latitudeDelta * 180.0) / ((earthRadius * (1 - earthEccentricity)) / (magic * sqrtMagic) * .pi)
        longitudeDelta = (longitudeDelta * 180.0) / (earthRadius / sqrtMagic * cos(radianLatitude) * .pi)

        return NinebotCoordinatePair(
            latitude: latitude + latitudeDelta,
            longitude: longitude + longitudeDelta
        )
    }

    static func isInsideMainlandChina(latitude: Double, longitude: Double) -> Bool {
        longitude > 72.004 && longitude < 137.8347 && latitude > 0.8293 && latitude < 55.8271
    }

    private static let earthRadius = 6378245.0
    private static let earthEccentricity = 0.00669342162296594323

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }
}
