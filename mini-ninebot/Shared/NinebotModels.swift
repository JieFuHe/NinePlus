import Foundation

enum NinebotAppGroup {
    static let identifier = "group.com.vvovvo.mini-ninebot"
}

struct NinebotProxyConfiguration: Codable, Equatable {
    var baseURLString: String
    var bearerToken: String

    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else {
            withScheme = "http://\(trimmed)"
        }

        return URL(string: withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    var isUsable: Bool {
        baseURL != nil
    }
}

struct NinebotLoginResult: Codable, Equatable {
    var uuid: String?
    var phone: String?
    var areaCode: String?
    var region: String?
    var businessUID: String?
}

struct NinebotVehicleInfo: Codable, Equatable, Identifiable {
    var sn: String
    var name: String
    var model: String
    var imageURLString: String?
    var raw: [String: JSONValue]?

    var id: String { sn }

    var vin: String? {
        firstRawString(["vin", "VIN", "vehicle_vin", "vehicleVin", "car_vin", "carVin"])
    }

    var identifierSummaryText: String {
        if let vin, !vin.isEmpty {
            return "SN \(sn) · VIN \(vin)"
        }
        return "SN \(sn)"
    }

    private func firstRawString(_ keys: [String]) -> String? {
        guard let raw else { return nil }
        for key in keys {
            if let value = raw[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

enum NinebotVehicleHealthLevel: String, Codable, Equatable {
    case good
    case attention
    case critical
    case charging
    case unknown
}

struct NinebotVehicleHealth: Codable, Equatable {
    var level: NinebotVehicleHealthLevel
    var title: String
    var message: String
    var systemImage: String
}

struct NinebotRideRecord: Codable, Equatable, Identifiable {
    var id: String
    var startedAt: Date?
    var endedAt: Date?
    var mileage: Double?
    var energy: Double?
    var usedElectricity: Double?
    var durationMinutes: Double?
    var speed: Double?
    var raw: [String: JSONValue]?
}

extension NinebotRideRecord {
    var stableIdentityKey: String {
        if let travelID = firstRawText(["travel_id", "travelId"]) {
            return "travel:\(travelID)"
        }

        if let explicitIdentifier = firstRawText(["ride_id", "rideId", "record_id", "recordId", "id"]) {
            return "id:\(explicitIdentifier)"
        }

        if let rawStart = firstRawText(["start_time", "startTime", "begin_time", "beginTime", "stime", "date", "day", "create_time", "createTime"]) {
            let rawEnd = firstRawText(["end_time", "endTime", "stop_time", "stopTime", "etime", "finish_time", "finishTime"]) ?? "none"
            let rawMileage = firstRawText(["mileages", "mileage", "distance", "rideMileage"]) ?? Self.metricText(mileage, scale: 100)
            let rawUsed = firstRawText(["used_electricity", "usedElectricity", "usedElectric", "useElectricity"]) ?? Self.metricText(usedElectricity, scale: 100)
            return "raw:start=\(rawStart)|end=\(rawEnd)|km=\(rawMileage)|used=\(rawUsed)"
        }

        if let startedAt {
            return [
                "start:\(Self.timestampText(startedAt))",
                "end:\(endedAt.map { Self.timestampText($0) } ?? "none")",
                "km:\(Self.metricText(mileage, scale: 100))",
                "used:\(Self.metricText(usedElectricity, scale: 100))"
            ].joined(separator: "|")
        }

        return [
            "fallback:\(id)",
            "km:\(Self.metricText(mileage, scale: 100))",
            "energy:\(Self.metricText(energy, scale: 10))",
            "used:\(Self.metricText(usedElectricity, scale: 100))",
            "duration:\(Self.metricText(durationMinutes, scale: 10))",
            "speed:\(Self.metricText(speed, scale: 10))"
        ].joined(separator: "|")
    }

    private func firstRawText(_ keys: [String]) -> String? {
        guard let raw else { return nil }
        for key in keys {
            if let text = raw[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return "\(key)=\(text)"
            }
        }
        return nil
    }

    private static func timestampText(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    private static func metricText(_ value: Double?, scale: Double) -> String {
        guard let value else { return "none" }
        return String(Int((value * scale).rounded()))
    }
}

struct NinebotDailyMileageRecord: Codable, Equatable, Identifiable {
    var id: String
    var day: Int
    var date: Date?
    var mileage: Double
}

struct NinebotRideTrackPoint: Codable, Equatable, Identifiable {
    var id: String
    var date: Date
    var latitude: Double
    var longitude: Double
    var speedKmh: Double
    var accelerationG: Double
    var horizontalAccuracy: Double?

    init(
        id: String = UUID().uuidString,
        date: Date,
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        accelerationG: Double,
        horizontalAccuracy: Double?
    ) {
        self.id = id
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
        self.accelerationG = accelerationG
        self.horizontalAccuracy = horizontalAccuracy
    }
}

struct NinebotRecordedRide: Codable, Equatable, Identifiable {
    var id: String
    var vehicleSN: String?
    var associatedRideID: String?
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var maxSpeedKmh: Double
    var averageSpeedKmh: Double
    var maxAccelerationG: Double
    var points: [NinebotRideTrackPoint]

    init(
        id: String = UUID().uuidString,
        vehicleSN: String?,
        associatedRideID: String? = nil,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        maxSpeedKmh: Double,
        averageSpeedKmh: Double,
        maxAccelerationG: Double,
        points: [NinebotRideTrackPoint]
    ) {
        self.id = id
        self.vehicleSN = vehicleSN
        self.associatedRideID = associatedRideID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.maxSpeedKmh = maxSpeedKmh
        self.averageSpeedKmh = averageSpeedKmh
        self.maxAccelerationG = maxAccelerationG
        self.points = points
    }

    var durationSeconds: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }

    var distanceKilometers: Double {
        distanceMeters / 1000
    }
}

struct NinebotVehicleState: Codable, Equatable {
    var battery: Int?
    var batteryVoltage: Double?
    var batteryTemperature: Double?
    var endurance: Double?
    var aiEstimatedMileage: Double?
    var isCharging: Bool?
    var isPoweredOn: Bool?
    var isLocked: Bool?
    var remainingChargeTime: Double?
    var locationDescription: String?
    var latitude: Double?
    var longitude: Double?
    var totalMileage: Double?
    var monthMileage: Double?
    var monthEnergy: Double?
    var monthUsedElectricity: Double?
    var lastMileage: Double?
    var lastEnergy: Double?
    var lastUsedElectricity: Double?
    var rideRecords: [NinebotRideRecord]?
    var dailyMileageRecords: [NinebotDailyMileageRecord]?
    var updatedAt: Date
    var rawStatus: [String: JSONValue]?
    var rawTravel: [String: JSONValue]?

    var batteryText: String {
        guard let battery else { return "--%" }
        return "\(battery)%"
    }

    var batteryFraction: Double {
        guard let battery else { return 0 }
        return min(max(Double(battery) / 100, 0), 1)
    }

    var batteryVoltageText: String {
        guard let batteryVoltage else { return "接口未返回" }
        return "\(Self.numberText(batteryVoltage, maximumFractionDigits: 1)) V"
    }

    var batteryTemperatureText: String {
        guard let batteryTemperature else { return "接口未返回" }
        return "\(Self.numberText(batteryTemperature, maximumFractionDigits: 1)) °C"
    }

    var enduranceText: String {
        guard let endurance else { return "-- km" }
        return "\(Self.decimalFormatter.string(from: NSNumber(value: endurance)) ?? "--") km"
    }

    var aiEstimatedMileageText: String {
        guard let aiEstimatedMileage else { return "接口未返回" }
        return "\(Self.numberText(aiEstimatedMileage, maximumFractionDigits: 1)) km"
    }

    var lockText: String {
        guard let isLocked else { return "未知" }
        return isLocked ? "已锁" : "未锁"
    }

    var powerText: String {
        if isFullyCharged { return "已充满" }
        if isCharging == true { return "充电中" }
        guard let isPoweredOn else { return "离线" }
        return isPoweredOn ? "已上电" : "已熄火"
    }

    var primaryStatusText: String {
        health.title
    }

    var monthMileageText: String {
        guard let monthMileage else { return "-- km" }
        return "\(Self.decimalFormatter.string(from: NSNumber(value: monthMileage)) ?? "--") km"
    }

    var totalMileageText: String {
        guard let totalMileage else { return "-- km" }
        return "\(Self.decimalFormatter.string(from: NSNumber(value: totalMileage)) ?? "--") km"
    }

    var remainingChargeTimeText: String {
        guard let remainingChargeTime else { return "未知" }
        return Self.durationText(minutes: remainingChargeTime)
    }

    var estimatedChargeTo80Minutes: Double? {
        guard isCharging == true else { return nil }
        guard let battery else { return nil }

        let level = min(max(Double(battery), 0), 100)
        guard level < 80 else { return 0 }

        let minutes = (80 - level) * Self.fastMinutesPerPercent
        return (minutes / 5).rounded(.up) * 5
    }

    var estimatedChargeTo80TimeText: String {
        guard isCharging == true else { return "未充电" }
        guard let estimatedChargeTo80Minutes else { return "计算中" }
        guard estimatedChargeTo80Minutes > 0 else { return "已超过 80%" }
        return Self.durationText(minutes: estimatedChargeTo80Minutes)
    }

    var estimatedChargeTo80ClockText: String {
        guard isCharging == true, let estimatedChargeTo80Minutes else { return "--" }
        guard estimatedChargeTo80Minutes > 0 else { return "已超过 80%" }
        return Self.clockFormatter.string(from: updatedAt.addingTimeInterval(estimatedChargeTo80Minutes * 60))
    }

    var estimatedFullChargeMinutes: Double? {
        guard isCharging == true else { return nil }
        guard let battery else { return remainingChargeTime }

        let level = min(max(Double(battery), 0), 100)
        guard level < 100 else { return 0 }

        let fastPercentRemaining = max(min(Self.fastChargeUpperBound, 100) - min(level, Self.fastChargeUpperBound), 0)
        let taperPercentRemaining = max(100 - max(level, Self.fastChargeUpperBound), 0)
        let minutes = fastPercentRemaining * Self.fastMinutesPerPercent + taperPercentRemaining * Self.taperMinutesPerPercent
        return (minutes / 5).rounded(.up) * 5
    }

    var estimatedFullChargeTimeText: String {
        guard isCharging == true else { return "未充电" }
        guard let estimatedFullChargeMinutes else { return "计算中" }
        guard estimatedFullChargeMinutes > 0 else { return "已充满" }
        return Self.durationText(minutes: estimatedFullChargeMinutes)
    }

    var estimatedFullChargeClockText: String {
        guard isCharging == true, let estimatedFullChargeMinutes else { return "--" }
        guard estimatedFullChargeMinutes > 0 else { return "已充满" }
        return Self.clockFormatter.string(from: updatedAt.addingTimeInterval(estimatedFullChargeMinutes * 60))
    }

    var chargeSummaryText: String {
        if isFullyCharged { return "已充满" }
        guard let isCharging else { return "充电未知" }
        return isCharging ? "充电中 · 约 \(estimatedFullChargeTimeText) 充满" : "未充电"
    }

    var chargingStateText: String {
        if isFullyCharged { return "已充满" }
        guard let isCharging else { return "未知" }
        return isCharging ? "充电中" : "未充电"
    }

    var isFullyCharged: Bool {
        if let battery, battery >= 100 {
            return true
        }
        return isCharging == true && estimatedFullChargeMinutes == 0
    }

    var locationText: String {
        guard let locationDescription, !locationDescription.isEmpty else { return "未知位置" }
        return locationDescription
    }

    var rangePerBatteryPercent: Double? {
        guard let battery, battery > 0, let endurance else { return nil }
        return max(endurance, 0) / Double(battery)
    }

    var rangePerBatteryPercentText: String {
        guard let rangePerBatteryPercent else { return "-- km/%" }
        return "\(Self.numberText(rangePerBatteryPercent, maximumFractionDigits: 2)) km/%"
    }

    var observedKmPerBatteryPercent: Double? {
        let samples = observedRangeSamples
        let totalMileage = samples.reduce(0) { $0 + $1.mileage }
        let totalUsedBattery = samples.reduce(0) { $0 + $1.usedBattery }
        guard totalMileage > 0, totalUsedBattery > 0 else { return nil }
        return totalMileage / totalUsedBattery
    }

    var observedRangeSampleCount: Int {
        observedRangeSamples.count
    }

    var rangeEstimateAccuracy: Double? {
        let ratios = observedRangeRatios
        guard !ratios.isEmpty else { return nil }

        let consistencyScore = observedRangeConsistencyScore ?? 0.55

        let sampleScore = min(Double(ratios.count) / 10, 1)
        let comparisonScore: Double
        if let observedEstimatedMileage, let interfaceEstimatedMileage {
            let denominator = max(max(observedEstimatedMileage, interfaceEstimatedMileage), 1)
            let delta = abs(observedEstimatedMileage - interfaceEstimatedMileage) / denominator
            comparisonScore = max(0, 1 - min(delta, 0.7) / 0.7)
        } else {
            comparisonScore = 0.7
        }

        let score = 0.35 + sampleScore * 0.35 + consistencyScore * 0.2 + comparisonScore * 0.1
        return min(max(score, 0.35), 0.96)
    }

    var rangeEstimateAccuracyText: String {
        guard let rangeEstimateAccuracy else { return "样本不足" }
        return "\(Self.numberText(rangeEstimateAccuracy * 100, maximumFractionDigits: 0))%"
    }

    var rangeEstimateAccuracyDetailText: String {
        guard observedRangeSampleCount > 0 else { return "等待有效行程样本" }
        return "基于 \(observedRangeSampleCount) 次有效行程"
    }

    var localEstimatedMileage: Double? {
        if let interfaceEstimatedMileage, let observedEstimatedMileage {
            let weight = observedRangeBlendWeight ?? 0.18
            return max(interfaceEstimatedMileage + (observedEstimatedMileage - interfaceEstimatedMileage) * weight, 0)
        }
        if let observedEstimatedMileage {
            return max(observedEstimatedMileage, 0)
        }
        return interfaceEstimatedMileage
    }

    var localEstimatedMileageText: String {
        guard let localEstimatedMileage else { return "-- km" }
        return "\(Self.numberText(localEstimatedMileage, maximumFractionDigits: 1)) km"
    }

    var localEstimateBasisText: String {
        if let observedKmPerBatteryPercent, interfaceEstimatedMileage != nil {
            return "结合接口续航和 \(observedRangeSampleCount) 次行程，约 \(Self.numberText(observedKmPerBatteryPercent, maximumFractionDigits: 2)) km/%。"
        }
        if let observedKmPerBatteryPercent {
            return "按 \(observedRangeSampleCount) 次行程估算，约 \(Self.numberText(observedKmPerBatteryPercent, maximumFractionDigits: 2)) km/%。"
        }
        if rangePerBatteryPercent != nil {
            return "按接口续航估算。"
        }
        return "刷新更多行程后生成估算。"
    }

    var monthEnergyPerKm: Double? {
        guard let monthMileage, monthMileage > 0 else { return nil }
        guard let energy = monthUsedElectricity ?? monthEnergy else { return nil }
        return energy / monthMileage
    }

    var monthEnergyPerKmText: String {
        guard let monthEnergyPerKm else { return "-- Wh/km" }
        return "\(Self.numberText(monthEnergyPerKm, maximumFractionDigits: 1)) Wh/km"
    }

    var lastEnergyPerKm: Double? {
        guard let lastMileage, lastMileage > 0 else { return nil }
        guard let lastEnergy else { return nil }
        return lastEnergy / lastMileage
    }

    var lastEnergyPerKmText: String {
        guard let lastEnergyPerKm else { return "-- Wh/km" }
        return "\(Self.numberText(lastEnergyPerKm, maximumFractionDigits: 1)) Wh/km"
    }

    var dailyAverageMileageText: String {
        guard let monthMileage else { return "-- km/日" }
        let day = max(Calendar.current.component(.day, from: updatedAt), 1)
        let value = monthMileage / Double(day)
        return "\(Self.numberText(value, maximumFractionDigits: 1)) km/日"
    }

    var todayMileage: Double? {
        if let record = dailyMileages.last(where: { record in
            guard let date = record.date else { return false }
            return Calendar.current.isDateInToday(date)
        }) {
            return record.mileage
        }

        let currentDay = Calendar.current.component(.day, from: updatedAt)
        return dailyMileages.last(where: { $0.day == currentDay })?.mileage
    }

    var todayMileageText: String {
        guard let todayMileage else { return "-- km" }
        return "\(Self.numberText(todayMileage, maximumFractionDigits: 1)) km"
    }

    var monthEstimatedCostText: String {
        guard let electricityWh = monthUsedElectricity ?? monthEnergy else { return "--" }
        return "¥\(Self.numberText(electricityWh / 1000 * Self.electricityPricePerKWh, maximumFractionDigits: 1, minimumFractionDigits: 1))"
    }

    var lastRideSummaryText: String {
        let mileage = lastMileage.map { "\(Self.numberText($0, maximumFractionDigits: 1)) km" } ?? "-- km"
        let energy = lastEnergy.map { "\(Self.numberText($0, maximumFractionDigits: 0)) Wh" } ?? "-- Wh"
        return "\(mileage) · \(energy)"
    }

    var latestSpeed: Double? {
        rides.compactMap(rideSpeed).first
    }

    var averageSpeed: Double? {
        let samples = rides.compactMap(rideSpeed)
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var latestSpeedText: String {
        guard let latestSpeed else { return "-- km/h" }
        return "\(Self.numberText(latestSpeed, maximumFractionDigits: 1)) km/h"
    }

    var averageSpeedText: String {
        guard let averageSpeed else { return "-- km/h" }
        return "\(Self.numberText(averageSpeed, maximumFractionDigits: 1)) km/h"
    }

    var rides: [NinebotRideRecord] {
        Self.deduplicatedRideRecords(rideRecords ?? [])
    }

    var dailyMileages: [NinebotDailyMileageRecord] {
        dailyMileageRecords ?? []
    }

    var health: NinebotVehicleHealth {
        if isFullyCharged {
            return NinebotVehicleHealth(
                level: .good,
                title: "已充满",
                message: "电量已满，可以拔掉充电器",
                systemImage: "battery.100"
            )
        }

        if isCharging == true {
            return NinebotVehicleHealth(
                level: .charging,
                title: "充电中",
                message: "约 \(estimatedFullChargeTimeText) 充满，\(estimatedFullChargeClockText) 左右",
                systemImage: "bolt.fill"
            )
        }

        if let battery, battery < 15 {
            return NinebotVehicleHealth(
                level: .critical,
                title: "低电量",
                message: "当前 \(battery)%，建议尽快充电",
                systemImage: "exclamationmark.triangle.fill"
            )
        }

        if isLocked == false {
            return NinebotVehicleHealth(
                level: .attention,
                title: "未锁车",
                message: "车辆未锁定，请确认停放环境",
                systemImage: "lock.open.fill"
            )
        }

        if let battery, battery < 25 {
            return NinebotVehicleHealth(
                level: .attention,
                title: "电量偏低",
                message: "当前 \(battery)%，续航约 \(enduranceText)",
                systemImage: "battery.25"
            )
        }

        if isLocked == true || isPoweredOn == false {
            return NinebotVehicleHealth(
                level: .good,
                title: "状态正常",
                message: "车辆已停放，续航约 \(enduranceText)",
                systemImage: "checkmark.shield.fill"
            )
        }

        return NinebotVehicleHealth(
            level: .unknown,
            title: "状态未知",
            message: "部分车况字段暂未返回",
            systemImage: "questionmark.circle.fill"
        )
    }

    var warningTexts: [String] {
        var warnings: [String] = []
        if let battery, battery < 15 {
            warnings.append("电量低于 15%，建议尽快充电")
        } else if let battery, battery < 25 {
            warnings.append("电量偏低，出门前建议确认续航")
        }
        if isPoweredOn == false {
            warnings.append("上电状态为 0，请确认车辆电源")
        }
        if isLocked == false {
            warnings.append("车辆当前未锁车")
        }
        return warnings
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let fastChargeUpperBound = 80.0
    private static let fastMinutesPerPercent = 4.0
    private static let taperMinutesPerPercent = 7.0
    private static let electricityPricePerKWh = 0.6
    private static let minimumObservedKmPerPercent = 0.2
    private static let maximumObservedKmPerPercent = 3.0

    private static func deduplicatedRideRecords(_ records: [NinebotRideRecord]) -> [NinebotRideRecord] {
        var seenKeys = Set<String>()
        var result: [NinebotRideRecord] = []

        for record in records {
            let key = record.stableIdentityKey
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            result.append(record)
        }

        return result
    }

    private var interfaceEstimatedMileage: Double? {
        if let endurance {
            return max(endurance, 0)
        }
        if let aiEstimatedMileage {
            return max(aiEstimatedMileage, 0)
        }
        return nil
    }

    private var normalizedBatteryPercent: Double? {
        guard let battery else { return nil }
        return min(max(Double(battery), 0), 100)
    }

    private var observedEstimatedMileage: Double? {
        guard let normalizedBatteryPercent, let observedKmPerBatteryPercent else { return nil }
        return max(observedKmPerBatteryPercent * normalizedBatteryPercent, 0)
    }

    private var observedRangeSamples: [(mileage: Double, usedBattery: Double)] {
        rides.compactMap { ride in
            guard let mileage = ride.mileage, mileage > 0.1,
                  let usedBattery = ride.usedElectricity, usedBattery > 0, usedBattery <= 100 else {
                return nil
            }

            let ratio = mileage / usedBattery
            guard ratio >= Self.minimumObservedKmPerPercent,
                  ratio <= Self.maximumObservedKmPerPercent else {
                return nil
            }

            return (mileage, usedBattery)
        }
    }

    private var observedRangeRatios: [Double] {
        observedRangeSamples.map { $0.mileage / $0.usedBattery }
    }

    private var observedRangeConsistencyScore: Double? {
        let ratios = observedRangeRatios
        guard !ratios.isEmpty else { return nil }
        guard ratios.count >= 2 else { return 0.55 }

        let mean = ratios.reduce(0, +) / Double(ratios.count)
        guard mean > 0 else { return 0 }

        let variance = ratios.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(ratios.count)
        let coefficientOfVariation = sqrt(variance) / mean
        return max(0, 1 - min(coefficientOfVariation, 0.6) / 0.6)
    }

    private var observedRangeBlendWeight: Double? {
        guard observedRangeSampleCount > 0 else { return nil }

        let sampleScore = min(Double(observedRangeSampleCount) / 12, 1)
        let consistencyScore = observedRangeConsistencyScore ?? 0.55
        let weight = 0.12 + sampleScore * 0.53 + consistencyScore * 0.25
        return min(max(weight, 0.18), 0.85)
    }

    private func rideSpeed(_ ride: NinebotRideRecord) -> Double? {
        if let speed = ride.speed, speed > 0 {
            return speed
        }
        guard let mileage = ride.mileage, mileage > 0,
              let durationMinutes = ride.durationMinutes, durationMinutes > 0 else {
            return nil
        }
        return mileage / (durationMinutes / 60)
    }

    private static func durationText(minutes: Double) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return "\(decimalFormatter.string(from: NSNumber(value: hours)) ?? "--") 小时"
        }
        return "\(decimalFormatter.string(from: NSNumber(value: minutes)) ?? "--") 分钟"
    }

    private static func numberText(
        _ value: Double,
        maximumFractionDigits: Int,
        minimumFractionDigits: Int = 0
    ) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = minimumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct NinebotVehicleHistoryPoint: Codable, Equatable, Identifiable {
    var id: String
    var sn: String
    var date: Date
    var battery: Int?
    var endurance: Double?
    var totalMileage: Double?
    var isCharging: Bool?
    var isLocked: Bool?
    var isPoweredOn: Bool?

    init(sn: String, state: NinebotVehicleState) {
        self.sn = sn
        self.date = state.updatedAt
        self.battery = state.battery
        self.endurance = state.endurance
        self.totalMileage = state.totalMileage
        self.isCharging = state.isCharging
        self.isLocked = state.isLocked
        self.isPoweredOn = state.isPoweredOn
        self.id = "\(sn)-\(Int(state.updatedAt.timeIntervalSince1970))"
    }
}

struct NinebotVehicleHistorySummary: Equatable {
    var first: NinebotVehicleHistoryPoint
    var latest: NinebotVehicleHistoryPoint
    var sampleCount: Int

    init?(points: [NinebotVehicleHistoryPoint]) {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first, let latest = sorted.last else { return nil }
        self.first = first
        self.latest = latest
        self.sampleCount = sorted.count
    }

    var batteryDelta: Int? {
        guard let first = first.battery, let latest = latest.battery else { return nil }
        return latest - first
    }

    var mileageDelta: Double? {
        guard let first = first.totalMileage, let latest = latest.totalMileage else { return nil }
        return latest - first
    }

    var periodText: String {
        let seconds = latest.date.timeIntervalSince(first.date)
        guard seconds > 0 else { return "刚刚开始记录" }
        let hours = seconds / 3600
        if hours >= 24 {
            return "\(Self.numberText(hours / 24, maximumFractionDigits: 1)) 天"
        }
        if hours >= 1 {
            return "\(Self.numberText(hours, maximumFractionDigits: 1)) 小时"
        }
        return "\(Self.numberText(seconds / 60, maximumFractionDigits: 0)) 分钟"
    }

    var batteryDeltaText: String {
        guard let batteryDelta else { return "--%" }
        return "\(batteryDelta >= 0 ? "+" : "")\(batteryDelta)%"
    }

    var mileageDeltaText: String {
        guard let mileageDelta else { return "-- km" }
        return "\(mileageDelta >= 0 ? "+" : "")\(Self.numberText(mileageDelta, maximumFractionDigits: 1)) km"
    }

    private static func numberText(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct NinebotResolvedAddress: Codable, Equatable {
    var sn: String
    var address: String
    var latitude: Double
    var longitude: Double
    var updatedAt: Date
    var source: String?
}

struct NinebotVehicleSnapshot: Codable, Equatable, Identifiable {
    var vehicle: NinebotVehicleInfo
    var state: NinebotVehicleState

    var id: String { vehicle.sn }
}

struct NinebotDashboard: Codable, Equatable {
    var vehicles: [NinebotVehicleSnapshot]
    var selectedSN: String?
    var updatedAt: Date

    var primaryVehicle: NinebotVehicleSnapshot? {
        if let selectedSN, let selected = vehicles.first(where: { $0.vehicle.sn == selectedSN }) {
            return selected
        }
        return vehicles.first
    }

    static let empty = NinebotDashboard(vehicles: [], selectedSN: nil, updatedAt: .distantPast)

    static let preview = NinebotDashboard(
        vehicles: [
            NinebotVehicleSnapshot(
                vehicle: NinebotVehicleInfo(
                    sn: "NINEBOT-DEMO",
                    name: "我的九号",
                    model: "Ninebot E-bike",
                    imageURLString: nil,
                    raw: [
                        "device_name": .string("我的九号"),
                        "wnumber": .string("NINEBOT-DEMO"),
                        "vehicle_name": .string("Ninebot E-bike")
                    ]
                ),
                state: NinebotVehicleState(
                    battery: 86,
                    batteryVoltage: 52.3,
                    batteryTemperature: 28.5,
                    endurance: 42.5,
                    aiEstimatedMileage: 38.2,
                    isCharging: false,
                    isPoweredOn: false,
                    isLocked: true,
                    remainingChargeTime: nil,
                    locationDescription: "河畔花园",
                    latitude: nil,
                    longitude: nil,
                    totalMileage: 1048.9,
                    monthMileage: 128.4,
                    monthEnergy: 3200,
                    monthUsedElectricity: 2800,
                    lastMileage: 4.6,
                    lastEnergy: 200,
                    lastUsedElectricity: 4,
                    rideRecords: [
                        NinebotRideRecord(
                            id: "preview-ride-1",
                            startedAt: Date().addingTimeInterval(-7200),
                            endedAt: Date().addingTimeInterval(-6600),
                            mileage: 4.6,
                            energy: 200,
                            usedElectricity: 4,
                            durationMinutes: 10,
                            speed: 27.6,
                            raw: nil
                        )
                    ],
                    dailyMileageRecords: [
                        NinebotDailyMileageRecord(id: "preview-1", day: 1, date: Date().addingTimeInterval(-345600), mileage: 12.3),
                        NinebotDailyMileageRecord(id: "preview-2", day: 2, date: Date().addingTimeInterval(-259200), mileage: 4.8),
                        NinebotDailyMileageRecord(id: "preview-3", day: 3, date: Date().addingTimeInterval(-172800), mileage: 18.5),
                        NinebotDailyMileageRecord(id: "preview-4", day: 4, date: Date().addingTimeInterval(-86400), mileage: 9.7),
                        NinebotDailyMileageRecord(id: "preview-5", day: 5, date: Date(), mileage: 6.7)
                    ],
                    updatedAt: Date(),
                    rawStatus: [
                        "dump_energy": .number(86),
                        "precise_estimate_mileage": .number(42.5),
                        "charging": .number(0),
                        "pwr": .number(0),
                        "loc": .object([
                            "lock": .number(1),
                            "lat": .number(31.2304),
                            "lon": .number(121.4737)
                        ])
                    ],
                    rawTravel: [
                        "total_mileages": .number(128.4),
                        "ec": .number(3.2),
                        "used_electricity": .number(2.8)
                    ]
                )
            )
        ],
        selectedSN: "NINEBOT-DEMO",
        updatedAt: Date()
    )
}

enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: JSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: DynamicCodingKey(key))
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case .string(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .number(let number):
            var container = encoder.singleValueContainer()
            try container.encode(number)
        case .bool(let bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var stringValue: String? {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let number):
            return number
        case .string(let string):
            return Double(string)
        case .bool(let bool):
            return bool ? 1 : 0
        default:
            return nil
        }
    }

    var intValue: Int? {
        guard let doubleValue else { return nil }
        return Int(doubleValue)
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let bool):
            return bool
        case .number(let number):
            return number != 0
        case .string(let string):
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(normalized) { return true }
            if ["0", "false", "no", "off"].contains(normalized) { return false }
            return nil
        default:
            return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    var displayText: String {
        switch self {
        case .object(let object):
            if object.isEmpty { return "{}" }
            return object
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.displayText)" }
                .joined(separator: ", ")
        case .array(let array):
            if array.isEmpty { return "[]" }
            return array.map(\.displayText).joined(separator: ", ")
        case .string(let string):
            return string
        case .number(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(_ intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.init(intValue)
    }
}
