import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum NinebotChargingLiveActivityManager {
    static func sync(with dashboard: NinebotDashboard) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task {
            await NinebotChargingActivityController.sync(with: dashboard)
        }
        #endif
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
private enum NinebotChargingActivityController {
    static func sync(with dashboard: NinebotDashboard) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        guard let snapshot = dashboard.primaryVehicle,
              snapshot.state.isCharging == true,
              !snapshot.state.isFullyCharged,
              let battery = snapshot.state.battery else {
            await endAll()
            return
        }

        let attributes = NinebotChargingActivityAttributes(
            vehicleSN: snapshot.vehicle.sn,
            vehicleName: snapshot.vehicle.name,
            vehicleModel: snapshot.vehicle.model
        )
        let state = NinebotChargingActivityAttributes.ContentState(
            battery: battery,
            estimatedRange: snapshot.state.localEstimatedMileage ?? snapshot.state.endurance ?? snapshot.state.aiEstimatedMileage,
            estimatedFullAt: estimatedFullAt(for: snapshot.state),
            chargingPower: snapshot.state.chargingPower,
            batteryTemperature: snapshot.state.batteryTemperature,
            batteryVoltage: snapshot.state.batteryVoltage,
            chargingSpeed: snapshot.state.estimatedChargingSpeedKmh,
            updatedAt: snapshot.state.updatedAt
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(20 * 60)
        )

        let activities = Activity<NinebotChargingActivityAttributes>.activities
        let matchingActivity = activities.first { $0.attributes.vehicleSN == snapshot.vehicle.sn }

        for activity in activities where activity.id != matchingActivity?.id {
            await activity.end(content, dismissalPolicy: .immediate)
        }

        if let matchingActivity {
            await matchingActivity.update(content)
        } else {
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                #if DEBUG
                print("Failed to start NineBot charging Live Activity: \(error)")
                #endif
            }
        }
    }

    private static func endAll() async {
        for activity in Activity<NinebotChargingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func estimatedFullAt(for state: NinebotVehicleState) -> Date? {
        guard let minutes = state.estimatedFullChargeMinutes, minutes > 0 else { return nil }
        return Date().addingTimeInterval(minutes * 60)
    }

}
#endif
