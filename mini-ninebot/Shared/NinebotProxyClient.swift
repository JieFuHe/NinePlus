import Foundation

enum NinebotProxyError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "代理地址无效"
        case .invalidResponse:
            return "代理返回的数据格式无效"
        case .server(let message):
            return message
        case .httpStatus(let statusCode, let message):
            if message.isEmpty {
                return "HTTP \(statusCode)"
            }
            return "HTTP \(statusCode): \(message)"
        }
    }
}

struct NinebotProxyClient {
    var configuration: NinebotProxyConfiguration
    var session: URLSession = .shared

    func healthCheck() async throws {
        _ = try await request(method: "GET", path: ["healthz"])
    }

    func login(account: String, password: String) async throws -> NinebotLoginResult {
        let payload = try await request(
            method: "POST",
            path: ["auth", "login"],
            body: [
                "account": account,
                "password": password,
            ]
        )
        return Self.loginResult(from: payload)
    }

    func sendLoginCode(account: String) async throws {
        _ = try await request(
            method: "POST",
            path: ["auth", "login-code"],
            body: ["account": account]
        )
    }

    func consumeLoginCode(account: String, code: String) async throws -> NinebotLoginResult {
        let payload = try await request(
            method: "POST",
            path: ["auth", "login-code", "consume"],
            body: [
                "account": account,
                "code": code,
            ]
        )
        return Self.loginResult(from: payload)
    }

    func refreshAccessToken() async throws {
        _ = try await request(method: "POST", path: ["auth", "refresh"])
    }

    func ringBell(sn: String) async throws -> JSONValue {
        try await request(method: "POST", path: ["vehicles", sn, "bell"])
    }

    func openBucket(sn: String) async throws -> JSONValue {
        try await request(method: "POST", path: ["vehicles", sn, "buck"])
    }

    func engineStart(sn: String) async throws -> JSONValue {
        try await request(method: "POST", path: ["vehicles", sn, "engine", "start"])
    }

    func engineStop(sn: String) async throws -> JSONValue {
        try await request(method: "POST", path: ["vehicles", sn, "engine", "stop"])
    }

    func fetchDashboard(selectedSN: String? = nil) async throws -> NinebotDashboard {
        let vehiclesPayload = try await request(method: "GET", path: ["vehicles"])
        let vehicleValues = Self.arrayPayload(from: vehiclesPayload, preferredKeys: ["vehicles", "data"])
        let vehicles = vehicleValues.compactMap(Self.vehicleInfo)
        let currentMonth = Self.currentMonthString()

        var snapshots: [NinebotVehicleSnapshot] = []
        for vehicle in vehicles {
            let status = try? await request(method: "GET", path: ["vehicles", vehicle.sn, "status"])
            let travel = try? await fetchTravel(sn: vehicle.sn, month: currentMonth)
            let battery = try? await request(method: "GET", path: ["vehicles", vehicle.sn, "battery"])
            let monthlyTravels = await fetchMonthlyTravels(
                sn: vehicle.sn,
                authDate: vehicle.authDate,
                currentMonth: currentMonth,
                currentTravel: travel
            )
            var state = Self.vehicleState(status: status, travel: travel, battery: battery, updatedAt: Date())
            if let totalMileage = Self.totalMileage(fromMonthlyTravels: monthlyTravels) {
                state.totalMileage = totalMileage
            }
            let resolvedVehicle = Self.vehicleInfo(vehicle, addingImageFrom: status, battery: battery)
            snapshots.append(NinebotVehicleSnapshot(vehicle: resolvedVehicle, state: state))
        }

        let resolvedSelectedSN: String?
        if let selectedSN, snapshots.contains(where: { $0.vehicle.sn == selectedSN }) {
            resolvedSelectedSN = selectedSN
        } else {
            resolvedSelectedSN = snapshots.first?.vehicle.sn
        }

        return NinebotDashboard(
            vehicles: snapshots,
            selectedSN: resolvedSelectedSN,
            updatedAt: Date()
        )
    }

    func fetchTravelDetail(sn: String, travelID: String) async throws -> NinebotRideDetail {
        let payload = try await request(
            method: "GET",
            path: ["vehicles", sn, "travel", travelID]
        )

        return NinebotRideDetail(
            vehicleSN: sn,
            rideID: travelID,
            fetchedAt: Date(),
            raw: payload,
            parsedRecord: Self.rideRecord(from: payload, index: 0)
        )
    }

    private func fetchTravel(sn: String, month: String) async throws -> JSONValue {
        try await request(
            method: "GET",
            path: ["vehicles", sn, "travel"],
            queryItems: [URLQueryItem(name: "month", value: month)]
        )
    }

    private func fetchMonthlyTravels(
        sn: String,
        authDate: Date?,
        currentMonth: String,
        currentTravel: JSONValue?
    ) async -> [JSONValue]? {
        let months = Self.monthStrings(from: authDate, through: Date())
        guard !months.isEmpty else {
            return currentTravel.map { [$0] }
        }

        var payloads: [JSONValue] = []
        for month in months {
            if month == currentMonth, let currentTravel {
                payloads.append(currentTravel)
                continue
            }

            do {
                payloads.append(try await fetchTravel(sn: sn, month: month))
            } catch {
                return nil
            }
        }
        return payloads
    }

    func registerPushDevice(token: String, bundleID: String, environment: String) async throws {
        _ = try await request(
            method: "POST",
            path: ["devices", "register"],
            body: [
                "token": token,
                "bundle_id": bundleID,
                "environment": environment,
            ]
        )
    }

    private func request(
        method: String,
        path: [String],
        queryItems: [URLQueryItem] = [],
        body: [String: String]? = nil
    ) async throws -> JSONValue {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = configuration.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NinebotProxyError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            throw NinebotProxyError.httpStatus(httpResponse.statusCode, Self.errorMessage(from: data))
        }

        if data.isEmpty {
            return .object([:])
        }

        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        return try Self.unwrapEnvelope(root)
    }

    private func buildURL(path: [String], queryItems: [URLQueryItem]) throws -> URL {
        guard var url = configuration.baseURL else {
            throw NinebotProxyError.invalidBaseURL
        }

        for component in path {
            url.appendPathComponent(component)
        }

        guard !queryItems.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NinebotProxyError.invalidBaseURL
        }
        components.queryItems = queryItems
        guard let finalURL = components.url else {
            throw NinebotProxyError.invalidBaseURL
        }
        return finalURL
    }
}

private extension NinebotProxyClient {
    static func unwrapEnvelope(_ root: JSONValue) throws -> JSONValue {
        guard let object = root.objectValue, object.keys.contains("ok") else {
            return root
        }

        if object["ok"]?.boolValue == true {
            return object["data"] ?? .object([:])
        }

        let error = object["error"]?.objectValue
        let message = error?["message"]?.stringValue
            ?? error?["code"]?.stringValue
            ?? "九号代理请求失败"
        throw NinebotProxyError.server(message)
    }

    static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let root = try? JSONDecoder().decode(JSONValue.self, from: data) {
            if let object = root.objectValue {
                if let error = object["error"]?.objectValue {
                    return error["message"]?.stringValue ?? error["code"]?.stringValue ?? ""
                }
                return object["message"]?.stringValue ?? ""
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func loginResult(from value: JSONValue) -> NinebotLoginResult {
        let object = value.objectValue ?? [:]
        return NinebotLoginResult(
            uuid: object["uuid"]?.stringValue,
            phone: object["phone"]?.stringValue,
            areaCode: object["area_code"]?.stringValue,
            region: object["region"]?.stringValue,
            businessUID: object["business_uid"]?.stringValue
        )
    }

    static func arrayPayload(from value: JSONValue, preferredKeys: [String]) -> [JSONValue] {
        if let array = value.arrayValue {
            return array
        }

        guard let object = value.objectValue else {
            return []
        }

        for key in preferredKeys {
            if let array = object[key]?.arrayValue {
                return array
            }
        }

        return []
    }

    static func vehicleInfo(from value: JSONValue) -> NinebotVehicleInfo? {
        guard let object = value.objectValue else { return nil }
        guard let sn = firstString(["wnumber", "sn"], in: object), !sn.isEmpty else {
            return nil
        }

        var model = firstString(["vehicle_name_en", "vehicle_name", "model", "vehicleModel"], in: object) ?? sn
        if let vehicleType = object["vehicle_type"]?.stringValue, !vehicleType.isEmpty {
            model = "\(model) (\(vehicleType))"
        }

        return NinebotVehicleInfo(
            sn: sn,
            name: firstString(["device_name", "deviceName", "ble_name"], in: object) ?? sn,
            model: model,
            imageURLString: firstString(["v6_light_img_url", "img_url", "img"], in: object),
            raw: object
        )
    }

    static func vehicleInfo(_ vehicle: NinebotVehicleInfo, addingImageFrom status: JSONValue?, battery: JSONValue?) -> NinebotVehicleInfo {
        guard vehicle.imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return vehicle
        }

        let statusObject = status?.objectValue ?? [:]
        let batteryObject = battery?.objectValue ?? [:]
        guard let imageURLString = firstString(
            ["v6_light_img_url", "v6LightImgUrl", "img_url", "imgUrl", "img", "image_url", "imageUrl"],
            in: statusObject
        ) ?? firstString(
            ["v6_light_img_url", "v6LightImgUrl", "img_url", "imgUrl", "img", "image_url", "imageUrl"],
            in: batteryObject
        ) else {
            return vehicle
        }

        var resolved = vehicle
        resolved.imageURLString = imageURLString
        return resolved
    }

    static func vehicleState(status: JSONValue?, travel: JSONValue?, battery: JSONValue? = nil, updatedAt: Date) -> NinebotVehicleState {
        let statusObject = status?.objectValue ?? [:]
        let travelObject = travel?.objectValue ?? [:]
        let batteryPayloadObject = battery?.objectValue ?? [:]
        let batteryObject = firstObject(["battery", "batteryInfo", "battery_info", "bms", "bmsInfo", "bms_info"], in: statusObject) ?? [:]
        let batteryListObject = firstArrayObject(["battery_list", "batteryList", "batteries"], in: batteryPayloadObject) ?? [:]
        let batteryMainObject = firstObject(["battery_main", "batteryMain"], in: batteryPayloadObject) ?? [:]
        let batterySources = [statusObject, batteryObject, batteryPayloadObject, batteryListObject, batteryMainObject]
        let loc = statusObject["loc"]?.objectValue
        let locationInfo = statusObject["locationInfo"]?.objectValue
        let lockNumber = loc?["lock"]?.intValue ?? statusObject["lock_status"]?.intValue
        let rides = travelObject["list"]?.arrayValue ?? []
        let rideRecords = rides.enumerated().compactMap { index, value in
            rideRecord(from: value, index: index)
        }
        let lastRide = rideRecords.first
        let dailyMileageRecords = dailyMileageRecords(from: travelObject)

        return NinebotVehicleState(
            battery: firstInt(["dump_energy", "dumpEnergy"], in: statusObject)
                ?? firstInt(["electricity", "dump_energy", "dumpEnergy"], in: batteryPayloadObject)
                ?? firstInt(["electricity", "dump_energy", "dumpEnergy"], in: batteryListObject),
            batteryVoltage: normalizedBatteryVoltage(
                firstDouble(
                    [
                        "battery_voltage",
                        "batteryVoltage",
                        "battery_vol",
                        "batteryVol",
                        "batt_voltage",
                        "battVoltage",
                        "bat_voltage",
                        "batVoltage",
                        "bms_voltage",
                        "bmsVoltage",
                        "bms_volt",
                        "bmsVolt",
                        "voltage",
                        "volt"
                    ],
                    in: batterySources
                )
            ),
            batteryTemperature: normalizedBatteryTemperature(
                firstDouble(
                    [
                        "battery_temperature",
                        "batteryTemperature",
                        "battery_temp",
                        "batteryTemp",
                        "batt_temperature",
                        "battTemperature",
                        "batt_temp",
                        "battTemp",
                        "bat_temperature",
                        "batTemperature",
                        "bat_temp",
                        "batTemp",
                        "bms_temperature",
                        "bmsTemperature",
                        "bms_temp",
                        "bmsTemp",
                        "bat_temp",
                        "batTemp",
                        "temperature",
                        "temp"
                    ],
                    in: batterySources
                )
            ),
            batteryCycleCount: firstInt(["bms_cycle", "bmsCycle", "cycle", "cycles"], in: batteryListObject)
                ?? firstInt(["bms_cycle", "bmsCycle", "cycle", "cycles"], in: batteryPayloadObject),
            chargingPower: firstDouble(["charging_power", "chargingPower", "charge_power", "chargePower"], in: batteryPayloadObject),
            endurance: firstDouble(["precise_estimate_mileage", "preciseEstimateMileage", "estimate_mileage", "estimateMileage"], in: statusObject),
            aiEstimatedMileage: firstDouble(["ai_estimate_mileage", "aiEstimateMileage", "ai_estimated_mileage", "aiEstimatedMileage"], in: statusObject),
            isCharging: firstBoolLike(["charging", "chargingState"], in: statusObject, trueValue: 1)
                ?? firstBoolLike(["charging", "chargingState"], in: batteryPayloadObject, trueValue: 1),
            isPoweredOn: firstBoolLike(["pwr", "powerStatus"], in: statusObject, trueValue: 1),
            isLocked: lockNumber.map { $0 == 1 },
            remainingChargeTime: firstDouble(["remain_charge_time", "remainChargeTime", "remainingChargeTime"], in: statusObject)
                ?? firstDouble(["remain_charge_time", "remainChargeTime", "remainingChargeTime"], in: batteryPayloadObject),
            locationDescription: firstString(["locationDesc", "desc"], in: locationInfo ?? [:]),
            latitude: normalizedCoordinate(
                loc?["lat"]?.doubleValue ?? locationInfo?["lat"]?.doubleValue,
                limit: 90
            ),
            longitude: normalizedCoordinate(
                loc?["lon"]?.doubleValue ?? locationInfo?["lon"]?.doubleValue,
                limit: 180
            ),
            totalMileage: firstDouble(["total_mileage", "totalMileage", "total_mileages"], in: statusObject)
                ?? firstDouble(["total_mileage", "totalMileage"], in: travelObject),
            monthMileage: firstDouble(["total_mileages", "monthMileage"], in: travelObject),
            monthEnergy: firstDouble(["ec", "monthEnergy"], in: travelObject),
            monthUsedElectricity: firstDouble(["used_electricity", "usedElectricity"], in: travelObject),
            lastMileage: lastRide?.mileage,
            lastEnergy: lastRide?.energy,
            lastUsedElectricity: lastRide?.usedElectricity,
            rideRecords: rideRecords.isEmpty ? nil : rideRecords,
            dailyMileageRecords: dailyMileageRecords.isEmpty ? nil : dailyMileageRecords,
            updatedAt: updatedAt,
            rawStatus: statusObject.isEmpty ? nil : statusObject,
            rawTravel: travelObject.isEmpty ? nil : travelObject,
            rawBattery: batteryPayloadObject.isEmpty ? nil : batteryPayloadObject
        )
    }

    static func normalizedCoordinate(_ value: Double?, limit: Double) -> Double? {
        guard let value else { return nil }
        if abs(value) <= limit { return value }

        for divisor in [1_000_000.0, 10_000_000.0, 100_000.0] {
            let normalized = value / divisor
            if abs(normalized) <= limit {
                return normalized
            }
        }

        return nil
    }

    static func rideRecord(from value: JSONValue, index: Int) -> NinebotRideRecord? {
        guard let object = value.objectValue else { return nil }
        let startedAt = firstDate(
            ["start_time", "startTime", "begin_time", "beginTime", "stime", "date", "day", "create_time", "createTime"],
            in: object
        )
        let endedAt = firstDate(
            ["end_time", "endTime", "stop_time", "stopTime", "etime", "finish_time", "finishTime"],
            in: object
        )
        let mileage = firstDouble(["mileages", "mileage", "distance", "rideMileage"], in: object)
        let energy = firstDouble(["ec", "energy", "electricity", "consume"], in: object)
        let usedElectricity = firstDouble(["used_electricity", "usedElectricity", "usedElectric", "useElectricity"], in: object)
        let durationMinutes = firstDurationMinutes(in: object, startedAt: startedAt, endedAt: endedAt)
        let speed = firstDouble(["speed", "avg_speed", "avgSpeed", "average_speed", "averageSpeed"], in: object)

        let id = firstString(["travel_id", "travelId", "ride_id", "rideId", "record_id", "recordId", "id"], in: object)
            ?? startedAt.map { "\(Int($0.timeIntervalSince1970))" }
            ?? "\(index)"

        return NinebotRideRecord(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            mileage: mileage,
            energy: energy,
            usedElectricity: usedElectricity,
            durationMinutes: durationMinutes,
            speed: speed,
            raw: object
        )
    }

    static func dailyMileageRecords(from travelObject: [String: JSONValue]) -> [NinebotDailyMileageRecord] {
        guard let detail = travelObject["detail"]?.arrayValue else { return [] }
        let month = firstString(["month"], in: travelObject)
        let currentMonth = currentMonthString()
        let currentDay = Calendar.current.component(.day, from: Date())
        let limit = month == currentMonth ? min(detail.count, currentDay) : detail.count

        return detail.prefix(limit).enumerated().compactMap { index, value in
            guard let mileage = value.doubleValue else { return nil }
            let day = index + 1
            return NinebotDailyMileageRecord(
                id: "\(month ?? "month")-\(day)",
                day: day,
                date: date(month: month, day: day),
                mileage: mileage
            )
        }
    }

    static func totalMileage(fromMonthlyTravels travels: [JSONValue]?) -> Double? {
        guard let travels else { return nil }
        var total = 0.0
        var hasMileage = false

        for travel in travels {
            guard let object = travel.objectValue else { continue }
            if let mileage = firstDouble(["total_mileages", "totalMileage", "monthMileage", "mileage"], in: object) {
                total += max(mileage, 0)
                hasMileage = true
                continue
            }

            let dailyTotal = dailyMileageRecords(from: object).reduce(0) { $0 + max($1.mileage, 0) }
            if dailyTotal > 0 {
                total += dailyTotal
                hasMileage = true
            }
        }

        return hasMileage ? total : nil
    }

    static func firstInt(_ keys: [String], in object: [String: JSONValue]) -> Int? {
        for key in keys {
            if let value = object[key]?.intValue {
                return value
            }
        }
        return nil
    }

    static func firstDouble(_ keys: [String], in object: [String: JSONValue]) -> Double? {
        for key in keys {
            if let value = object[key]?.doubleValue {
                return value
            }
        }
        return nil
    }

    static func firstDouble(_ keys: [String], in objects: [[String: JSONValue]]) -> Double? {
        for object in objects {
            if let value = firstDouble(keys, in: object) {
                return value
            }
        }
        return nil
    }

    static func firstString(_ keys: [String], in object: [String: JSONValue]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func firstObject(_ keys: [String], in object: [String: JSONValue]) -> [String: JSONValue]? {
        for key in keys {
            if let value = object[key]?.objectValue {
                return value
            }
        }
        return nil
    }

    static func firstArrayObject(_ keys: [String], in object: [String: JSONValue]) -> [String: JSONValue]? {
        for key in keys {
            guard let array = object[key]?.arrayValue else { continue }
            for value in array {
                if let objectValue = value.objectValue {
                    return objectValue
                }
            }
        }
        return nil
    }

    static func normalizedBatteryVoltage(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value > 1_000 {
            return value / 1_000
        }
        if value > 120 {
            return value / 10
        }
        return value
    }

    static func normalizedBatteryTemperature(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if abs(value) > 120 {
            return value / 10
        }
        return value
    }

    static func firstDate(_ keys: [String], in object: [String: JSONValue]) -> Date? {
        for key in keys {
            if let value = dateValue(object[key]) {
                return value
            }
        }
        return nil
    }

    static func firstDurationMinutes(in object: [String: JSONValue], startedAt: Date?, endedAt: Date?) -> Double? {
        let derived = durationMinutes(startedAt: startedAt, endedAt: endedAt)

        if let minutes = firstDurationValue(["durationMinutes", "duration_min", "durationMin"], in: object) {
            return saneDuration(minutes, fallback: derived)
        }
        if let seconds = firstDurationValue(["duration_seconds", "durationSeconds", "ride_seconds", "riding_seconds"], in: object) {
            return saneDuration(seconds / 60, fallback: derived)
        }
        if let value = firstDurationValue(["duration", "ride_time", "rideTime", "riding_time", "ridingTime", "use_time", "useTime", "cost_time", "costTime"], in: object) {
            return saneDuration(ambiguousDurationMinutes(value, derived: derived), fallback: derived)
        }

        return derived
    }

    static func firstBoolLike(_ keys: [String], in object: [String: JSONValue], trueValue: Int) -> Bool? {
        for key in keys {
            if let value = boolLike(object[key], trueValue: trueValue) {
                return value
            }
        }
        return nil
    }

    static func boolLike(_ value: JSONValue?, trueValue: Int) -> Bool? {
        guard let value else { return nil }
        if let intValue = value.intValue {
            return intValue == trueValue
        }
        return value.boolValue
    }

    static func dateValue(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }

        guard let string = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            return nil
        }

        if let structuredDate = structuredChinaDateValue(string) {
            return structuredDate
        }

        if let number = Double(string) {
            return epochDateValue(number)
        }

        for format in [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ] {
            let formatter = chinaDateFormatter(format: format)
            if let date = formatter.date(from: string) {
                return date
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: string) {
            return date
        }

        return nil
    }

    static func date(month: String?, day: Int) -> Date? {
        guard let month, month.count == 6 else { return nil }
        let yearText = String(month.prefix(4))
        let monthText = String(month.suffix(2))
        guard let year = Int(yearText), let monthNumber = Int(monthText) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chinaTimeZone
        return calendar.date(from: DateComponents(year: year, month: monthNumber, day: day))
    }

    static func currentMonthString() -> String {
        monthString(for: Date())
    }

    static func monthString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = chinaTimeZone
        formatter.dateFormat = "yyyyMM"
        return formatter.string(from: date)
    }

    static func monthStrings(from startDate: Date?, through endDate: Date) -> [String] {
        guard let startDate else {
            return [monthString(for: endDate)]
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chinaTimeZone
        let startComponents = calendar.dateComponents([.year, .month], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month], from: endDate)
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents),
              start <= end else {
            return [monthString(for: endDate)]
        }

        var result: [String] = []
        var cursor = start
        while cursor <= end {
            result.append(monthString(for: cursor))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    static var chinaTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
    }

    static func chinaDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = chinaTimeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    static func structuredChinaDateValue(_ text: String) -> Date? {
        let digitsOnly = text.allSatisfy(\.isNumber)
        guard digitsOnly else { return nil }

        let format: String
        switch text.count {
        case 14:
            format = "yyyyMMddHHmmss"
        case 12:
            format = "yyyyMMddHHmm"
        case 8:
            format = "yyyyMMdd"
        default:
            return nil
        }

        return chinaDateFormatter(format: format).date(from: text)
    }

    static func epochDateValue(_ number: Double) -> Date? {
        if number > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: number / 1000)
        }
        if number > 1_000_000_000 {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }

    static func firstDurationValue(_ keys: [String], in object: [String: JSONValue]) -> Double? {
        for key in keys {
            guard let value = object[key] else { continue }
            if let clockDuration = clockDurationMinutes(value) {
                return clockDuration
            }
            if let numericDuration = value.doubleValue, numericDuration > 0 {
                return numericDuration
            }
        }
        return nil
    }

    static func clockDurationMinutes(_ value: JSONValue) -> Double? {
        guard let string = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              string.contains(":") else {
            return nil
        }

        let parts = string.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }

        if parts.count == 2 {
            return parts[0] + parts[1] / 60
        }
        return parts[0] * 60 + parts[1] + parts[2] / 60
    }

    static func durationMinutes(startedAt: Date?, endedAt: Date?) -> Double? {
        guard let startedAt, let endedAt else { return nil }
        let minutes = endedAt.timeIntervalSince(startedAt) / 60
        guard minutes > 0, minutes <= 48 * 60 else { return nil }
        return minutes
    }

    static func ambiguousDurationMinutes(_ value: Double, derived: Double?) -> Double {
        guard let derived else {
            return value > 300 ? value / 60 : value
        }

        let minuteCandidate = value
        let secondCandidate = value / 60
        return abs(secondCandidate - derived) < abs(minuteCandidate - derived)
            ? secondCandidate
            : minuteCandidate
    }

    static func saneDuration(_ value: Double, fallback: Double?) -> Double? {
        guard value > 0, value <= 48 * 60 else {
            return fallback
        }
        return value
    }
}
