import Foundation
import WidgetKit

struct NinebotWidgetEntry: TimelineEntry {
    var date: Date
    var dashboard: NinebotDashboard
    var errorMessage: String?
    var vehicleImages: [String: Data] = [:]
}

struct NinebotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NinebotWidgetEntry {
        NinebotWidgetEntry(date: Date(), dashboard: .preview, errorMessage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NinebotWidgetEntry) -> Void) {
        let store = NinebotSharedStore()
        let dashboard = store.loadDashboard() ?? .preview
        completion(NinebotWidgetEntry(
            date: Date(),
            dashboard: dashboard,
            errorMessage: store.loadLastError(),
            vehicleImages: cachedVehicleImages(for: dashboard, store: store)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NinebotWidgetEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let refreshMinutes = refreshIntervalMinutes(for: entry.dashboard.primaryVehicle?.state)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())
                ?? Date().addingTimeInterval(TimeInterval(refreshMinutes * 60))
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func refreshIntervalMinutes(for state: NinebotVehicleState?) -> Int {
        guard let state else { return 30 }
        if state.isCharging == true, !state.isFullyCharged { return 3 }
        if state.isLocked == false || state.isPoweredOn == true { return 8 }
        if let battery = state.battery, battery < 20 { return 10 }
        return 20
    }

    private func loadEntry() async -> NinebotWidgetEntry {
        let startedAt = Date()
        let store = NinebotSharedStore()
        let cached = store.loadDashboard()
        let configuration = store.loadConfiguration() ?? NinebotProxyConfiguration(baseURLString: "", bearerToken: "")

        guard configuration.isUsable else {
            store.saveLastWidgetRefreshEvent(NinebotRefreshEvent(
                source: "Widget",
                operation: "刷新小组件",
                startedAt: startedAt,
                endedAt: Date(),
                success: false,
                message: "未配置代理"
            ))
            return NinebotWidgetEntry(
                date: Date(),
                dashboard: cached ?? .empty,
                errorMessage: store.loadLastError(),
                vehicleImages: cached.map { cachedVehicleImages(for: $0, store: store) } ?? [:]
            )
        }

        do {
            let dashboard = try await NinebotProxyClient(configuration: configuration)
                .fetchDashboard(selectedSN: cached?.selectedSN)
            let archivedDashboard = store.saveDashboard(dashboard)
            store.saveLastWidgetRefreshEvent(NinebotRefreshEvent(
                source: "Widget",
                operation: "刷新小组件",
                startedAt: startedAt,
                endedAt: Date(),
                success: true,
                message: archivedDashboard.primaryVehicle?.vehicle.name
            ))
            return NinebotWidgetEntry(
                date: Date(),
                dashboard: archivedDashboard,
                errorMessage: nil,
                vehicleImages: await vehicleImages(for: archivedDashboard, store: store)
            )
        } catch {
            let message = error.localizedDescription
            store.saveLastError(message)
            store.saveLastWidgetRefreshEvent(NinebotRefreshEvent(
                source: "Widget",
                operation: "刷新小组件",
                startedAt: startedAt,
                endedAt: Date(),
                success: false,
                message: message
            ))
            return NinebotWidgetEntry(
                date: Date(),
                dashboard: cached ?? .empty,
                errorMessage: message,
                vehicleImages: cached.map { cachedVehicleImages(for: $0, store: store) } ?? [:]
            )
        }
    }

    private func vehicleImages(for dashboard: NinebotDashboard, store: NinebotSharedStore) async -> [String: Data] {
        var images = cachedVehicleImages(for: dashboard, store: store)

        for snapshot in dashboard.vehicles {
            guard let urlString = snapshot.vehicle.imageURLString,
                  let url = URL(string: urlString) else {
                continue
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      !data.isEmpty,
                      data.count <= 2_500_000 else {
                    continue
                }

                store.saveVehicleImageData(data, sn: snapshot.vehicle.sn)
                images[snapshot.vehicle.sn] = data
            } catch {
                continue
            }
        }

        return images
    }

    private func cachedVehicleImages(for dashboard: NinebotDashboard, store: NinebotSharedStore) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: dashboard.vehicles.compactMap { snapshot in
            guard let data = store.loadVehicleImageData(sn: snapshot.vehicle.sn) else {
                return nil
            }
            return (snapshot.vehicle.sn, data)
        })
    }
}
