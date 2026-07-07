import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine

struct NinebotDashboardView: View {
    @ObservedObject var model: NinebotViewModel
    var onOpenTrips: () -> Void = {}
    @State private var isShowingVehiclePicker = false
    @State private var scrollOffset: CGFloat = 0
    @State private var pullDistance: CGFloat = 0
    @State private var isShowingPullTimestamp = false
    @State private var pullTimestampDismissID = UUID()
    @State private var didTriggerPullRefresh = false
    @State private var isTrackingPullGesture = false
    @State private var pullGestureStartedAtTop = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                dashboardBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let primary = model.dashboard.primaryVehicle {
                            let activeAction = activeVehicleAction(for: primary.vehicle.sn)

                            VehicleControlHero(
                                snapshot: primary,
                                canSwitchVehicle: model.hasVehicles,
                                resolvedAddress: model.resolvedAddressText(for: primary),
                                showsUpdateTime: !model.isAddressGeocodingEnabled,
                                isLoading: model.isLoading,
                                onRingBell: {
                                    performVehicleAction(.bell, sn: primary.vehicle.sn)
                                }
                            ) {
                                isShowingVehiclePicker = true
                            }
                            VehicleActionPanel(
                                snapshot: primary,
                                isLoading: model.isLoading,
                                activeAction: activeAction
                            ) { action in
                                performVehicleAction(action, sn: primary.vehicle.sn)
                            }
                            .padding(.top, primary.state.isCharging == true && !primary.state.isFullyCharged ? -8 : 0)
                            VehicleLocationRideSummaryPanel(
                                snapshot: primary,
                                resolvedAddress: model.resolvedAddressText(for: primary),
                                isLoading: model.isLoading,
                                onOpenTrips: onOpenTrips,
                                onRingBell: {
                                    performVehicleAction(.bell, sn: primary.vehicle.sn)
                                }
                            )
                                .padding(.horizontal, 16)
                            NavigationLink {
                                NinebotBatteryDetailView(
                                    snapshot: primary,
                                    points: model.history(for: primary.vehicle.sn)
                                )
                            } label: {
                                VehicleHealthPanel(snapshot: primary)
                            }
                            .buttonStyle(.plain)
                                .padding(.horizontal, 16)

                            NavigationLink {
                                NinebotVehicleDetailView(model: model, sn: primary.vehicle.sn)
                            } label: {
                                VehicleBasicsPanel(snapshot: primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        } else {
                            EmptyDashboardView(hasConfiguration: model.hasConfiguration)
                                .padding(.horizontal, 16)
                        }

                        if model.dashboard.vehicles.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("车辆概览")
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                ForEach(model.dashboard.vehicles) { snapshot in
                                    VehicleRow(
                                        snapshot: snapshot,
                                        isSelected: snapshot.vehicle.sn == (model.dashboard.selectedSN ?? model.dashboard.primaryVehicle?.vehicle.sn)
                                    ) {
                                        model.selectVehicle(sn: snapshot.vehicle.sn)
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    scrollOffset = max(0, newValue)
                }
                .simultaneousGesture(pullRefreshGesture)

                if let primary = model.dashboard.primaryVehicle, showsRefreshIndicator {
                    PullRefreshTimestampCircle(
                        snapshot: primary,
                        isLoading: isDashboardRefreshLoading,
                        pullDistance: refreshIndicatorDistance,
                        topInset: proxy.safeAreaInsets.top
                    )
                    .zIndex(9)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if let primary = model.dashboard.primaryVehicle, showsCompactHeader {
                    CompactVehicleHeader(snapshot: primary, topInset: proxy.safeAreaInsets.top)
                        .zIndex(10)
                        .transition(.opacity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.18), value: showsCompactHeader)
        .animation(.easeInOut(duration: 0.18), value: showsRefreshIndicator)
        .onAppear {
            if isDashboardRefreshLoading {
                showPullTimestamp(distance: 84, autoDismiss: false)
            }
        }
        .onChange(of: model.isLoading) { _, isLoading in
            if isDashboardRefreshLoading {
                showPullTimestamp(distance: 84, autoDismiss: false)
            } else if !isLoading {
                schedulePullTimestampDismiss()
            }
        }
        .sheet(isPresented: $isShowingVehiclePicker) {
            VehiclePickerSheet(
                dashboard: model.dashboard,
                fallbackAccount: model.currentAccountDisplay
            ) { sn in
                model.selectVehicle(sn: sn)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var showsCompactHeader: Bool {
        scrollOffset > 24
    }

    private func activeVehicleAction(for sn: String) -> NinebotVehicleAction? {
        guard model.activeVehicleActionSN == sn else { return nil }
        return model.activeVehicleAction
    }

    private func performVehicleAction(_ action: NinebotVehicleAction, sn: String) {
        guard !model.isLoading else { return }
        Task {
            await model.perform(action, sn: sn)
        }
    }

    private var isDashboardRefreshLoading: Bool {
        guard model.isLoading else { return false }
        let message = model.loadingMessage ?? ""
        return message.contains("刷新车况") || message.contains("解析车辆位置")
    }

    private var showsRefreshIndicator: Bool {
        isShowingPullTimestamp || isDashboardRefreshLoading
    }

    private var refreshIndicatorDistance: CGFloat {
        isDashboardRefreshLoading ? max(pullDistance, 84) : pullDistance
    }

    private var dashboardBackground: some View {
        Color.teslaPageBackground
    }

    private var pullRefreshGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                if !isTrackingPullGesture {
                    isTrackingPullGesture = true
                    pullGestureStartedAtTop = scrollOffset <= 1 && value.translation.height > 0
                }

                guard pullGestureStartedAtTop, scrollOffset <= 1, value.translation.height > 0, !model.isLoading else { return }
                let distance = min(value.translation.height, 110)
                pullDistance = distance
                if distance > 16 {
                    showPullTimestamp(distance: distance, autoDismiss: false)
                }
            }
            .onEnded { value in
                defer {
                    isTrackingPullGesture = false
                    pullGestureStartedAtTop = false
                }

                guard pullGestureStartedAtTop, scrollOffset <= 1, value.translation.height > 0 else {
                    schedulePullTimestampDismiss(delay: 200_000_000)
                    return
                }

                if value.translation.height > 86 {
                    triggerPullRefreshIfNeeded()
                } else {
                    schedulePullTimestampDismiss(delay: 220_000_000)
                }
            }
    }

    private func showPullTimestamp(distance: CGFloat, autoDismiss: Bool = true) {
        pullDistance = max(pullDistance, distance)
        isShowingPullTimestamp = true
        if autoDismiss, !model.isLoading {
            schedulePullTimestampDismiss(delay: 1_200_000_000)
        }
    }

    private func triggerPullRefreshIfNeeded() {
        guard !didTriggerPullRefresh, !model.isLoading else { return }
        didTriggerPullRefresh = true
        showPullTimestamp(distance: max(pullDistance, 56), autoDismiss: false)

        Task {
            await model.refreshDashboard()
            didTriggerPullRefresh = false
            schedulePullTimestampDismiss(delay: 450_000_000)
        }
    }

    private func schedulePullTimestampDismiss(delay: UInt64 = 900_000_000) {
        let dismissID = UUID()
        pullTimestampDismissID = dismissID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard pullTimestampDismissID == dismissID, !model.isLoading else { return }
            isShowingPullTimestamp = false
            pullDistance = 0
        }
    }
}

private struct PullRefreshTimestampCircle: View {
    var snapshot: NinebotVehicleSnapshot
    var isLoading: Bool
    var pullDistance: CGFloat
    var topInset: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle()
                        .stroke(Color.teslaHairline, lineWidth: 1)
                }

            VStack(spacing: 2) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.teslaGreen)
                    Text("更新中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                        .lineLimit(1)
                } else {
                    Text("更新")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                        .lineLimit(1)
                    Text(formatTime(snapshot.state.updatedAt))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 62, height: 62)
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .scaleEffect(0.86 + min(1, pullDistance / 84) * 0.14)
        .opacity(min(1, max(0.35, pullDistance / 44)))
        .padding(.top, topInset + 6)
    }
}

private struct NinebotVehicleDetailView: View {
    @ObservedObject var model: NinebotViewModel
    var sn: String
    @State private var copiedMessage: String?

    var body: some View {
        Group {
            if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VehicleHeroCard(snapshot: snapshot)
                        VehicleDetailPanel(
                            snapshot: snapshot,
                            resolvedAddress: resolvedAddress,
                            isLoading: model.isLoading,
                            onRingBell: {
                                Task { await model.perform(.bell, sn: snapshot.vehicle.sn) }
                            }
                        )
                        VehicleChargingAnalysisPanel(
                            snapshot: snapshot,
                            points: model.history(for: snapshot.vehicle.sn)
                        )
                        RawPayloadCopyPanel(snapshot: snapshot, copiedMessage: $copiedMessage)
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("车辆数据已失效")
                        .font(.headline)
                    Text("返回车控页后重新选择车辆")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.teslaPageBackground)
        .navigationTitle("车辆详情")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let copiedMessage {
                Text(copiedMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: copiedMessage)
    }

    private var snapshot: NinebotVehicleSnapshot? {
        model.dashboard.vehicles.first { $0.vehicle.sn == sn } ?? model.dashboard.primaryVehicle
    }

    private var resolvedAddress: String? {
        snapshot.flatMap { model.resolvedAddressText(for: $0) }
    }
}

private struct NinebotBatteryDetailView: View {
    var snapshot: NinebotVehicleSnapshot
    var points: [NinebotVehicleHistoryPoint]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BatteryDetailHeroCard(snapshot: snapshot)
                BatteryDetailMetricsCard(snapshot: snapshot)

                if snapshot.state.isCharging == true || snapshot.state.isFullyCharged {
                    BatteryChargingDetailCard(snapshot: snapshot)
                }

                VehicleChargingAnalysisPanel(snapshot: snapshot, points: points)
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.teslaPageBackground.ignoresSafeArea())
        .navigationTitle("电池")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BatteryDetailHeroCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.state.isFullyCharged ? "已充满" : snapshot.state.chargingStateText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(snapshot.state.isCharging == true || snapshot.state.isFullyCharged ? Color.teslaGreen : Color.teslaSecondaryText)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(snapshot.state.batteryText)
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(batteryTextColor(snapshot.state))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("当前电量")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.teslaSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                BatteryGauge(value: snapshot.state.battery)
                    .frame(width: 72, height: 72)
            }

            BatteryProgressBar(value: snapshot.state.batteryFraction)

            HStack(spacing: 10) {
                BatteryDetailMiniMetric(title: "电压", value: snapshot.state.batteryVoltageText, systemImage: "bolt.batteryblock.fill")
                BatteryDetailMiniMetric(title: "温度", value: snapshot.state.batteryTemperatureText, systemImage: "thermometer.medium")
            }
        }
        .padding(18)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct BatteryDetailMetricsCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            BasicInfoTile(title: "电压", value: snapshot.state.batteryVoltageText, systemImage: "bolt.batteryblock.fill")
            BasicInfoTile(title: "温度", value: snapshot.state.batteryTemperatureText, systemImage: "thermometer.medium")
            BasicInfoTile(title: "循环次数", value: snapshot.state.batteryCycleCountText, systemImage: "arrow.trianglehead.2.clockwise")
            BasicInfoTile(title: "更新时间", value: formatTime(snapshot.state.updatedAt), systemImage: "clock.fill")
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct BatteryChargingDetailCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(snapshot.state.isFullyCharged ? "充电完成" : "正在充电", systemImage: snapshot.state.isFullyCharged ? "checkmark.circle.fill" : "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(Color.teslaGreen)

                Spacer()

                Text(snapshot.state.estimatedFullChargeTimeText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
            }

            DetailSection(title: "充电信息") {
                DetailRow(title: "充电功率", value: snapshot.state.chargingPowerText, systemImage: "bolt.fill")
                DetailRow(title: "充电速度", value: snapshot.state.estimatedChargingSpeedText, systemImage: "bolt.car.fill")
                DetailRow(title: "预计充满", value: snapshot.state.estimatedFullChargeTimeText, systemImage: "timer")
                DetailRow(title: "满电时间", value: snapshot.state.estimatedFullChargeClockText, systemImage: "clock.badge.checkmark.fill")
                DetailRow(title: "充至 80%", value: snapshot.state.estimatedChargeTo80TimeText, systemImage: "battery.75")
                DetailRow(title: "接口剩余", value: snapshot.state.remainingChargeTimeText, systemImage: "clock.badge.questionmark")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct BatteryDetailMiniMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.teslaGreen)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct VehicleChargingAnalysisPanel: View {
    var snapshot: NinebotVehicleSnapshot
    var points: [NinebotVehicleHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("充电分析")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text(snapshot.state.isCharging == true ? "当前正在充电" : "按本地快照统计")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                Text(snapshot.state.chargingStateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.state.isCharging == true ? Color.teslaGreen : Color.teslaSecondaryText)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                BasicInfoTile(title: "功率", value: snapshot.state.chargingPowerText, systemImage: "bolt.fill")
                BasicInfoTile(title: "温度", value: snapshot.state.batteryTemperatureText, systemImage: "thermometer.medium")
                BasicInfoTile(title: "电压", value: snapshot.state.batteryVoltageText, systemImage: "bolt.batteryblock.fill")
                BasicInfoTile(title: "充电速度", value: snapshot.state.estimatedChargingSpeedText, systemImage: "bolt.car.fill")
                BasicInfoTile(title: "充电快照", value: "\(chargingPoints.count) 个", systemImage: "clock.arrow.circlepath")
                BasicInfoTile(title: "电量变化", value: chargingDeltaText, systemImage: "battery.100")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }

    private var chargingPoints: [NinebotVehicleHistoryPoint] {
        points.filter { $0.isCharging == true }.sorted { $0.date < $1.date }
    }

    private var chargingDeltaText: String {
        guard let first = chargingPoints.first?.battery,
              let last = chargingPoints.last?.battery else {
            return "--%"
        }
        let delta = last - first
        return "\(delta >= 0 ? "+" : "")\(delta)%"
    }
}

private struct NinebotVehicleMapView: View {
    var snapshot: NinebotVehicleSnapshot
    var address: String?
    var coordinate: CLLocationCoordinate2D
    var isLoading: Bool
    var onRingBell: () -> Void
    @State private var cameraPosition: MapCameraPosition
    @StateObject private var userLocationProvider = VehicleMapUserLocationProvider()

    init(
        snapshot: NinebotVehicleSnapshot,
        address: String?,
        coordinate: CLLocationCoordinate2D,
        isLoading: Bool,
        onRingBell: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.address = address
        self.coordinate = coordinate
        self.isLoading = isLoading
        self.onRingBell = onRingBell
        _cameraPosition = State(initialValue: .region(Self.region(for: coordinate)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                Marker(snapshot.vehicle.name, coordinate: coordinate)
                    .tint(Color.teslaGreen)

                if let userCoordinate = userLocationProvider.coordinate {
                    Marker("我的位置", systemImage: "location.fill", coordinate: userCoordinate)
                        .tint(.blue)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.vehicle.name)
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(1)

                    Text(locationTitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.teslaSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    ControlMetricPill(title: "纬度", value: formatCoordinate(coordinate.latitude), systemImage: "map")
                    ControlMetricPill(title: "经度", value: formatCoordinate(coordinate.longitude), systemImage: "map.fill")
                }

                if let distanceText = userDistanceText {
                    ControlMetricPill(title: "我的距离", value: distanceText, systemImage: "location.fill")
                }

                HStack(spacing: 10) {
                    Button {
                        onRingBell()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("寻车鸣笛", systemImage: "bell.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)

                    Button {
                        openInAppleMaps()
                    } label: {
                        Label("Apple 地图", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.teslaGreen)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(16)
        }
        .navigationTitle("车辆位置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            userLocationProvider.start()
            fitVisibleRegion()
        }
        .onDisappear {
            userLocationProvider.stop()
        }
        .onChange(of: userLocationProvider.locationVersion) { _, _ in
            fitVisibleRegion()
        }
    }

    private var locationTitle: String {
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else {
            return coordinateText(coordinate.latitude, coordinate.longitude)
        }
        return address
    }

    private func openInAppleMaps() {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = snapshot.vehicle.name
        mapItem.openInMaps()
    }

    private var userDistanceText: String? {
        guard let userCoordinate = userLocationProvider.coordinate else { return nil }
        let vehicleLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let meters = userLocation.distance(from: vehicleLocation)
        if meters >= 1000 {
            return formatNumber(meters / 1000, unit: " km", maximumFractionDigits: 1)
        }
        return formatNumber(meters, unit: " m", maximumFractionDigits: 0)
    }

    private func fitVisibleRegion() {
        guard let userCoordinate = userLocationProvider.coordinate else {
            cameraPosition = .region(Self.region(for: coordinate))
            return
        }

        cameraPosition = .region(Self.region(for: [coordinate, userCoordinate]))
    }

    private static func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        )
    }

    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )
        }

        let minLatitude = coordinates.map(\.latitude).min() ?? coordinates[0].latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? coordinates[0].latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? coordinates[0].longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? coordinates[0].longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.8, 0.006)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.8, 0.006)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

@MainActor
private final class VehicleMapUserLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var locationVersion = 0

    private let manager = CLLocationManager()

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }

        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }

        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if isAuthorized {
                start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last(where: Self.isUsableLocation) else { return }
            coordinate = mapKitCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            locationVersion += 1
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }

    private static func isUsableLocation(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 200
            && (-90...90).contains(location.coordinate.latitude)
            && (-180...180).contains(location.coordinate.longitude)
    }
}

struct NinebotTripsTabView: View {
    @ObservedObject var model: NinebotViewModel

    var body: some View {
        if let snapshot = model.dashboard.primaryVehicle {
            NinebotTripsView(
                model: model,
                snapshot: snapshot,
                recordedRides: model.recordedRides(for: snapshot.vehicle.sn)
            )
        } else {
            EmptyDashboardView(hasConfiguration: model.hasConfiguration)
                .padding(.horizontal, 16)
                .background(Color.teslaPageBackground.ignoresSafeArea())
                .navigationTitle("行程")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct NinebotTripsView: View {
    @ObservedObject var model: NinebotViewModel
    var snapshot: NinebotVehicleSnapshot
    var recordedRides: [NinebotRecordedRide] = []
    @State private var selectedMonth = tripMonthString(for: Date())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TripHeroPanel(snapshot: snapshot)
                NavigationLink {
                    TripTrendView(snapshot: snapshot, recordedRides: recordedRides)
                } label: {
                    TripTrendEntryCard(snapshot: snapshot)
                }
                .buttonStyle(.plain)
                TripMonthFilterPanel(
                    months: monthOptions,
                    selectedMonth: selectedMonth,
                    nextFetchMonth: nextFetchMonth,
                    isSyncing: model.syncingTravelMonth != nil,
                    onSelect: { selectedMonth = $0 },
                    onFetchOlder: {
                        let targetMonth = nextFetchMonth
                        selectedMonth = targetMonth
                        Task {
                            await model.syncTravelMonth(vehicleSN: snapshot.vehicle.sn, month: targetMonth)
                        }
                    }
                )
                RideListSection(
                    model: model,
                    records: filteredRecords,
                    recordedRides: recordedRides,
                    vehicleSN: snapshot.vehicle.sn,
                    selectedMonth: selectedMonth
                )
            }
            .padding(16)
        }
        .background(Color.teslaPageBackground.ignoresSafeArea())
        .navigationTitle("行程")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthOptions: [String] {
        var months = Set(snapshot.state.rides.compactMap(tripMonthString(for:)))
        months.insert(tripMonthString(for: Date()))
        months.insert(selectedMonth)
        return months.sorted(by: >)
    }

    private var filteredRecords: [NinebotRideRecord] {
        snapshot.state.rides.filter { tripMonthString(for: $0) == selectedMonth }
    }

    private var nextFetchMonth: String {
        previousTripMonth(before: monthOptions.min() ?? selectedMonth)
    }
}

private struct TripMonthFilterPanel: View {
    var months: [String]
    var selectedMonth: String
    var nextFetchMonth: String
    var isSyncing: Bool
    var onSelect: (String) -> Void
    var onFetchOlder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("月份筛选")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text("当前 \(tripMonthDisplayName(selectedMonth))")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                Button(action: onFetchOlder) {
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Text("获取 \(tripMonthDisplayName(nextFetchMonth))")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.teslaGreen)
                .disabled(isSyncing)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(months, id: \.self) { month in
                        Button {
                            onSelect(month)
                        } label: {
                            Text(tripMonthDisplayName(month))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(month == selectedMonth ? Color.white : Color.teslaPrimaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(month == selectedMonth ? Color.teslaGreen : Color.teslaCardBackground)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(month == selectedMonth ? Color.clear : Color.teslaHairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private func tripMonthString(for record: NinebotRideRecord) -> String? {
    guard let date = record.startedAt ?? record.endedAt else { return nil }
    return tripMonthString(for: date)
}

private func tripMonthString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    formatter.dateFormat = "yyyyMM"
    return formatter.string(from: date)
}

private func previousTripMonth(before month: String) -> String {
    guard month.count == 6,
          let year = Int(month.prefix(4)),
          let monthValue = Int(month.suffix(2)) else {
        return tripMonthString(for: Date())
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    let date = calendar.date(from: DateComponents(year: year, month: monthValue, day: 1)) ?? Date()
    let previous = calendar.date(byAdding: .month, value: -1, to: date) ?? date
    return tripMonthString(for: previous)
}

private func tripMonthDisplayName(_ month: String) -> String {
    guard month.count == 6 else { return month }
    let year = month.prefix(4)
    let monthValue = month.suffix(2)
    return "\(year).\(monthValue)"
}

private struct VehiclePickerSheet: View {
    var dashboard: NinebotDashboard
    var fallbackAccount: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(accountGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 2)

                            ForEach(group.vehicles) { snapshot in
                                Button {
                                    onSelect(snapshot.vehicle.sn)
                                    dismiss()
                                } label: {
                                    VehiclePickerRow(
                                        snapshot: snapshot,
                                        isSelected: snapshot.vehicle.sn == selectedSN
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.teslaPageBackground)
            .navigationTitle("切换车辆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectedSN: String? {
        dashboard.selectedSN ?? dashboard.primaryVehicle?.vehicle.sn
    }

    private var accountGroups: [VehiclePickerAccountGroup] {
        var groups: [VehiclePickerAccountGroup] = []

        for snapshot in dashboard.vehicles {
            let title = vehicleAccountTitle(for: snapshot, fallback: fallbackAccount)
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].vehicles.append(snapshot)
            } else {
                groups.append(VehiclePickerAccountGroup(title: title, vehicles: [snapshot]))
            }
        }

        return groups
    }
}

private struct VehiclePickerAccountGroup: Identifiable {
    var title: String
    var vehicles: [NinebotVehicleSnapshot]

    var id: String { title }
}

private func vehicleAccountTitle(for snapshot: NinebotVehicleSnapshot, fallback: String) -> String {
    let keys = [
        "account",
        "account_id",
        "accountId",
        "phone",
        "mobile",
        "user_phone",
        "userPhone",
        "owner_phone",
        "ownerPhone",
        "bind_phone",
        "bindPhone",
        "user_id",
        "userId",
        "business_uid",
        "businessUID",
        "uid",
        "uuid"
    ]

    if let raw = snapshot.vehicle.raw {
        for key in keys {
            if let value = raw[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return "\(value) 账号"
            }
        }
    }

    let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fallback.isEmpty, fallback != "未绑定账号" {
        return "\(fallback) 账号"
    }
    return "当前代理账号"
}

private struct VehiclePickerRow: View {
    var snapshot: NinebotVehicleSnapshot
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VehicleImage(urlString: snapshot.vehicle.imageURLString, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.vehicle.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(snapshot.state.batteryText)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(batteryTextColor(snapshot.state))
                }

                Text(snapshot.vehicle.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(snapshot.vehicle.identifierSummaryText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Label(snapshot.state.primaryStatusText, systemImage: statusSystemImage(snapshot.state))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor(snapshot.state))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.teslaGreen : Color(.tertiaryLabel))
                .padding(.top, 2)
        }
        .padding(12)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}

private struct CompactVehicleHeader: View {
    var snapshot: NinebotVehicleSnapshot
    var topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.teslaPageBackground
                .frame(height: topInset)
            Text("\(snapshot.vehicle.name)·\(snapshot.state.batteryText)·\(compactVehicleStatusText(snapshot.state))")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(Color.teslaPageBackground)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

private struct VehicleControlHero: View {
    var snapshot: NinebotVehicleSnapshot
    var canSwitchVehicle: Bool
    var resolvedAddress: String?
    var showsUpdateTime: Bool
    var isLoading: Bool
    var onRingBell: () -> Void
    var onSwitchVehicle: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Button {
                        guard canSwitchVehicle else { return }
                        onSwitchVehicle()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(snapshot.vehicle.name)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Color.teslaPrimaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                if canSwitchVehicle {
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.teslaSecondaryText)
                                }
                            }

                            Text(snapshot.vehicle.model)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.teslaSecondaryText)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(canSwitchVehicle ? "切换车辆" : snapshot.vehicle.name)

                    if let resolvedAddress = normalizedResolvedAddress {
                        if let coordinate = vehicleCoordinate(snapshot.state) {
                            NavigationLink {
                                NinebotVehicleMapView(
                                    snapshot: snapshot,
                                    address: resolvedAddress,
                                    coordinate: coordinate,
                                    isLoading: isLoading,
                                    onRingBell: onRingBell
                                )
                            } label: {
                                Text(resolvedAddress)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.teslaSecondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(resolvedAddress)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.teslaSecondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else if showsUpdateTime {
                        Text("更新 \(formatDate(snapshot.state.updatedAt))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.teslaSecondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                StatusChip(
                    title: compactVehicleStatusText(snapshot.state),
                    systemImage: statusSystemImage(snapshot.state),
                    color: statusColor(snapshot.state)
                )
            }

            VStack(spacing: 6) {
                Text(snapshot.state.localEstimatedMileageText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("预计可行驶")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.035))
                    .frame(height: 24)
                    .blur(radius: 16)
                    .offset(y: 60)

                VehicleImage(urlString: snapshot.vehicle.imageURLString, size: 246, showsBackground: false)
                    .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 196)

            VStack(spacing: 12) {
                BatteryProgressBar(value: snapshot.state.batteryFraction)

                HStack(spacing: 10) {
                    TeslaHeroMetric(title: "电量", value: snapshot.state.batteryText, systemImage: "battery.100")
                    Divider()
                        .frame(height: 34)
                    TeslaHeroMetric(title: "接口续航", value: snapshot.state.enduranceText, systemImage: "road.lanes")
                    Divider()
                        .frame(height: 34)
                    TeslaHeroMetric(title: "均速", value: snapshot.state.averageSpeedText, systemImage: "speedometer")
                }
            }

            if snapshot.state.isCharging == true && !snapshot.state.isFullyCharged {
                ChargingStatusView(state: snapshot.state)
                    .padding(.horizontal, -6)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var normalizedResolvedAddress: String? {
        guard let value = resolvedAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct TeslaHeroMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.teslaSecondaryText)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BatteryProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.teslaControlBackground)

                Capsule()
                    .fill(Color.teslaGreen)
                    .frame(width: max(proxy.size.width * value, 8))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("电量进度 \(Int(value * 100))%")
    }
}

private struct StatusChip: View {
    var title: String
    var systemImage: String
    var color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.teslaCardBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
    }
}

private struct ChargingStatusView: View {
    var state: NinebotVehicleState
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.teslaGreen.opacity(0.16))
                    ZStack {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.teslaGreen)
                            .offset(y: isAnimating ? -1 : 1)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
                    }
                    .frame(width: 22, height: 22)
                    .clipped()
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("正在充电")
                        .font(.subheadline.weight(.semibold))
                    Text("约 \(state.estimatedFullChargeTimeText) 充满")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if !metrics.isEmpty {
                HStack(spacing: 8) {
                    ForEach(metrics) { metric in
                        ChargingMetricChip(metric: metric)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.teslaGreen.opacity(0.9), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.42, height: 2)
                    .offset(x: isAnimating ? proxy.size.width : -proxy.size.width * 0.42)
                    .animation(.linear(duration: 1.35).repeatForever(autoreverses: false), value: isAnimating)
            }
            .frame(height: 2)
        }
        .clipped()
        .onAppear {
            isAnimating = true
        }
    }

    private var metrics: [ChargingMetric] {
        [
            state.chargingPower.map {
                ChargingMetric(title: "功率", value: formatNumber($0, unit: " W", maximumFractionDigits: 0), systemImage: "bolt.fill")
            },
            state.batteryVoltage.map {
                ChargingMetric(title: "电压", value: formatNumber($0, unit: " V", maximumFractionDigits: 1), systemImage: "bolt.batteryblock.fill")
            },
            state.batteryTemperature.map {
                ChargingMetric(title: "温度", value: formatNumber($0, unit: "°C", maximumFractionDigits: 1), systemImage: "thermometer.medium")
            }
        ].compactMap { $0 }
    }
}

private struct ChargingMetric: Identifiable {
    var title: String
    var value: String
    var systemImage: String

    var id: String {
        title
    }
}

private struct ChargingMetricChip: View {
    var metric: ChargingMetric

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: metric.systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.teslaGreen)
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(metric.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.teslaCardBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ControlMetricPill: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct VehicleLocationRideSummaryPanel: View {
    var snapshot: NinebotVehicleSnapshot
    var resolvedAddress: String?
    var isLoading: Bool
    var onOpenTrips: () -> Void
    var onRingBell: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VehicleLocationSummaryCard(
                snapshot: snapshot,
                resolvedAddress: resolvedAddress,
                isLoading: isLoading,
                onRingBell: onRingBell
            )
            .frame(maxWidth: .infinity)

            Button(action: onOpenTrips) {
                VehicleRideSummaryGroupCard(snapshot: snapshot)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 198)
    }
}

private struct VehicleLocationSummaryCard: View {
    var snapshot: NinebotVehicleSnapshot
    var resolvedAddress: String?
    var isLoading: Bool
    var onRingBell: () -> Void

    var body: some View {
        if let coordinate = vehicleCoordinate(snapshot.state) {
            NavigationLink {
                NinebotVehicleMapView(
                    snapshot: snapshot,
                    address: normalizedLocationText,
                    coordinate: coordinate,
                    isLoading: isLoading,
                    onRingBell: onRingBell
                )
            } label: {
                content(coordinate: coordinate)
            }
            .buttonStyle(.plain)
        } else {
            content(coordinate: nil)
        }
    }

    private func content(coordinate: CLLocationCoordinate2D?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("车辆位置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("更新自\(formatTime(snapshot.state.updatedAt))")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ZStack(alignment: .bottomLeading) {
                if let coordinate {
                    VehicleLocationPreviewMap(coordinate: coordinate)
                } else {
                    ZStack {
                        Color.teslaControlBackground
                        Image(systemName: "map")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.teslaSecondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(locationTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.top, 28)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [
                            Color.teslaCardBackground.opacity(0.98),
                            Color.teslaCardBackground.opacity(0.82),
                            Color.teslaCardBackground.opacity(0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 18,
                style: .continuous
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var normalizedLocationText: String? {
        guard let value = resolvedAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var locationTitle: String {
        if let normalizedLocationText {
            return normalizedLocationText
        }
        if let description = snapshot.state.locationDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }
        if let coordinate = vehicleCoordinate(snapshot.state) {
            return coordinateText(coordinate.latitude, coordinate.longitude)
        }
        return "暂无车辆位置"
    }
}

private struct VehicleLocationPreviewMap: View {
    var coordinate: CLLocationCoordinate2D
    @State private var cameraPosition: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _cameraPosition = State(initialValue: .region(Self.region(for: coordinate)))
    }

    var body: some View {
        Map(position: $cameraPosition) {
            Marker("车辆", systemImage: "scooter", coordinate: coordinate)
                .tint(Color.teslaGreen)
        }
        .allowsHitTesting(false)
    }

    private static func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0048, longitudeDelta: 0.0048)
        )
    }
}

private struct VehicleRideSummaryGroupCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("行程", systemImage: "road.lanes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.teslaSecondaryText)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 8) {
                VehicleRideSummaryTile(
                    title: "最近骑行",
                    value: formatDistanceNumber(snapshot.state.lastMileage),
                    unit: "km",
                    systemImage: "arrow.left.arrow.right",
                    isPrimary: true
                )

                VehicleRideSummaryTile(
                    title: "总行程",
                    value: formatDistanceNumber(snapshot.state.totalMileage),
                    unit: "km",
                    systemImage: "calendar",
                    isPrimary: false
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct VehicleRideSummaryTile: View {
    var title: String
    var value: String
    var unit: String
    var systemImage: String
    var isPrimary: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: isPrimary ? 30 : 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: 112, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(isPrimary ? Color.teslaGreen.opacity(0.10) : Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct VehicleRideMetricCard: View {
    var title: String
    var value: String
    var unit: String
    var systemImage: String
    var isProminent: Bool

    var body: some View {
        Group {
            if isProminent {
                prominentContent
            } else {
                compactContent
            }
        }
        .padding(14)
        .frame(height: isProminent ? 110 : 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 4)
    }

    private var prominentContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
            }
        }
    }

    private var compactContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
        }
    }
}

private struct VehicleRangeEstimatePanel: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("预估可行驶")
                        .font(.headline)
                    Text(snapshot.state.localEstimateBasisText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(snapshot.state.localEstimatedMileageText)
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            RangeEstimateBar(batteryFraction: snapshot.state.batteryFraction)

            HStack(spacing: 10) {
                BasicInfoTile(title: "本地模型", value: snapshot.state.localEstimatedMileageText, systemImage: "function")
                BasicInfoTile(title: "行程均速", value: snapshot.state.averageSpeedText, systemImage: "speedometer")
                BasicInfoTile(title: "接口续航", value: snapshot.state.enduranceText, systemImage: "road.lanes")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 4)
    }
}

private struct RangeEstimateBar: View {
    var batteryFraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.teslaControlBackground)

                Capsule()
                    .fill(Color.teslaGreen.opacity(0.9))
                    .frame(width: max(proxy.size.width * batteryFraction, 8))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("剩余电量 \(Int(batteryFraction * 100))%")
    }
}

private struct VehicleHealthPanel: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        let warnings = snapshot.state.warningTexts
        let health = snapshot.state.health

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(healthColor(health.level).opacity(0.14))
                    Image(systemName: snapshot.state.isCharging == true ? "bolt.fill" : "battery.100")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(snapshot.state.isCharging == true ? Color.teslaGreen : batteryTextColor(snapshot.state))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("电池")
                        .font(.headline)
                    Text(snapshot.state.isCharging == true ? snapshot.state.chargeSummaryText : "查看电压、温度和充电信息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(snapshot.state.batteryText)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(batteryTextColor(snapshot.state))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.teslaSecondaryText)
                }
                .frame(alignment: .center)
            }

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct VehicleUsagePanel: View {
    var snapshot: NinebotVehicleSnapshot
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("用车统计")
                        .font(.headline)
                    Text("完整行程和能耗进详情查看")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if showsDisclosure {
                    HStack(spacing: 4) {
                        Text("行程")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                BasicInfoTile(title: "本月日均", value: snapshot.state.dailyAverageMileageText, systemImage: "calendar")
                BasicInfoTile(title: "最近骑行", value: snapshot.state.lastRideSummaryText, systemImage: "clock.arrow.circlepath")
                BasicInfoTile(title: "行程均速", value: snapshot.state.averageSpeedText, systemImage: "speedometer")
                BasicInfoTile(title: "本月能耗", value: snapshot.state.monthEnergyPerKmText, systemImage: "bolt.horizontal.fill")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TripHeroPanel: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("行程概要")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text(snapshot.vehicle.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.state.rangeEstimateAccuracyText)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.teslaGreen)
                    Text("预估准确率")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(snapshot.state.localEstimatedMileageText)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("预计可行驶")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                BasicInfoTile(title: "今日里程", value: snapshot.state.todayMileageText, systemImage: "sun.max.fill")
                BasicInfoTile(title: "平均速度", value: snapshot.state.averageSpeedText, systemImage: "speedometer")
                BasicInfoTile(title: "有效样本", value: "\(snapshot.state.observedRangeSampleCount) 次", systemImage: "scope")
                BasicInfoTile(title: "本月日均", value: snapshot.state.dailyAverageMileageText, systemImage: "calendar")
            }

            Label(snapshot.state.rangeEstimateAccuracyDetailText, systemImage: "target")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TripTrendEntryCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teslaGreen.opacity(0.14))
                Image(systemName: "chart.xyaxis.line")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("查看趋势")
                    .font(.headline)
                    .foregroundStyle(Color.teslaPrimaryText)
                Text("里程、用电、速度和续航估算表现")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(snapshot.state.monthMileageText)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.teslaSecondaryText)
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TripTrendView: View {
    var snapshot: NinebotVehicleSnapshot
    var recordedRides: [NinebotRecordedRide]

    private var analysis: TripTrendAnalysis {
        TripTrendAnalysis(snapshot: snapshot, recordedRides: recordedRides)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TripTrendHeroCard(snapshot: snapshot, analysis: analysis)
                TripTrendRangeModelCard(snapshot: snapshot)
                TripTrendDailyCard(records: analysis.dailyRecords)
                TripTrendRideCard(analysis: analysis)
                TripTrendInsightCard(analysis: analysis)

                if !recordedRides.isEmpty {
                    TripTrendRecordedCard(records: recordedRides)
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.teslaPageBackground.ignoresSafeArea())
        .navigationTitle("趋势分析")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TripTrendRangeModelCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地续航模型")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text(snapshot.state.rangeModelInsightText)
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer(minLength: 8)

                Text(snapshot.state.localEstimatedMileageText)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                BasicInfoTile(title: "准确率", value: snapshot.state.rangeEstimateAccuracyText, systemImage: "target")
                BasicInfoTile(title: "有效样本", value: "\(snapshot.state.observedRangeSampleCount) 次", systemImage: "scope")
                BasicInfoTile(title: "近期效率", value: snapshot.state.rangePerBatteryPercentText, systemImage: "gauge.with.dots.needle.33percent")
                BasicInfoTile(title: "接口续航", value: snapshot.state.enduranceText, systemImage: "road.lanes")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TripTrendHeroCard: View {
    var snapshot: NinebotVehicleSnapshot
    var analysis: TripTrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.vehicle.name)
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(1)
                    Text("趋势分析")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(snapshot.state.rangeEstimateAccuracyText)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.teslaGreen)
                    Text("预估准确率")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDistance(analysis.monthMileage))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("当月行程")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            HStack(spacing: 10) {
                TrendHeroMetric(title: "骑行次数", value: "\(analysis.rideCount)", suffix: "次", systemImage: "list.number")
                TrendHeroMetric(title: "活跃天数", value: "\(analysis.activeDayCount)", suffix: "天", systemImage: "calendar")
                TrendHeroMetric(title: "单公里耗电", value: analysis.energyPerKmShortText, suffix: "Wh/km", systemImage: "bolt.horizontal.fill")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TrendHeroMetric: View {
    var title: String
    var value: String
    var suffix: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.teslaSecondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(suffix)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
            }
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TripTrendDailyCard: View {
    var records: [NinebotDailyMileageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日里程趋势")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text(records.isEmpty ? "等待接口返回本月 detail" : "最近 \(visibleRecords.count) 天")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                Text(formatDistance(records.map(\.mileage).max()))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }

            if records.isEmpty {
                EmptyTrendState(text: "暂无每日里程趋势")
            } else {
                TrendBarChart(values: visibleRecords.map { record in
                    TrendBarValue(
                        id: record.id,
                        label: "\(record.day)",
                        value: record.mileage,
                        tint: Color.teslaGreen
                    )
                })
                .frame(height: 176)

                HStack(spacing: 10) {
                    ControlMetricPill(title: "日均", value: formatDistance(averageMileage), systemImage: "chart.bar.xaxis")
                    ControlMetricPill(title: "最高", value: formatDistance(peakMileage), systemImage: "arrow.up.right")
                    ControlMetricPill(title: "活跃", value: "\(records.count) 天", systemImage: "calendar")
                }
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }

    private var visibleRecords: [NinebotDailyMileageRecord] {
        Array(records.suffix(14))
    }

    private var averageMileage: Double? {
        guard !records.isEmpty else { return nil }
        return records.reduce(0) { $0 + $1.mileage } / Double(records.count)
    }

    private var peakMileage: Double? {
        records.map(\.mileage).max()
    }
}

private struct TripTrendRideCard: View {
    var analysis: TripTrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近骑行表现")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text(analysis.recentRides.isEmpty ? "等待行程列表" : "最近 \(analysis.recentRides.count) 次")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                Text(formatSpeed(analysis.averageSpeed))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }

            if analysis.recentRides.isEmpty {
                EmptyTrendState(text: "暂无最近骑行数据")
            } else {
                TripRecentRideBars(records: analysis.recentRides)
                    .frame(height: 168)

                HStack(spacing: 10) {
                    ControlMetricPill(title: "平均速度", value: formatSpeed(analysis.averageSpeed), systemImage: "speedometer")
                    ControlMetricPill(title: "平均用电", value: formatPercent(analysis.averageUsedElectricity), systemImage: "powerplug.fill")
                    ControlMetricPill(title: "最高里程", value: formatDistance(analysis.peakRideMileage), systemImage: "arrow.up.right")
                }
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TripTrendInsightCard: View {
    var analysis: TripTrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地模型提示")
                .font(.headline)
                .foregroundStyle(Color.teslaPrimaryText)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(analysis.insights, id: \.self) { insight in
                    Label(insight, systemImage: "sparkle.magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TripTrendRecordedCard: View {
    var records: [NinebotRecordedRide]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地记录")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text("记录页生成的轨迹统计")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                Text("\(records.count) 次")
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                BasicInfoTile(title: "本地总里程", value: formatDistance(records.reduce(0) { $0 + $1.distanceKilometers }), systemImage: "point.3.connected.trianglepath.dotted")
                BasicInfoTile(title: "本地极速", value: formatSpeed(records.map(\.maxSpeedKmh).max()), systemImage: "gauge.with.dots.needle.67percent")
                BasicInfoTile(title: "最大 G", value: formatAccelerationG(records.map(\.maxAccelerationG).max()), systemImage: "bolt.circle.fill")
                BasicInfoTile(title: "已关联", value: "\(records.filter { $0.associatedRideID != nil }.count) 次", systemImage: "link")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct TrendBarValue: Identifiable {
    var id: String
    var label: String
    var value: Double
    var tint: Color
}

private struct TrendBarChart: View {
    var values: [TrendBarValue]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.map(\.value).max() ?? 0, 1)
            let chartHeight = max(proxy.size.height - 42, 1)
            let barWidth = min(max(proxy.size.width / CGFloat(max(values.count, 1)) * 0.24, 4), 11)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider()
                            .opacity(0.55)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 20)

                HStack(alignment: .bottom, spacing: values.count > 10 ? 7 : 10) {
                    ForEach(values) { item in
                        VStack(spacing: 6) {
                            Text(shortTrendValue(item.value))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.teslaSecondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)

                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(Color.teslaSecondaryText.opacity(0.10))
                                    .frame(width: barWidth, height: chartHeight)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [item.tint.opacity(0.72), item.tint],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: barWidth, height: max(6, chartHeight * CGFloat(item.value / maxValue)))
                            }

                            Text(item.label)
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(Color.teslaSecondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TripRecentRideBars: View {
    var records: [NinebotRideRecord]

    var body: some View {
        TrendBarChart(values: Array(records.enumerated()).map { index, ride in
            TrendBarValue(
                id: ride.id,
                label: "\(index + 1)",
                value: ride.mileage ?? 0,
                tint: ride.usedElectricity.map { $0 > 15 ? Color.orange : Color.teslaGreen } ?? Color.teslaGreen
            )
        })
    }
}

private struct EmptyTrendState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.teslaSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.teslaControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TripTrendAnalysis {
    var snapshot: NinebotVehicleSnapshot
    var recordedRides: [NinebotRecordedRide]

    var dailyRecords: [NinebotDailyMileageRecord] {
        snapshot.state.dailyMileages.sorted {
            if let left = $0.date, let right = $1.date {
                return left < right
            }
            return $0.day < $1.day
        }
    }

    var rides: [NinebotRideRecord] {
        snapshot.state.rides
    }

    var recentRides: [NinebotRideRecord] {
        Array(rides.prefix(8))
    }

    var rideCount: Int {
        rides.count
    }

    var activeDayCount: Int {
        dailyRecords.count
    }

    var monthMileage: Double? {
        if let monthMileage = snapshot.state.monthMileage {
            return monthMileage
        }
        guard !dailyRecords.isEmpty else { return nil }
        return dailyRecords.reduce(0) { $0 + $1.mileage }
    }

    var averageDailyMileage: Double? {
        guard let monthMileage, !dailyRecords.isEmpty else { return nil }
        return monthMileage / Double(dailyRecords.count)
    }

    var averageSpeed: Double? {
        let samples = rides.compactMap(\.speed).filter { $0 > 0 }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var averageUsedElectricity: Double? {
        let samples = rides.compactMap(\.usedElectricity).filter { $0 > 0 }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var peakRideMileage: Double? {
        rides.compactMap(\.mileage).max()
    }

    var energyPerKm: Double? {
        if let monthMileage, monthMileage > 0,
           let energy = snapshot.state.monthUsedElectricity ?? snapshot.state.monthEnergy {
            return energy / monthMileage
        }

        let samples = rides.compactMap { ride -> Double? in
            guard let mileage = ride.mileage, mileage > 0,
                  let energy = ride.energy, energy > 0 else { return nil }
            return energy / mileage
        }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var energyPerKmText: String {
        guard let energyPerKm else { return "-- Wh/km" }
        return "\(formatNumber(energyPerKm, unit: " Wh/km", maximumFractionDigits: 1))"
    }

    var energyPerKmShortText: String {
        guard let energyPerKm else { return "--" }
        return formatNumber(energyPerKm, unit: "", maximumFractionDigits: 1)
    }

    var insights: [String] {
        var result: [String] = []

        if let peak = peakRideMileage, let averageDailyMileage, peak > averageDailyMileage * 1.8 {
            result.append("有长距离单次骑行，续航预估会更依赖最近行程样本。")
        }

        if let averageUsedElectricity, averageUsedElectricity > 12 {
            result.append("最近单次平均用电偏高，可以关注胎压、载重和急加速。")
        }

        if let energyPerKm, energyPerKm > 35 {
            result.append("单公里耗电偏高，后续可以结合温度和速度继续校准。")
        }

        if snapshot.state.observedRangeSampleCount < 5 {
            result.append("有效续航样本还不多，多记录几次后准确率会更稳定。")
        }

        if recordedRides.contains(where: { $0.associatedRideID == nil }) {
            result.append("有本地记录尚未关联接口行程，关联后趋势会更完整。")
        }

        if result.isEmpty {
            result.append("当前趋势正常，继续积累行程后可以看到更稳定的变化。")
        }

        return result
    }
}

private struct DailyMileagePanel: View {
    var records: [NinebotDailyMileageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日里程")
                        .font(.headline)
                    Text(records.isEmpty ? "等待行程接口返回 detail" : "按每日总里程生成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatDistance(totalMileage))
                    .font(.headline.monospacedDigit().weight(.semibold))
            }

            if records.isEmpty {
                Text("暂无每日里程数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                DailyMileageLineChart(records: records)
                    .frame(height: 128)

                HStack(spacing: 10) {
                    ControlMetricPill(title: "最高", value: formatDistance(peakMileage), systemImage: "arrow.up.right")
                    ControlMetricPill(title: "平均", value: formatDistance(averageMileage), systemImage: "chart.bar.xaxis")
                    ControlMetricPill(title: "天数", value: "\(records.count) 天", systemImage: "calendar")
                }
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    private var totalMileage: Double? {
        guard !records.isEmpty else { return nil }
        return records.reduce(0) { $0 + $1.mileage }
    }

    private var averageMileage: Double? {
        guard let totalMileage, !records.isEmpty else { return nil }
        return totalMileage / Double(records.count)
    }

    private var peakMileage: Double? {
        records.map(\.mileage).max()
    }
}

private struct DailyMileageLineChart: View {
    var records: [NinebotDailyMileageRecord]

    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(in: proxy.size)

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider()
                        Spacer(minLength: 0)
                    }
                    Divider()
                }
                .opacity(0.45)

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.teslaGreen.opacity(0.65), Color.teslaGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay {
                            Circle()
                                .stroke(Color.teslaGreen, lineWidth: 2)
                        }
                        .frame(width: index == points.count - 1 ? 8 : 6, height: index == points.count - 1 ? 8 : 6)
                        .position(point)
                }
            }
        }
        .padding(12)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("每日里程折线图")
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !records.isEmpty else { return [] }
        let maxMileage = max(records.map(\.mileage).max() ?? 0, 1)
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let count = records.count

        return records.enumerated().map { index, record in
            let x = count == 1 ? width / 2 : width * CGFloat(index) / CGFloat(count - 1)
            let y = height - height * CGFloat(record.mileage / maxMileage)
            return CGPoint(x: x, y: min(max(y, 0), height))
        }
    }
}

private struct VehicleHistoryPanel: View {
    var points: [NinebotVehicleHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("历史记录")
                        .font(.headline)
                    Text("每次刷新后自动记录本地快照")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let summary = NinebotVehicleHistorySummary(points: points) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    BasicInfoTile(title: "记录周期", value: summary.periodText, systemImage: "clock")
                    BasicInfoTile(title: "样本数", value: "\(summary.sampleCount)", systemImage: "list.bullet.rectangle")
                    BasicInfoTile(title: "电量变化", value: summary.batteryDeltaText, systemImage: "battery.100")
                    BasicInfoTile(title: "里程变化", value: summary.mileageDeltaText, systemImage: "road.lanes")
                }
            } else {
                Text("刷新一次车况后开始记录趋势")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}

private struct VehicleHeroCard: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VehicleImage(urlString: snapshot.vehicle.imageURLString, size: 78)

                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.vehicle.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text(snapshot.vehicle.model)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(snapshot.vehicle.sn)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                BatteryGauge(value: snapshot.state.battery)
                    .frame(width: 62, height: 62)
            }

            HStack(spacing: 22) {
                MetricView(title: "续航", value: snapshot.state.enduranceText, systemImage: "road.lanes")
                MetricView(title: "锁车", value: snapshot.state.lockText, systemImage: snapshot.state.isLocked == true ? "lock.fill" : "lock.open.fill")
                MetricView(title: "电源", value: snapshot.state.powerText, systemImage: "power")
            }

            Divider()

            Label("更新 \(formatDate(snapshot.state.updatedAt))", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}

private struct VehicleActionPanel: View {
    var snapshot: NinebotVehicleSnapshot
    var isLoading: Bool
    var activeAction: NinebotVehicleAction?
    var onAction: (NinebotVehicleAction) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let activeAction {
                VehicleControlLoadingStrip(action: activeAction)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 12) {
                CommandPadButton(
                    title: "寻车",
                    systemImage: "bell.fill",
                    tint: Color.teslaPrimaryText,
                    isLoading: activeAction == .bell,
                    isDisabled: isLoading
                ) {
                    onAction(.bell)
                }

                SlideActionControl(
                    title: isLocked ? "滑动开锁" : "滑动关锁",
                    completedTitle: isLocked ? "正在开锁" : "正在关锁",
                    systemImage: isLocked ? "lock.fill" : "lock.open.fill",
                    color: Color.teslaGreen,
                    isLoading: activeAction == slideAction,
                    isDisabled: isLoading
                ) {
                    onAction(slideAction)
                }
                .id(isLocked ? "unlock" : "lock")

                CommandPadButton(
                    title: "座桶",
                    systemImage: "shippingbox.fill",
                    tint: Color.teslaPrimaryText,
                    isLoading: activeAction == .openBucket,
                    isDisabled: isLoading
                ) {
                    onAction(.openBucket)
                }
            }
        }
        .padding(12)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    private var isLocked: Bool {
        snapshot.state.isLocked != false
    }

    private var slideAction: NinebotVehicleAction {
        isLocked ? .engineStart : .engineStop
    }
}

private struct VehicleControlLoadingStrip: View {
    var action: NinebotVehicleAction

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.teslaGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.loadingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                Text("发送完成后自动刷新车况")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.teslaGreen.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct CommandPadButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var isLoading: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.teslaControlBackground)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        }
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.teslaGreen)
                    } else {
                        Image(systemName: systemImage)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 44, height: 44)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
            }
            .frame(width: 70, height: 64)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isLoading ? 0.45 : 1)
    }
}

private struct SlideActionControl: View {
    var title: String
    var completedTitle: String
    var systemImage: String
    var color: Color
    var isLoading: Bool
    var isDisabled: Bool
    var onCommit: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isCommitted = false
    @State private var isDragging = false

    private let height: CGFloat = 64
    private let thumbSize: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            let maxOffset = max(proxy.size.width - thumbSize - 10, 0)
            let isBusy = isLoading || isCommitted

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.teslaControlBackground)
                    .overlay {
                        Capsule()
                            .stroke(Color.teslaHairline, lineWidth: 1)
                    }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.42), color.opacity(0.16)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumbSize + dragOffset, thumbSize))
                    .opacity(isDragging || isCommitted ? 1 : 0)

                HStack(spacing: 8) {
                    Spacer(minLength: thumbSize + 8)

                    HStack(spacing: 8) {
                        Text(isBusy ? completedTitle : title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(color)
                        } else if !isCommitted {
                            HStack(spacing: -2) {
                                Image(systemName: "chevron.right")
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                        }
                    }
                    .offset(x: 10)

                    Spacer(minLength: 12)
                }
                .foregroundStyle(isDisabled && !isLoading ? Color.teslaSecondaryText : Color.teslaPrimaryText)
                .padding(.horizontal, 12)

                ZStack {
                    Circle()
                        .fill(Color.teslaActionThumb)
                        .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: thumbSize, height: thumbSize)
                .padding(5)
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isDisabled, !isCommitted else { return }
                            isDragging = true
                            dragOffset = min(max(value.translation.width, 0), maxOffset)
                        }
                        .onEnded { _ in
                            guard !isDisabled, !isCommitted else { return }
                            if dragOffset >= maxOffset * 0.72 {
                                isCommitted = true
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    dragOffset = maxOffset
                                }
                                onCommit()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        dragOffset = 0
                                        isCommitted = false
                                        isDragging = false
                                    }
                                }
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    dragOffset = 0
                                    isDragging = false
                                }
                            }
                        }
                )
            }
        }
        .frame(height: height)
        .opacity(isDisabled && !isLoading ? 0.55 : 1)
        .accessibilityLabel(title)
    }
}

private struct VehicleBasicsPanel: View {
    var snapshot: NinebotVehicleSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teslaControlBackground)
                Image(systemName: "info.circle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("查看信息")
                    .font(.headline)
                    .foregroundStyle(Color.teslaPrimaryText)
                Text("\(snapshot.vehicle.model) · 更新 \(formatTime(snapshot.state.updatedAt))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.teslaSecondaryText)
        }
        .padding(18)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

private struct BasicInfoTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .frame(width: 22, height: 22, alignment: .leading)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct VehicleDetailPanel: View {
    var snapshot: NinebotVehicleSnapshot
    var resolvedAddress: String?
    var isLoading: Bool
    var onRingBell: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("详细信息")
                .font(.headline)

            DetailSection(title: "车况") {
                DetailRow(title: "健康状态", value: snapshot.state.health.title, systemImage: snapshot.state.health.systemImage)
                DetailRow(title: "状态说明", value: snapshot.state.health.message, systemImage: "text.bubble.fill")
                DetailRow(title: "电量", value: snapshot.state.batteryText, systemImage: "battery.100")
                DetailRow(title: "电池电压", value: snapshot.state.batteryVoltageText, systemImage: "bolt.batteryblock.fill")
                DetailRow(title: "电池温度", value: snapshot.state.batteryTemperatureText, systemImage: "thermometer.medium")
                DetailRow(title: "循环次数", value: snapshot.state.batteryCycleCountText, systemImage: "arrow.trianglehead.2.clockwise")
                DetailRow(title: "充电功率", value: snapshot.state.chargingPowerText, systemImage: "bolt.fill")
                DetailRow(title: "预估续航", value: snapshot.state.enduranceText, systemImage: "road.lanes")
                DetailRow(title: "AI 预估", value: snapshot.state.aiEstimatedMileageText, systemImage: "sparkles")
                DetailRow(title: "本地预估", value: snapshot.state.localEstimatedMileageText, systemImage: "function")
                DetailRow(title: "本地模型", value: snapshot.state.rangeModelSummaryText, systemImage: "target")
                DetailRow(title: "续航可信", value: snapshot.state.rangePerBatteryPercentText, systemImage: "speedometer")
                DetailRow(title: "充电状态", value: snapshot.state.chargingStateText, systemImage: "bolt.fill")
                DetailRow(title: "充电速度", value: snapshot.state.estimatedChargingSpeedText, systemImage: "bolt.car.fill")
                DetailRow(title: "充至 80%", value: snapshot.state.estimatedChargeTo80TimeText, systemImage: "battery.75")
                DetailRow(title: "80% 时间", value: snapshot.state.estimatedChargeTo80ClockText, systemImage: "clock.badge.checkmark")
                DetailRow(title: "预计充满", value: snapshot.state.estimatedFullChargeTimeText, systemImage: "timer")
                DetailRow(title: "满电时间", value: snapshot.state.estimatedFullChargeClockText, systemImage: "clock.badge.checkmark.fill")
                DetailRow(title: "接口剩余", value: snapshot.state.remainingChargeTimeText, systemImage: "clock.badge.questionmark")
                DetailRow(title: "电源状态", value: snapshot.state.powerText, systemImage: "power")
                DetailRow(title: "锁车状态", value: snapshot.state.lockText, systemImage: snapshot.state.isLocked == true ? "lock.fill" : "lock.open.fill")
                DetailRow(title: "更新时间", value: formatDate(snapshot.state.updatedAt), systemImage: "clock")
            }

            DetailSection(title: "定位") {
                if let coordinate = vehicleCoordinate(snapshot.state) {
                    NavigationLink {
                        NinebotVehicleMapView(
                            snapshot: snapshot,
                            address: locationText,
                            coordinate: coordinate,
                            isLoading: isLoading,
                            onRingBell: onRingBell
                        )
                    } label: {
                        DetailRow(title: "位置", value: locationText, systemImage: "map")
                    }
                    .buttonStyle(.plain)
                } else {
                    DetailRow(title: "位置", value: locationText, systemImage: "map")
                }
                if hasResolvedAddress {
                    DetailRow(title: "地址来源", value: "Apple 地图解析", systemImage: "map.fill")
                }
                DetailRow(title: "纬度", value: formatCoordinate(snapshot.state.latitude), systemImage: "map")
                DetailRow(title: "经度", value: formatCoordinate(snapshot.state.longitude), systemImage: "map.fill")
                DetailRow(title: "坐标", value: coordinateText(snapshot.state.latitude, snapshot.state.longitude), systemImage: "location.fill")
            }

            DetailSection(title: "车辆资料") {
                DetailRow(title: "名称", value: snapshot.vehicle.name, systemImage: "tag.fill")
                DetailRow(title: "车型", value: snapshot.vehicle.model, systemImage: "bolt.car.fill")
                DetailRow(title: "SN", value: snapshot.vehicle.sn, systemImage: "number")
                DetailRow(title: "VIN", value: snapshot.vehicle.vin ?? "--", systemImage: "barcode.viewfinder")
                DetailRow(title: "图片", value: snapshot.vehicle.imageURLString ?? "--", systemImage: "photo")
            }

            RawFieldSection(title: "车辆原始字段", fields: snapshot.vehicle.raw)
            RawFieldSection(title: "状态原始字段", fields: snapshot.state.rawStatus)
            RawFieldSection(title: "电池原始字段", fields: snapshot.state.rawBattery)
            RawFieldSection(title: "行程原始字段", fields: snapshot.state.rawTravel)
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var locationText: String {
        guard let resolvedAddress = normalizedResolvedAddress else {
            return snapshot.state.locationText
        }
        return resolvedAddress
    }

    private var hasResolvedAddress: Bool {
        normalizedResolvedAddress != nil
    }

    private var normalizedResolvedAddress: String? {
        guard let value = resolvedAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct DetailSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct DetailRow: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            Text(value.isEmpty ? "--" : value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct RideListSection: View {
    @ObservedObject var model: NinebotViewModel
    var records: [NinebotRideRecord]
    var recordedRides: [NinebotRecordedRide] = []
    var vehicleSN: String?
    var selectedMonth: String
    @State private var visibleLimit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("行程列表")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text("点击行程查看详情和本地轨迹")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }

                Spacer()

                Text("\(records.count)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            if records.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(tripMonthDisplayName(selectedMonth)) 暂无行程")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text("可以切换已有月份，或继续向前获取服务器归档。")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.teslaCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.teslaHairline, lineWidth: 1)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(records.prefix(visibleLimit).enumerated()), id: \.element.id) { index, record in
                        NavigationLink {
                            NinebotRideDetailView(
                                model: model,
                                vehicleSN: vehicleSN,
                                record: record,
                                localRecord: associatedRecord(for: record)
                            )
                        } label: {
                            RideRecordRow(
                                record: record,
                                index: index
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if records.count > visibleLimit {
                        Button {
                            visibleLimit += 30
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.down.circle.fill")
                                Text("显示更多")
                                Text("\(records.count - visibleLimit)")
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.teslaGreen)
                        .background(Color.teslaCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.teslaHairline, lineWidth: 1)
                        }
                    }
                }
            }
        }
        .onChange(of: selectedMonth) { _ in
            visibleLimit = 30
        }
    }

    private func associatedRecord(for record: NinebotRideRecord) -> NinebotRecordedRide? {
        recordedRides.first { ride in
            ride.associatedRideID == record.id && (vehicleSN == nil || ride.vehicleSN == nil || ride.vehicleSN == vehicleSN)
        }
    }
}

private struct RideRecordRow: View {
    var record: NinebotRideRecord
    var index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.teslaGreen.opacity(0.14))
                    Image(systemName: "road.lanes")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.teslaGreen)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.startedAt.map(formatRideDate) ?? "行程 \(index + 1)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(record.endedAt.map { "结束 \($0.formatted(.dateTime.hour().minute()))" } ?? "结束时间未知")
                        Text("·")
                        Text(formatDuration(record.durationMinutes))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatDistance(record.mileage))
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(1)
                }
            }

            if !metrics.isEmpty {
                HStack(spacing: 10) {
                    ForEach(metrics) { metric in
                        RideMetric(title: metric.title, value: metric.value, systemImage: metric.systemImage)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.teslaCardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    private var metrics: [RideDisplayMetric] {
        [
            record.energy.map { RideDisplayMetric(title: "能耗", value: formatEnergyWh($0), systemImage: "bolt.horizontal.fill") },
            record.usedElectricity.map { RideDisplayMetric(title: "用电", value: formatPercent($0), systemImage: "powerplug.fill") },
            record.speed.map { RideDisplayMetric(title: "速度", value: formatSpeed($0), systemImage: "speedometer") }
        ].compactMap { $0 }
    }
}

private struct RideDisplayMetric: Identifiable {
    var title: String
    var value: String
    var systemImage: String

    var id: String {
        "\(title)-\(value)-\(systemImage)"
    }
}

private struct NinebotRideDetailView: View {
    @ObservedObject var model: NinebotViewModel
    var vehicleSN: String?
    var record: NinebotRideRecord
    var localRecord: NinebotRecordedRide?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RideDetailHero(record: effectiveRecord, localRecord: localRecord)

                if let localRecord {
                    RideTrackMapPanel(record: localRecord)
                } else if !interfaceTrackPoints.isEmpty {
                    InterfaceRideTrackMapPanel(points: interfaceTrackPoints)
                }

                DetailSection(title: "接口行程") {
                    DetailRow(title: "开始时间", value: effectiveRecord.startedAt.map(formatDate) ?? "--", systemImage: "play.fill")
                    DetailRow(title: "结束时间", value: effectiveRecord.endedAt.map(formatDate) ?? "--", systemImage: "stop.fill")
                    DetailRow(title: "里程", value: formatDistance(effectiveRecord.mileage), systemImage: "road.lanes")
                    DetailRow(title: "时长", value: formatDuration(effectiveRecord.durationMinutes), systemImage: "timer")
                    DetailRow(title: "速度", value: formatSpeed(effectiveRecord.speed), systemImage: "speedometer")
                    DetailRow(title: "能耗", value: formatEnergyWh(effectiveRecord.energy), systemImage: "bolt.horizontal.fill")
                    DetailRow(title: "用电", value: formatPercent(effectiveRecord.usedElectricity), systemImage: "powerplug.fill")
                    DetailRow(title: "行程 ID", value: record.id, systemImage: "number")
                }

                RawJSONSection(title: "行程详情完整返回值", value: remoteDetail?.raw)
                RawFieldSection(title: "列表原始字段", fields: record.raw)
            }
            .padding(16)
        }
        .background(Color.teslaPageBackground.ignoresSafeArea())
        .navigationTitle("行程详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(vehicleSN ?? "")|\(record.id)") {
            await loadRemoteDetailIfNeeded()
        }
    }

    private var canLoadRemoteDetail: Bool {
        vehicleSN?.isEmpty == false && !record.id.isEmpty
    }

    private var remoteDetail: NinebotRideDetail? {
        guard let vehicleSN else { return nil }
        return model.rideDetail(vehicleSN: vehicleSN, rideID: record.id)
    }

    private var effectiveRecord: NinebotRideRecord {
        remoteDetail?.parsedRecord ?? record
    }

    private var interfaceTrackPoints: [NinebotInterfaceTrackPoint] {
        guard localRecord == nil else { return [] }
        return remoteDetail?.interfaceTrackPoints ?? []
    }

    private func loadRemoteDetailIfNeeded() async {
        guard let vehicleSN, canLoadRemoteDetail else { return }
        await model.refreshRideDetail(vehicleSN: vehicleSN, rideID: record.id)
    }
}

private struct RideDetailHero: View {
    var record: NinebotRideRecord
    var localRecord: NinebotRecordedRide?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.startedAt.map(formatRideDate) ?? "行程详情")
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    if localRecord != nil {
                        Text("已关联本地轨迹")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.teslaGreen)
                    }
                }

                Spacer()

                if localRecord != nil {
                    Image(systemName: "map.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.teslaGreen)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(formatDistance(record.mileage))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("里程")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            if !metrics.isEmpty {
                LazyVGrid(
                    columns: gridColumns,
                    spacing: 10
                ) {
                    ForEach(metrics) { metric in
                        BasicInfoTile(title: metric.title, value: metric.value, systemImage: metric.systemImage)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    private var gridColumns: [GridItem] {
        if metrics.count <= 1 {
            return [GridItem(.flexible(), spacing: 10)]
        }
        return [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var metrics: [RideDisplayMetric] {
        var result: [RideDisplayMetric] = [
            record.speed.map { RideDisplayMetric(title: "接口速度", value: formatSpeed($0), systemImage: "speedometer") },
            record.energy.map { RideDisplayMetric(title: "能耗", value: formatEnergyWh($0), systemImage: "bolt.horizontal.fill") },
            record.usedElectricity.map { RideDisplayMetric(title: "用电", value: formatPercent($0), systemImage: "powerplug.fill") },
            record.durationMinutes.map { RideDisplayMetric(title: "时长", value: formatDuration($0), systemImage: "timer") }
        ].compactMap { $0 }

        if let localRecord {
            result.append(contentsOf: [
                RideDisplayMetric(title: "本地极速", value: formatSpeed(localRecord.maxSpeedKmh), systemImage: "gauge.with.dots.needle.67percent"),
                RideDisplayMetric(title: "最大 G", value: formatAccelerationG(localRecord.maxAccelerationG), systemImage: "bolt.circle.fill"),
                RideDisplayMetric(title: "轨迹点", value: "\(localRecord.points.count) 个", systemImage: "point.3.connected.trianglepath.dotted")
            ])
        }

        return result
    }
}

private struct RideTrackMapPanel: View {
    var record: NinebotRecordedRide
    @State private var cameraPosition: MapCameraPosition

    init(record: NinebotRecordedRide) {
        self.record = record
        _cameraPosition = State(initialValue: .region(Self.region(for: record.speedTrackCoordinates)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地轨迹")
                        .font(.headline)
                    Text("\(formatDate(record.startedAt)) - \(formatDate(record.endedAt))")
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Text(formatDistance(record.distanceKilometers))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }

            Map(position: $cameraPosition) {
                ForEach(record.speedTrackSegments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                if let maxSpeedPoint = record.maxSpeedTrackPoint {
                    Annotation("最快", coordinate: maxSpeedPoint.coordinate) {
                        TrackMaxSpeedBadge(speed: maxSpeedPoint.speedKmh)
                    }
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TrackSpeedLegend()

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                RideMetric(title: "开始", value: formatTime(record.startedAt), systemImage: "play.fill")
                RideMetric(title: "结束", value: formatTime(record.endedAt), systemImage: "stop.fill")
                RideMetric(title: "最快", value: formatSpeed(record.maxSpeedKmh), systemImage: "speedometer")
                RideMetric(title: "最大 G", value: formatAccelerationG(record.maxAccelerationG), systemImage: "bolt.circle.fill")
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        let minLatitude = coordinates.map(\.latitude).min() ?? coordinates[0].latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? coordinates[0].latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? coordinates[0].longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? coordinates[0].longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.5, 0.006),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.5, 0.006)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct InterfaceRideTrackMapPanel: View {
    var points: [NinebotInterfaceTrackPoint]
    @State private var cameraPosition: MapCameraPosition

    init(points: [NinebotInterfaceTrackPoint]) {
        self.points = points
        _cameraPosition = State(initialValue: .region(Self.region(for: points.map(\.coordinate))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接口轨迹")
                .font(.headline)
                .foregroundStyle(Color.teslaPrimaryText)

            Map(position: $cameraPosition) {
                ForEach(speedSegments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                if let maxSpeedPoint {
                    Annotation("最快", coordinate: maxSpeedPoint.coordinate) {
                        TrackMaxSpeedBadge(speed: maxSpeedPoint.speedKmh)
                    }
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TrackSpeedLegend()
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    private var speedPoints: [TrackSpeedPoint] {
        points.enumerated().map { index, point in
            TrackSpeedPoint(
                id: point.id.isEmpty ? "interface-\(index)" : point.id,
                coordinate: point.coordinate,
                speedKmh: point.speedKmh
            )
        }
    }

    private var speedSegments: [TrackSpeedSegment] {
        makeSpeedTrackSegments(from: speedPoints)
    }

    private var maxSpeedPoint: TrackSpeedPoint? {
        bestSpeedTrackPoint(from: speedPoints)
    }

    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        let minLatitude = coordinates.map(\.latitude).min() ?? coordinates[0].latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? coordinates[0].latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? coordinates[0].longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? coordinates[0].longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.5, 0.006),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.5, 0.006)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct TrackSpeedPoint: Identifiable {
    var id: String
    var coordinate: CLLocationCoordinate2D
    var speedKmh: Double?
}

private struct TrackSpeedSegment: Identifiable {
    var id: String
    var coordinates: [CLLocationCoordinate2D]
    var speedKmh: Double?

    var color: Color {
        speedTrackColor(speedKmh)
    }
}

private struct TrackMaxSpeedBadge: View {
    var speed: Double?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.caption2.weight(.bold))
            Text(formatSpeed(speed))
                .font(.caption2.monospacedDigit().weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.red)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 4)
    }
}

private struct TrackSpeedLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: .cyan, title: "低速")
            legendItem(color: Color.teslaGreen, title: "巡航")
            legendItem(color: .orange, title: "较快")
            legendItem(color: .red, title: "最快")
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color.teslaSecondaryText)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 16, height: 4)
            Text(title)
        }
    }
}

private extension NinebotRecordedRide {
    var coordinates: [CLLocationCoordinate2D] {
        trackCoordinates
    }

    var speedTrackPoints: [TrackSpeedPoint] {
        points
            .sorted { $0.date < $1.date }
            .filter {
                (-90...90).contains($0.latitude)
                    && (-180...180).contains($0.longitude)
                    && (($0.horizontalAccuracy ?? 0) <= 120)
            }
            .enumerated()
            .map { index, point in
                TrackSpeedPoint(
                    id: point.id.isEmpty ? "local-\(index)" : point.id,
                    coordinate: NinebotCoordinateTransform.mapKitCoordinate(latitude: point.latitude, longitude: point.longitude),
                    speedKmh: point.speedKmh
                )
            }
    }

    var speedTrackCoordinates: [CLLocationCoordinate2D] {
        speedTrackPoints.map(\.coordinate)
    }

    var speedTrackSegments: [TrackSpeedSegment] {
        makeSpeedTrackSegments(from: speedTrackPoints)
    }

    var maxSpeedTrackPoint: TrackSpeedPoint? {
        bestSpeedTrackPoint(from: speedTrackPoints)
    }
}

private func makeSpeedTrackSegments(from points: [TrackSpeedPoint]) -> [TrackSpeedSegment] {
    guard points.count > 1 else { return [] }

    return (0..<(points.count - 1)).map { index in
        let start = points[index]
        let end = points[index + 1]
        let speed = end.speedKmh ?? start.speedKmh
        return TrackSpeedSegment(
            id: "\(start.id)-\(end.id)-\(index)",
            coordinates: [start.coordinate, end.coordinate],
            speedKmh: speed
        )
    }
}

private func bestSpeedTrackPoint(from points: [TrackSpeedPoint]) -> TrackSpeedPoint? {
    points
        .filter { ($0.speedKmh ?? 0) > 0.5 }
        .max { ($0.speedKmh ?? 0) < ($1.speedKmh ?? 0) }
}

private func speedTrackColor(_ speed: Double?) -> Color {
    guard let speed else { return Color.teslaGreen }
    switch speed {
    case ..<8:
        return .cyan
    case ..<25:
        return Color.teslaGreen
    case ..<40:
        return .orange
    default:
        return .red
    }
}

private struct RideMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.teslaSecondaryText)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RawFieldSection: View {
    var title: String
    var fields: [String: JSONValue]?
    @State private var didCopy = false

    var body: some View {
        DisclosureGroup {
            if let fields, !fields.isEmpty {
                let rows = fields.sorted { lhs, rhs in
                    lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }

                VStack(spacing: 0) {
                    ForEach(rows, id: \.key) { key, value in
                        RawFieldRow(key: key, value: value.displayText)
                    }
                }
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if didCopy {
                    Label("已复制", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.teslaGreen)
                } else if let copyText {
                    Button {
                        copyRawText(copyText)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var copyText: String? {
        guard let fields, !fields.isEmpty else { return nil }
        return formattedJSON(.object(fields))
    }

    private func copyRawText(_ text: String) {
        UIPasteboard.general.string = text
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }
}

private struct RawJSONSection: View {
    var title: String
    var value: JSONValue?
    @State private var didCopy = false

    var body: some View {
        DisclosureGroup {
            if let value {
                if let object = value.objectValue, !object.isEmpty {
                    let rows = object.sorted { lhs, rhs in
                        lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                    }

                    VStack(spacing: 0) {
                        ForEach(rows, id: \.key) { key, value in
                            RawFieldRow(key: key, value: value.displayText)
                        }
                    }
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Text(value.displayText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.teslaPrimaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                }
            } else {
                Text("详情返回后会显示完整字段")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if didCopy {
                    Label("已复制", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.teslaGreen)
                } else if let copyText {
                    Button {
                        copyRawText(copyText)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var copyText: String? {
        guard let value else { return nil }
        return formattedJSON(value)
    }

    private func copyRawText(_ text: String) {
        UIPasteboard.general.string = text
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }
}

private struct RawFieldRow: View {
    var key: String
    var value: String

    var body: some View {
        let displayName = friendlyRawFieldName(key)

        VStack(alignment: .leading, spacing: 5) {
            Text(displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            if displayName != key {
                Text(key)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            Text(value.isEmpty ? "--" : value)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct RawPayloadCopyPanel: View {
    var snapshot: NinebotVehicleSnapshot
    @Binding var copiedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("原始返回值")
                        .font(.headline)
                    Text("复制车辆、状态、行程接口的完整 JSON，方便排查新字段。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            Button {
                UIPasteboard.general.string = fullPayloadText
                copiedMessage = "已复制完整返回值"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    copiedMessage = nil
                }
            } label: {
                Label("复制完整返回值", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var fullPayloadText: String {
        formattedJSON(
            .object([
                "vehicle": .object(snapshot.vehicle.raw ?? [:]),
                "status": .object(snapshot.state.rawStatus ?? [:]),
                "travel": .object(snapshot.state.rawTravel ?? [:])
            ])
        )
    }
}

extension Color {
    static let teslaPageBackground = dynamic(
        light: UIColor(red: 0.945, green: 0.952, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.025, green: 0.029, blue: 0.035, alpha: 1)
    )
    static let teslaCardBackground = dynamic(
        light: UIColor(red: 0.995, green: 0.995, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.08, blue: 0.092, alpha: 1)
    )
    static let teslaControlBackground = dynamic(
        light: UIColor(red: 0.91, green: 0.925, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.125, green: 0.135, blue: 0.152, alpha: 1)
    )
    static let teslaPrimaryText = dynamic(
        light: UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.965, alpha: 1)
    )
    static let teslaSecondaryText = dynamic(
        light: UIColor(red: 0.42, green: 0.45, blue: 0.49, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.65, blue: 0.69, alpha: 1)
    )
    static let teslaGreen = dynamic(
        light: UIColor(red: 0.13, green: 0.82, blue: 0.28, alpha: 1),
        dark: UIColor(red: 0.20, green: 0.93, blue: 0.38, alpha: 1)
    )
    static let teslaActionThumb = dynamic(
        light: UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.82, blue: 0.28, alpha: 1)
    )
    static let teslaHairline = dynamic(
        light: UIColor(red: 0, green: 0, blue: 0, alpha: 0.06),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.10)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct NinePlusCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat? = nil
    var shadowOpacity: Double = 0.05

    func body(content: Content) -> some View {
        let card = content
            .background(Color.teslaCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.teslaHairline, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 14, x: 0, y: 8)

        if let padding {
            card.padding(padding)
        } else {
            card
        }
    }
}

extension View {
    func ninePlusCard(
        cornerRadius: CGFloat = 24,
        padding: CGFloat? = nil,
        shadowOpacity: Double = 0.05
    ) -> some View {
        modifier(NinePlusCardStyle(cornerRadius: cornerRadius, padding: padding, shadowOpacity: shadowOpacity))
    }
}

private struct VehicleRow: View {
    var snapshot: NinebotVehicleSnapshot
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VehicleImage(urlString: snapshot.vehicle.imageURLString, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.vehicle.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(snapshot.state.enduranceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.state.batteryText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(batteryTextColor(snapshot.state))
                    Text(snapshot.state.primaryStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor(snapshot.state))
                        .lineLimit(1)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.teslaGreen : Color(.tertiaryLabel))
            }
            .padding(12)
            .background(Color.teslaCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func vehicleCoordinate(_ state: NinebotVehicleState) -> CLLocationCoordinate2D? {
    guard let latitude = state.latitude,
          let longitude = state.longitude,
          (-90...90).contains(latitude),
          (-180...180).contains(longitude) else {
        return nil
    }

    return mapKitCoordinate(latitude: latitude, longitude: longitude)
}

private func mapKitCoordinate(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
    NinebotCoordinateTransform.mapKitCoordinate(latitude: latitude, longitude: longitude)
}

private func formatDistance(_ value: Double?) -> String {
    formatNumber(value, unit: " km", maximumFractionDigits: 1)
}

private func formatDistanceNumber(_ value: Double?) -> String {
    formatNumber(value, unit: "", maximumFractionDigits: 1)
}

private func formatEnergyWh(_ value: Double?) -> String {
    formatNumber(value, unit: " Wh", maximumFractionDigits: 0)
}

private func formatPercent(_ value: Double?) -> String {
    formatNumber(value, unit: "%", maximumFractionDigits: 1)
}

private func formatSpeed(_ value: Double?) -> String {
    formatNumber(value, unit: " km/h", maximumFractionDigits: 1)
}

private func formatAccelerationG(_ value: Double?) -> String {
    formatNumber(value, unit: " G", maximumFractionDigits: 2, minimumFractionDigits: 2)
}

private func shortTrendValue(_ value: Double) -> String {
    if value >= 100 {
        return formatNumber(value, unit: "", maximumFractionDigits: 0)
    }
    if value >= 10 {
        return formatNumber(value, unit: "", maximumFractionDigits: 1)
    }
    return formatNumber(value, unit: "", maximumFractionDigits: 1)
}

private func formatDuration(_ minutes: Double?) -> String {
    guard let minutes else { return "--" }
    if minutes >= 60 {
        return formatNumber(minutes / 60, unit: " 小时", maximumFractionDigits: 1)
    }
    return formatNumber(minutes, unit: " 分钟", maximumFractionDigits: 0)
}

private func formatRideDate(_ date: Date) -> String {
    formatDate(date)
}

private func formattedJSON(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return value.displayText
    }
    return text
}

private func formatNumber(
    _ value: Double?,
    unit: String,
    maximumFractionDigits: Int = 6,
    minimumFractionDigits: Int = 0
) -> String {
    guard let value else { return "--\(unit)" }
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = maximumFractionDigits
    formatter.minimumFractionDigits = minimumFractionDigits
    let text = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    return "\(text)\(unit)"
}

private func boolText(_ value: Bool?, trueText: String, falseText: String) -> String {
    guard let value else { return "未知" }
    return value ? trueText : falseText
}

private func coordinateText(_ latitude: Double?, _ longitude: Double?) -> String {
    guard let latitude, let longitude else { return "--" }
    return "\(formatCoordinate(latitude)), \(formatCoordinate(longitude))"
}

private func formatCoordinate(_ value: Double?) -> String {
    formatNumber(value, unit: "", maximumFractionDigits: 8)
}

private func healthColor(_ level: NinebotVehicleHealthLevel) -> Color {
    switch level {
    case .good:
        return Color.teslaGreen
    case .attention:
        return .orange
    case .critical:
        return .red
    case .charging:
        return Color.teslaGreen
    case .unknown:
        return .secondary
    }
}

private func statusColor(_ state: NinebotVehicleState) -> Color {
    healthColor(state.health.level)
}

private func statusSystemImage(_ state: NinebotVehicleState) -> String {
    state.health.systemImage
}

private func compactVehicleStatusText(_ state: NinebotVehicleState) -> String {
    if state.isFullyCharged {
        return "已充满"
    }
    if state.isCharging == true {
        return "充电中"
    }
    if state.isPoweredOn == true {
        return "已上电"
    }
    if state.isLocked == true {
        return "已上锁"
    }
    if state.isLocked == false {
        return "未上锁"
    }
    return state.primaryStatusText
}

private func batteryTextColor(_ state: NinebotVehicleState) -> Color {
    if state.isFullyCharged { return Color.teslaGreen }
    if state.isCharging == true { return Color.teslaGreen }
    guard let battery = state.battery else { return .primary }
    if battery < 15 { return .red }
    if battery < 50 { return .orange }
    return .primary
}

private func friendlyRawFieldName(_ key: String) -> String {
    let names: [String: String] = [
        "ai_estimate_mileage": "AI 预估续航",
        "aiEstimateMileage": "AI 预估续航",
        "ai_estimated_mileage": "AI 预估续航",
        "aiEstimatedMileage": "AI 预估续航",
        "and_mac": "Android MAC",
        "battery": "电量",
        "battery_exist": "电池存在",
        "battery_list": "电池列表",
        "batteryList": "电池列表",
        "battery_main": "主电池",
        "batteryMain": "主电池",
        "battery_voltage": "电池电压",
        "batteryVoltage": "电池电压",
        "battery_vol": "电池电压",
        "batteryVol": "电池电压",
        "battery_temperature": "电池温度",
        "batteryTemperature": "电池温度",
        "battery_temp": "电池温度",
        "batteryTemp": "电池温度",
        "barrel_lock_status": "座桶锁状态",
        "ble_name": "蓝牙名称",
        "bat_voltage": "电池电压",
        "batVoltage": "电池电压",
        "bat_temperature": "电池温度",
        "batTemperature": "电池温度",
        "bat_temp": "电池温度",
        "batTemp": "电池温度",
        "batt_voltage": "电池电压",
        "battVoltage": "电池电压",
        "batt_temperature": "电池温度",
        "battTemperature": "电池温度",
        "batt_temp": "电池温度",
        "battTemp": "电池温度",
        "bms": "电池管理",
        "bms_cycle": "循环次数",
        "bmsCycle": "循环次数",
        "bmsInfo": "电池管理",
        "bms_info": "电池管理",
        "bms_volt": "电池电压",
        "bmsVolt": "电池电压",
        "bms_voltage": "电池电压",
        "bmsVoltage": "电池电压",
        "bms_temperature": "电池温度",
        "bmsTemperature": "电池温度",
        "bms_temp": "电池温度",
        "bmsTemp": "电池温度",
        "buck": "座桶",
        "business_uid": "业务用户 ID",
        "businessUID": "业务用户 ID",
        "begin_time": "开始时间",
        "beginTime": "开始时间",
        "charging": "充电状态",
        "charging_power": "充电功率",
        "chargingPower": "充电功率",
        "chargingState": "充电状态",
        "charging_protection": "充电保护",
        "color": "颜色",
        "cost_time": "用时",
        "costTime": "用时",
        "create_time": "创建时间",
        "createTime": "创建时间",
        "device_name": "设备名称",
        "distance": "里程",
        "day_total_mileage": "当日总里程",
        "detail": "每日里程",
        "dump_energy": "剩余电量",
        "dumpEnergy": "剩余电量",
        "duration": "时长",
        "ec": "能耗",
        "end_time": "结束时间",
        "endTime": "结束时间",
        "estimateMileage": "预估续航",
        "estimate_mileage": "预估续航",
        "id": "ID",
        "image": "车辆图片",
        "last_ec": "最近能耗",
        "last_mileages": "最近里程",
        "last_used_electricity": "最近用电",
        "lat": "纬度",
        "latitude": "纬度",
        "left_mileage_user_choose": "剩余里程选择",
        "list": "行程列表",
        "loc": "定位信息",
        "locationDesc": "位置描述",
        "locationInfo": "定位信息",
        "lock": "锁车状态",
        "lon": "经度",
        "longitude": "经度",
        "mileages": "里程",
        "mileage": "里程",
        "month": "月份",
        "model": "车型",
        "name": "名称",
        "pwr": "电源状态",
        "powerStatus": "电源状态",
        "precise_estimate_mileage": "精确预估续航",
        "precise_mileage_user_choose": "精确里程选择",
        "remainChargeTime": "剩余充电时间",
        "remain_charge_time": "剩余充电时间",
        "remain_charge_timestamp": "剩余充电时间戳",
        "remainingChargeTime": "剩余充电时间",
        "speed": "速度",
        "sn": "SN",
        "total_mileage": "总里程",
        "totalMileage": "总里程",
        "total_mileages": "本月里程",
        "times": "骑行次数",
        "track": "接口轨迹",
        "trail": "接口轨迹",
        "trial": "接口轨迹",
        "travel_id": "行程 ID",
        "used_electricity": "已用电量",
        "vehicle_name": "车辆名称",
        "vehicle_vin": "VIN",
        "vehicleVin": "VIN",
        "vin": "VIN",
        "VIN": "VIN",
        "volt": "电压",
        "voltage": "电压",
        "temp": "温度",
        "temperature": "温度",
        "wnumber": "车辆编号"
    ]
    return names[key] ?? key
}

private struct EmptyDashboardView: View {
    var hasConfiguration: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasConfiguration ? "antenna.radiowaves.left.and.right.slash" : "link.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(hasConfiguration ? "暂无车辆数据" : "未配置代理")
                .font(.headline)

            Text(hasConfiguration ? "刷新后会显示九号车辆状态" : "到“我的”填写代理地址并登录后即可读取车辆")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .padding(.horizontal, 20)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct VehicleImage: View {
    var urlString: String?
    var size: CGFloat
    var showsBackground = true

    var body: some View {
        ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            }

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    case .failure:
                        fallbackImage
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        fallbackImage
                    }
                }
            } else {
                fallbackImage
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackImage: some View {
        Image(systemName: "bolt.car.fill")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MetricView: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BatteryGauge: View {
    var value: Int?

    var body: some View {
        Gauge(value: Double(value ?? 0), in: 0...100) {
            Text("电量")
        } currentValueLabel: {
            Text(value.map { "\($0)" } ?? "--")
                .font(.caption.weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(gaugeColor)
    }

    private var gaugeColor: Color {
        guard let value else { return .gray }
        if value < 20 { return .red }
        if value < 50 { return .orange }
        return Color.teslaGreen
    }
}

struct NinebotDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NinebotDashboardView(model: NinebotViewModel())
    }
}
