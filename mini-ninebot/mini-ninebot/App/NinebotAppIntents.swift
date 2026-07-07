import AppIntents
import Foundation
import WidgetKit

enum NinebotShortcutError: LocalizedError {
    case missingConfiguration
    case missingVehicle

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "请先在 App 的“我的”页面配置数据源并登录"
        case .missingVehicle:
            return "没有找到可操作的车辆，请先打开 App 刷新车况"
        }
    }
}

struct NinebotRefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新九号车况"
    static var description = IntentDescription("刷新已登录九号车辆的电量、续航和状态。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vehicleName = try await NinebotShortcutRunner.refreshDashboard()
        return .result(dialog: "\(vehicleName) 车况已刷新")
    }
}

struct NinebotBatteryStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "查询九号电量"
    static var description = IntentDescription("查询当前选中九号车辆的电量、预估续航和状态。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await NinebotShortcutRunner.batteryStatus()
        return .result(dialog: "\(text)")
    }
}

struct NinebotVehicleLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "查询九号位置"
    static var description = IntentDescription("查询当前选中九号车辆的位置和最后更新时间。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await NinebotShortcutRunner.locationStatus()
        return .result(dialog: "\(text)")
    }
}

struct NinebotRingBellIntent: AppIntent {
    static var title: LocalizedStringResource = "九号寻车铃"
    static var description = IntentDescription("通过九号接口让当前选中的车辆发出寻车提示音。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vehicleName = try await NinebotShortcutRunner.perform(.bell)
        return .result(dialog: "\(vehicleName) 寻车铃已发送")
    }
}

struct NinebotOpenBucketIntent: AppIntent {
    static var title: LocalizedStringResource = "打开九号座桶"
    static var description = IntentDescription("打开当前选中九号车辆的座桶。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vehicleName = try await NinebotShortcutRunner.perform(.openBucket)
        return .result(dialog: "\(vehicleName) 开座桶指令已发送")
    }
}

struct NinebotEngineStartIntent: AppIntent {
    static var title: LocalizedStringResource = "九号上电"
    static var description = IntentDescription("让当前选中的九号车辆进入上电状态。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vehicleName = try await NinebotShortcutRunner.perform(.engineStart)
        return .result(dialog: "\(vehicleName) 上电指令已发送")
    }
}

struct NinebotEngineStopIntent: AppIntent {
    static var title: LocalizedStringResource = "九号熄火"
    static var description = IntentDescription("让当前选中的九号车辆进入熄火状态。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vehicleName = try await NinebotShortcutRunner.perform(.engineStop)
        return .result(dialog: "\(vehicleName) 熄火指令已发送")
    }
}

struct NinebotAppShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .lime

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NinebotRefreshStatusIntent(),
            phrases: [
                "\(.applicationName)刷新车况",
                "用\(.applicationName)刷新车况",
                "在\(.applicationName)刷新车况",
                "让\(.applicationName)刷新车况",
                "\(.applicationName)查看车况",
                "\(.applicationName)查电量",
                "刷新\(.applicationName)车况",
                "查看\(.applicationName)电量",
                "\(.applicationName)刷新九号"
            ],
            shortTitle: "刷新车况",
            systemImageName: "arrow.clockwise"
        )

        AppShortcut(
            intent: NinebotBatteryStatusIntent(),
            phrases: [
                "\(.applicationName)查电量",
                "\(.applicationName)查询电量",
                "用\(.applicationName)查电量",
                "在\(.applicationName)查询电量",
                "\(.applicationName)还有多少电",
                "\(.applicationName)还能骑多远"
            ],
            shortTitle: "查电量",
            systemImageName: "battery.100"
        )

        AppShortcut(
            intent: NinebotVehicleLocationIntent(),
            phrases: [
                "\(.applicationName)查位置",
                "\(.applicationName)查询位置",
                "用\(.applicationName)查位置",
                "在\(.applicationName)查询位置",
                "\(.applicationName)车在哪里",
                "\(.applicationName)九号在哪里"
            ],
            shortTitle: "查位置",
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: NinebotRingBellIntent(),
            phrases: [
                "\(.applicationName)寻车",
                "用\(.applicationName)寻车",
                "在\(.applicationName)寻车",
                "\(.applicationName)响铃",
                "用\(.applicationName)九号寻车铃",
                "让\(.applicationName)响铃"
            ],
            shortTitle: "寻车铃",
            systemImageName: "bell.fill"
        )

        AppShortcut(
            intent: NinebotOpenBucketIntent(),
            phrases: [
                "\(.applicationName)打开座桶",
                "用\(.applicationName)打开座桶",
                "在\(.applicationName)打开座桶",
                "\(.applicationName)开座桶",
                "用\(.applicationName)打开九号座桶",
                "让\(.applicationName)开座桶"
            ],
            shortTitle: "开座桶",
            systemImageName: "shippingbox.fill"
        )

        AppShortcut(
            intent: NinebotEngineStartIntent(),
            phrases: [
                "\(.applicationName)上电",
                "用\(.applicationName)上电",
                "在\(.applicationName)上电",
                "\(.applicationName)开机",
                "用\(.applicationName)九号上电",
                "打开\(.applicationName)电源"
            ],
            shortTitle: "上电",
            systemImageName: "power.circle.fill"
        )

        AppShortcut(
            intent: NinebotEngineStopIntent(),
            phrases: [
                "\(.applicationName)熄火",
                "用\(.applicationName)熄火",
                "在\(.applicationName)熄火",
                "\(.applicationName)关机",
                "用\(.applicationName)九号熄火",
                "关闭\(.applicationName)电源"
            ],
            shortTitle: "熄火",
            systemImageName: "lock.fill"
        )
    }
}

@MainActor
private enum NinebotShortcutRunner {
    static func refreshDashboard() async throws -> String {
        let startedAt = Date()
        let store = NinebotSharedStore()
        do {
            let client = try client(from: store)
            let cached = store.loadDashboard()
            let dashboard = try await client.fetchDashboard(selectedSN: cached?.selectedSN)
            let archivedDashboard = store.saveDashboard(dashboard)
            recordShortcutEvent(store: store, startedAt: startedAt, operation: "刷新车况", success: true, message: archivedDashboard.primaryVehicle?.vehicle.name)
            WidgetCenter.shared.reloadAllTimelines()
            return archivedDashboard.primaryVehicle?.vehicle.name ?? "九号"
        } catch {
            recordShortcutEvent(store: store, startedAt: startedAt, operation: "刷新车况", success: false, message: error.localizedDescription)
            throw error
        }
    }

    static func batteryStatus() async throws -> String {
        let startedAt = Date()
        let store = NinebotSharedStore()
        do {
            let dashboard = try await refreshedDashboardIfPossible(store: store)
            guard let snapshot = dashboard.primaryVehicle else {
                throw NinebotShortcutError.missingVehicle
            }
            let text = "\(snapshot.vehicle.name) 当前电量 \(snapshot.state.batteryText)，预估续航 \(snapshot.state.localEstimatedMileageText)，状态 \(snapshot.state.powerText)。"
            recordShortcutEvent(store: store, startedAt: startedAt, operation: "查询电量", success: true, message: snapshot.vehicle.name)
            WidgetCenter.shared.reloadAllTimelines()
            return text
        } catch {
            recordShortcutEvent(store: store, startedAt: startedAt, operation: "查询电量", success: false, message: error.localizedDescription)
            throw error
        }
    }

    static func locationStatus() async throws -> String {
        let startedAt = Date()
        let store = NinebotSharedStore()
        do {
            let dashboard = try await refreshedDashboardIfPossible(store: store)
            guard let snapshot = dashboard.primaryVehicle else {
                throw NinebotShortcutError.missingVehicle
            }
            let address = store.loadResolvedAddresses()[snapshot.vehicle.sn]?.address
            let locationText: String
            if let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationText = address
            } else if let latitude = snapshot.state.latitude, let longitude = snapshot.state.longitude {
                locationText = "\(String(format: "%.6f", latitude)), \(String(format: "%.6f", longitude))"
            } else {
                locationText = "暂无位置"
            }
            let text = "\(snapshot.vehicle.name) 位置：\(locationText)。更新于 \(shortcutTime(snapshot.state.updatedAt))。"
            recordShortcutEvent(store: store, startedAt: startedAt, operation: "查询位置", success: true, message: snapshot.vehicle.name)
            WidgetCenter.shared.reloadAllTimelines()
            return text
        } catch {
            recordShortcutEvent(store: store, startedAt: startedAt, operation: "查询位置", success: false, message: error.localizedDescription)
            throw error
        }
    }

    static func perform(_ action: NinebotVehicleAction) async throws -> String {
        let startedAt = Date()
        let store = NinebotSharedStore()
        do {
            let client = try client(from: store)
            let dashboard = try await dashboardForOperation(store: store, client: client)
            guard let vehicle = dashboard.primaryVehicle?.vehicle else {
                throw NinebotShortcutError.missingVehicle
            }

            switch action {
            case .bell:
                _ = try await client.ringBell(sn: vehicle.sn)
            case .openBucket:
                _ = try await client.openBucket(sn: vehicle.sn)
            case .engineStart:
                _ = try await client.engineStart(sn: vehicle.sn)
            case .engineStop:
                _ = try await client.engineStop(sn: vehicle.sn)
            }

            let refreshed = try await client.fetchDashboard(selectedSN: vehicle.sn)
            store.saveDashboard(refreshed)
            recordShortcutEvent(store: store, startedAt: startedAt, operation: action.title, success: true, message: vehicle.name)
            WidgetCenter.shared.reloadAllTimelines()
            return vehicle.name
        } catch {
            recordShortcutEvent(store: store, startedAt: startedAt, operation: action.title, success: false, message: error.localizedDescription)
            throw error
        }
    }

    private static func client(from store: NinebotSharedStore) throws -> NinebotProxyClient {
        let configuration = store.loadConfiguration() ?? NinebotProxyConfiguration(baseURLString: "", bearerToken: "")
        guard configuration.isUsable else {
            throw NinebotShortcutError.missingConfiguration
        }
        return NinebotProxyClient(configuration: configuration)
    }

    private static func dashboardForOperation(
        store: NinebotSharedStore,
        client: NinebotProxyClient
    ) async throws -> NinebotDashboard {
        if let cached = store.loadDashboard(), cached.primaryVehicle != nil {
            return cached
        }

        let dashboard = try await client.fetchDashboard(selectedSN: nil)
        let archivedDashboard = store.saveDashboard(dashboard)
        guard archivedDashboard.primaryVehicle != nil else {
            throw NinebotShortcutError.missingVehicle
        }
        return archivedDashboard
    }

    private static func refreshedDashboardIfPossible(store: NinebotSharedStore) async throws -> NinebotDashboard {
        guard let client = try? client(from: store) else {
            if let cached = store.loadDashboard(), cached.primaryVehicle != nil {
                return cached
            }
            throw NinebotShortcutError.missingConfiguration
        }
        let cached = store.loadDashboard()
        let dashboard = try await client.fetchDashboard(selectedSN: cached?.selectedSN)
        return store.saveDashboard(dashboard)
    }

    private static func recordShortcutEvent(
        store: NinebotSharedStore,
        startedAt: Date,
        operation: String,
        success: Bool,
        message: String?
    ) {
        store.saveLastAppRefreshEvent(NinebotRefreshEvent(
            source: "Shortcut",
            operation: operation,
            startedAt: startedAt,
            endedAt: Date(),
            success: success,
            message: message
        ))
    }

    private static func shortcutTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
