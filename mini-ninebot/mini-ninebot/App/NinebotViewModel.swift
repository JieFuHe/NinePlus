import Combine
import CoreLocation
import Foundation
import MapKit
import WidgetKit

enum NinebotInputError: LocalizedError {
    case missingProxy
    case missingAccount
    case missingPassword
    case missingCode

    var errorDescription: String? {
        switch self {
        case .missingProxy:
            return "请先填写代理地址"
        case .missingAccount:
            return "请填写手机号"
        case .missingPassword:
            return "请填写密码"
        case .missingCode:
            return "请填写验证码"
        }
    }
}

enum NinebotVehicleAction: String, CaseIterable, Identifiable {
    case bell
    case openBucket
    case engineStart
    case engineStop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bell: return "寻车铃"
        case .openBucket: return "开座桶"
        case .engineStart: return "上电"
        case .engineStop: return "熄火"
        }
    }

    var resultTitle: String {
        switch self {
        case .bell: return "寻车铃已发送"
        case .openBucket: return "开座桶指令已发送"
        case .engineStart: return "上电指令已发送"
        case .engineStop: return "熄火指令已发送"
        }
    }

    var loadingTitle: String {
        switch self {
        case .bell: return "正在寻车鸣笛"
        case .openBucket: return "正在打开座桶"
        case .engineStart: return "正在开锁"
        case .engineStop: return "正在关锁"
        }
    }

    var subtitle: String {
        switch self {
        case .bell: return "让车辆发出提示音"
        case .openBucket: return "打开座桶"
        case .engineStart: return "车辆进入可骑行状态"
        case .engineStop: return "关闭电源并锁车"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .bell: return "发送寻车铃？"
        case .openBucket: return "打开座桶？"
        case .engineStart: return "车辆上电？"
        case .engineStop: return "车辆熄火？"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .bell:
            return "车辆会发出提示音。"
        case .openBucket:
            return "座桶会被打开，请确认车辆在你身边。"
        case .engineStart:
            return "车辆会进入上电/解锁状态，请确认车辆在你身边。"
        case .engineStop:
            return "车辆会进入熄火/锁车状态，请确认不会影响当前骑行。"
        }
    }

    var systemImage: String {
        switch self {
        case .bell: return "bell.fill"
        case .openBucket: return "shippingbox.fill"
        case .engineStart: return "power.circle.fill"
        case .engineStop: return "lock.fill"
        }
    }

    var isDangerous: Bool {
        switch self {
        case .engineStart, .engineStop, .openBucket:
            return true
        case .bell:
            return false
        }
    }
}

@MainActor
final class NinebotViewModel: ObservableObject {
    @Published var baseURLString = ""
    @Published var bearerToken = ""
    @Published var account = ""
    @Published var password = ""
    @Published var smsCode = ""
    @Published var loginResult: NinebotLoginResult?
    @Published var dashboard: NinebotDashboard
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published private(set) var activeVehicleAction: NinebotVehicleAction?
    @Published private(set) var activeVehicleActionSN: String?
    @Published private(set) var history: [String: [NinebotVehicleHistoryPoint]] = [:]
    @Published private(set) var resolvedAddresses: [String: NinebotResolvedAddress] = [:]
    @Published private(set) var recordedRides: [NinebotRecordedRide] = []

    private let store = NinebotSharedStore()
    private var lastAutomaticRefreshAt: Date?

    init() {
        let configuration = store.loadConfiguration()
        let loginResult = store.loadLoginResult()
        self.baseURLString = configuration?.baseURLString ?? ""
        self.bearerToken = configuration?.bearerToken ?? ""
        self.loginResult = loginResult
        self.account = loginResult?.phone ?? ""
        self.dashboard = store.loadDashboard() ?? .empty
        self.errorMessage = store.loadLastError()
        self.history = Self.historyMap(for: self.dashboard, store: store)
        self.resolvedAddresses = store.loadResolvedAddresses().filter { $0.value.source == Self.addressGeocodingSource }
        self.recordedRides = store.loadRecordedRides()
    }

    var hasConfiguration: Bool {
        currentConfiguration.isUsable
    }

    var hasVehicles: Bool {
        !dashboard.vehicles.isEmpty
    }

    var currentAccountDisplay: String {
        let savedPhone = loginResult?.phone?.trimmed ?? ""
        return savedPhone.isEmpty ? "未绑定账号" : savedPhone
    }

    var hasLoginAccount: Bool {
        !(loginResult?.phone?.trimmed ?? "").isEmpty
    }

    var loginAccountCount: Int {
        hasLoginAccount ? 1 : 0
    }

    var isAddressGeocodingEnabled: Bool {
        true
    }

    func refreshOnLaunchIfPossible() async {
        await refreshResolvedAddressesIfNeeded(for: dashboard)
        await refreshAutomaticallyIfPossible()
    }

    func refreshWhenActiveIfPossible() async {
        await refreshResolvedAddressesIfNeeded(for: dashboard)
        await refreshAutomaticallyIfPossible()
    }

    private func refreshAutomaticallyIfPossible() async {
        guard hasConfiguration else { return }
        guard !isLoading else { return }

        let now = Date()
        if let lastAutomaticRefreshAt, now.timeIntervalSince(lastAutomaticRefreshAt) < 8 {
            return
        }

        lastAutomaticRefreshAt = now
        await refreshDashboard()
    }

    func saveConfiguration() {
        let configuration = currentConfiguration
        guard configuration.isUsable else {
            errorMessage = NinebotInputError.missingProxy.localizedDescription
            return
        }

        store.saveConfiguration(configuration)
        errorMessage = nil
        statusMessage = "代理配置已保存"
    }

    func testConnection() async {
        await runLoadingOperation(message: "正在测试连接") {
            let client = try makeClient()
            try await client.healthCheck()
            self.errorMessage = nil
            self.statusMessage = "代理连接正常"
        }
    }

    func refreshLoginToken() async {
        await runLoadingOperation(message: "正在刷新登录状态") {
            let client = try makeClient()
            try await client.refreshAccessToken()
            self.errorMessage = nil
            self.statusMessage = "登录状态已刷新"
        }
    }

    func refreshDashboard() async {
        await runLoadingOperation(message: "正在刷新车况") {
            let client = try makeClient()
            let dashboard = try await client.fetchDashboard(selectedSN: self.dashboard.selectedSN)
            let archivedDashboard = self.saveDashboard(dashboard)
            await self.refreshResolvedAddressesIfNeeded(for: archivedDashboard)
            self.errorMessage = nil
            self.statusMessage = "已更新 \(Self.timeFormatter.string(from: archivedDashboard.updatedAt))"
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func resolveAddressesNow() async {
        await runLoadingOperation(message: "正在解析车辆位置") {
            try await self.resolveAddresses(for: self.dashboard, force: true)
            self.errorMessage = nil
            self.statusMessage = "车辆位置已解析"
        }
    }

    func loginWithPassword() async {
        await runLoadingOperation(message: "正在密码登录") {
            guard !account.trimmed.isEmpty else { throw NinebotInputError.missingAccount }
            guard !password.isEmpty else { throw NinebotInputError.missingPassword }

            saveConfiguration()
            let client = try makeClient()
            let result = try await client.login(account: account.trimmed, password: password)
            rememberLoginResult(result, fallbackAccount: account.trimmed)
            password = ""

            let dashboard = try await client.fetchDashboard(selectedSN: self.dashboard.selectedSN)
            let archivedDashboard = self.saveDashboard(dashboard)
            await self.refreshResolvedAddressesIfNeeded(for: archivedDashboard)
            self.errorMessage = nil
            self.statusMessage = "登录成功"
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func sendSMSCode() async {
        await runLoadingOperation(message: "正在发送验证码") {
            guard !account.trimmed.isEmpty else { throw NinebotInputError.missingAccount }

            saveConfiguration()
            let client = try makeClient()
            try await client.sendLoginCode(account: account.trimmed)
            self.errorMessage = nil
            self.statusMessage = "验证码已发送"
        }
    }

    func consumeSMSCode() async {
        await runLoadingOperation(message: "正在验证码登录") {
            guard !account.trimmed.isEmpty else { throw NinebotInputError.missingAccount }
            guard !smsCode.trimmed.isEmpty else { throw NinebotInputError.missingCode }

            saveConfiguration()
            let client = try makeClient()
            let result = try await client.consumeLoginCode(account: account.trimmed, code: smsCode.trimmed)
            rememberLoginResult(result, fallbackAccount: account.trimmed)
            smsCode = ""

            let dashboard = try await client.fetchDashboard(selectedSN: self.dashboard.selectedSN)
            let archivedDashboard = self.saveDashboard(dashboard)
            await self.refreshResolvedAddressesIfNeeded(for: archivedDashboard)
            self.errorMessage = nil
            self.statusMessage = "登录成功"
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func selectVehicle(sn: String) {
        dashboard.selectedSN = sn
        saveDashboard(dashboard)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func perform(_ action: NinebotVehicleAction, sn: String) async {
        activeVehicleAction = action
        activeVehicleActionSN = sn
        defer {
            activeVehicleAction = nil
            activeVehicleActionSN = nil
        }

        await runLoadingOperation(message: action.loadingTitle) {
            let client = try makeClient()
            switch action {
            case .bell:
                _ = try await client.ringBell(sn: sn)
            case .openBucket:
                _ = try await client.openBucket(sn: sn)
            case .engineStart:
                _ = try await client.engineStart(sn: sn)
            case .engineStop:
                _ = try await client.engineStop(sn: sn)
            }

            self.statusMessage = action.resultTitle
            self.errorMessage = nil

            let dashboard = try await client.fetchDashboard(selectedSN: sn)
            let archivedDashboard = self.saveDashboard(dashboard)
            await self.refreshResolvedAddressesIfNeeded(for: archivedDashboard)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func history(for sn: String) -> [NinebotVehicleHistoryPoint] {
        history[sn] ?? []
    }

    func recordedRides(for sn: String?) -> [NinebotRecordedRide] {
        recordedRides.filter { ride in
            guard let sn else { return true }
            return ride.vehicleSN == nil || ride.vehicleSN == sn
        }
    }

    func recordedRide(associatedWith rideID: String, vehicleSN: String?) -> NinebotRecordedRide? {
        recordedRides.first { ride in
            ride.associatedRideID == rideID && (vehicleSN == nil || ride.vehicleSN == nil || ride.vehicleSN == vehicleSN)
        }
    }

    func saveRecordedRide(_ ride: NinebotRecordedRide) {
        store.upsertRecordedRide(ride)
        recordedRides = store.loadRecordedRides()
        statusMessage = "骑行记录已保存"
    }

    func deleteRecordedRide(id: String) {
        store.deleteRecordedRide(id: id)
        recordedRides = store.loadRecordedRides()
        statusMessage = "骑行记录已删除"
    }

    func resolvedAddressText(for snapshot: NinebotVehicleSnapshot) -> String? {
        return resolvedAddresses[snapshot.vehicle.sn]?.address
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private var currentConfiguration: NinebotProxyConfiguration {
        NinebotProxyConfiguration(
            baseURLString: baseURLString,
            bearerToken: bearerToken
        )
    }

    private func makeClient() throws -> NinebotProxyClient {
        let configuration = currentConfiguration
        guard configuration.isUsable else {
            throw NinebotInputError.missingProxy
        }
        store.saveConfiguration(configuration)
        return NinebotProxyClient(configuration: configuration)
    }

    @discardableResult
    private func saveDashboard(_ dashboard: NinebotDashboard) -> NinebotDashboard {
        let archivedDashboard = store.saveDashboard(dashboard)
        self.dashboard = archivedDashboard
        history = Self.historyMap(for: archivedDashboard, store: store)
        return archivedDashboard
    }

    private func refreshResolvedAddressesIfNeeded(for dashboard: NinebotDashboard) async {
        try? await resolveAddresses(for: dashboard, force: false)
    }

    private func resolveAddresses(for dashboard: NinebotDashboard, force: Bool) async throws {
        let geocoder = AppleReverseGeocoder()
        var nextAddresses = resolvedAddresses
        var didResolve = false
        var lastError: Error?
        var sawCoordinate = false

        for snapshot in dashboard.vehicles {
            guard let latitude = snapshot.state.latitude,
                  let longitude = snapshot.state.longitude else {
                continue
            }

            sawCoordinate = true
            if !force, let cached = nextAddresses[snapshot.vehicle.sn],
               isFreshAddress(cached, latitude: latitude, longitude: longitude) {
                continue
            }

            do {
                let geocodeCoordinate = NinebotCoordinateTransform.gcj02Coordinate(latitude: latitude, longitude: longitude)
                let address = try await geocoder.reverseGeocode(
                    latitude: geocodeCoordinate.latitude,
                    longitude: geocodeCoordinate.longitude
                )
                nextAddresses[snapshot.vehicle.sn] = NinebotResolvedAddress(
                    sn: snapshot.vehicle.sn,
                    address: address,
                    latitude: latitude,
                    longitude: longitude,
                    updatedAt: Date(),
                    source: Self.addressGeocodingSource
                )
                didResolve = true
            } catch {
                lastError = error
            }
        }

        resolvedAddresses = nextAddresses
        store.saveResolvedAddresses(nextAddresses)

        if force, !didResolve {
            if let lastError {
                throw lastError
            }
            if !sawCoordinate {
                throw AppleGeocodingError.missingCoordinate
            }
        }
    }

    private func isFreshAddress(
        _ address: NinebotResolvedAddress,
        latitude: Double,
        longitude: Double
    ) -> Bool {
        let sameCoordinate = abs(address.latitude - latitude) < 0.00001
            && abs(address.longitude - longitude) < 0.00001
        return sameCoordinate && Date().timeIntervalSince(address.updatedAt) < 15 * 60
    }

    private func rememberLoginResult(_ result: NinebotLoginResult, fallbackAccount: String) {
        var resolvedResult = result
        if resolvedResult.phone?.trimmed.isEmpty != false {
            resolvedResult.phone = fallbackAccount
        }
        loginResult = resolvedResult
        account = resolvedResult.phone ?? fallbackAccount
        store.saveLoginResult(resolvedResult)
    }

    private func runLoadingOperation(message: String, _ operation: () async throws -> Void) async {
        loadingMessage = message
        isLoading = true
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            try await operation()
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            statusMessage = nil
            store.saveLastError(message)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let addressGeocodingSource = "apple-mapkit"

    private static func historyMap(
        for dashboard: NinebotDashboard,
        store: NinebotSharedStore
    ) -> [String: [NinebotVehicleHistoryPoint]] {
        Dictionary(uniqueKeysWithValues: dashboard.vehicles.map { snapshot in
            (snapshot.vehicle.sn, store.loadHistory(sn: snapshot.vehicle.sn))
        })
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum AppleGeocodingError: LocalizedError {
    case invalidResponse
    case missingCoordinate

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Apple 地址解析返回无效"
        case .missingCoordinate:
            return "车辆暂未返回可解析的坐标"
        }
    }
}

private struct AppleReverseGeocoder {
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw AppleGeocodingError.invalidResponse
        }
        request.preferredLocale = Locale(identifier: "zh_CN")

        let mapItems = try await request.mapItems
        let address = Self.addressText(from: mapItems.first)
        guard !address.isEmpty else {
            throw AppleGeocodingError.invalidResponse
        }
        return address
    }

    private static func addressText(from mapItem: MKMapItem?) -> String {
        guard let mapItem else { return "" }
        let candidates = [
            mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true),
            mapItem.address?.fullAddress,
            mapItem.address?.shortAddress,
            mapItem.name
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }
}
