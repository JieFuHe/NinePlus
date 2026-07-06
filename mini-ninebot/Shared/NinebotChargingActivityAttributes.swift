import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct NinebotChargingActivityAttributes: ActivityAttributes {
    var vehicleSN: String
    var vehicleName: String
    var vehicleModel: String

    struct ContentState: Codable, Hashable {
        var battery: Int
        var estimatedRange: Double?
        var estimatedFullAt: Date?
        var chargingPower: Double?
        var batteryTemperature: Double?
        var batteryVoltage: Double?
        var chargingSpeed: Double?
        var updatedAt: Date
    }
}
#endif
