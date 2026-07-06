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
            let refreshMinutes = entry.dashboard.primaryVehicle?.state.isCharging == true ? 5 : 15
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())
                ?? Date().addingTimeInterval(TimeInterval(refreshMinutes * 60))
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func loadEntry() async -> NinebotWidgetEntry {
        let store = NinebotSharedStore()
        let cached = store.loadDashboard()

        guard let configuration = store.loadConfiguration(), configuration.isUsable else {
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
            return NinebotWidgetEntry(
                date: Date(),
                dashboard: archivedDashboard,
                errorMessage: nil,
                vehicleImages: await vehicleImages(for: archivedDashboard, store: store)
            )
        } catch {
            let message = error.localizedDescription
            store.saveLastError(message)
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
