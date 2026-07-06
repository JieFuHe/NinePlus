import Combine
import CoreLocation
import CoreMotion
import MapKit
import SwiftUI

struct NinebotRecordingView: View {
    @ObservedObject var model: NinebotViewModel
    @StateObject private var recorder = NinebotRideRecorder()
    @State private var pendingRecord: NinebotRecordedRide?

    private var snapshot: NinebotVehicleSnapshot? {
        model.dashboard.primaryVehicle
    }

    var body: some View {
        ZStack {
            RecordingBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    RecordingHeader(snapshot: snapshot, recorder: recorder)

                    RecordingSpeedGauge(
                        speedKmh: recorder.currentSpeedKmh,
                        maxSpeedKmh: recorder.maxSpeedKmh,
                        isRecording: recorder.isRecording
                    )
                    .padding(.top, 6)

                    RecordingControlPanel(
                        recorder: recorder,
                        canRecord: snapshot != nil,
                        onStart: {
                            recorder.start(vehicleSN: snapshot?.vehicle.sn)
                        },
                        onStop: {
                            guard let record = recorder.stop() else { return }
                            model.saveRecordedRide(record)
                            pendingRecord = record
                        }
                    )

                    RecordingMetricsGrid(recorder: recorder)

                    RecordingTrackPreview(
                        points: recorder.points,
                        currentPoint: recorder.currentLocationPoint
                    )

                    RecordingHistorySection(
                        records: model.recordedRides(for: snapshot?.vehicle.sn),
                        onDelete: { record in
                            model.deleteRecordedRide(id: record.id)
                        }
                    )
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $pendingRecord) { record in
            RideAssociationSheet(snapshot: snapshot, record: record) { rideID in
                var savedRecord = record
                savedRecord.vehicleSN = snapshot?.vehicle.sn
                savedRecord.associatedRideID = rideID
                model.saveRecordedRide(savedRecord)
                pendingRecord = nil
            }
        }
        .onAppear {
            recorder.startPreview()
        }
        .onDisappear {
            recorder.stopPreviewIfIdle()
        }
    }
}

@MainActor
final class NinebotRideRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isRecording = false
    @Published private(set) var currentSpeedKmh: Double = 0
    @Published private(set) var currentAccelerationG: Double = 0
    @Published private(set) var maxSpeedKmh: Double = 0
    @Published private(set) var maxAccelerationG: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var points: [NinebotRideTrackPoint] = []
    @Published private(set) var currentLocationPoint: NinebotRideTrackPoint?
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var lastErrorText: String?

    private let manager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var vehicleSN: String?
    private var lastLocation: CLLocation?
    private var lastSpeedMPS: Double?
    private var speedSamples: [Double] = []
    private var lastMotionTimestamp: TimeInterval?
    private var ignoreLocationUntil: Date?

    private let maximumReasonableSpeedKmh = 120.0
    private let maximumReasonableGPSAccelerationG = 1.5
    private let maximumReasonableMotionG = 2.5
    private let maximumReasonableSegmentDistance = 250.0
    private let maximumLocationAge: TimeInterval = 8
    private let minimumLocationDeltaTime: TimeInterval = 0.2
    private let maximumLocationDeltaTimeForSpeed: TimeInterval = 20

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 1
    }

    var elapsedSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        let endDate = isRecording ? Date() : (endedAt ?? startedAt)
        return max(endDate.timeIntervalSince(startedAt), 0)
    }

    var distanceKilometers: Double {
        distanceMeters / 1000
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startPreview() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorText = "系统定位服务未开启"
            return
        }

        if authorizationStatus == .notDetermined {
            requestAuthorization()
            return
        }

        guard isAuthorized else {
            lastErrorText = "需要定位权限才能显示实时位置"
            return
        }

        lastErrorText = nil
        startMotionUpdates()
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stopPreviewIfIdle() {
        guard !isRecording else { return }
        manager.stopUpdatingLocation()
        stopMotionUpdates()
    }

    func start(vehicleSN: String?) {
        lastErrorText = nil
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorText = "系统定位服务未开启"
            return
        }

        if authorizationStatus == .notDetermined {
            requestAuthorization()
            lastErrorText = "请允许定位后再开始记录"
            return
        }

        guard isAuthorized else {
            lastErrorText = "需要定位权限才能记录轨迹"
            return
        }

        self.vehicleSN = vehicleSN
        isRecording = true
        currentSpeedKmh = 0
        currentAccelerationG = 0
        maxSpeedKmh = 0
        maxAccelerationG = 0
        distanceMeters = 0
        points = []
        speedSamples = []
        lastLocation = nil
        lastSpeedMPS = nil
        lastMotionTimestamp = nil
        ignoreLocationUntil = Date().addingTimeInterval(1.2)
        startedAt = Date()
        endedAt = nil
        startMotionUpdates()
        manager.startUpdatingLocation()
    }

    func stop() -> NinebotRecordedRide? {
        guard isRecording, let startedAt else { return nil }
        let endedAt = Date()
        isRecording = false
        self.endedAt = endedAt

        let durationHours = max(endedAt.timeIntervalSince(startedAt) / 3600, 0)
        let averageSpeed: Double
        if durationHours > 0 {
            averageSpeed = distanceKilometers / durationHours
        } else if !speedSamples.isEmpty {
            averageSpeed = speedSamples.reduce(0, +) / Double(speedSamples.count)
        } else {
            averageSpeed = 0
        }

        return NinebotRecordedRide(
            vehicleSN: vehicleSN,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            maxSpeedKmh: maxSpeedKmh,
            averageSpeedKmh: averageSpeed,
            maxAccelerationG: maxAccelerationG,
            points: points
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if isAuthorized {
                startPreview()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastErrorText = error.localizedDescription
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            handleLocations(locations)
        }
    }

    private func handleLocations(_ locations: [CLLocation]) {
        for location in locations where isUsable(location) {
            consume(location)
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor in
                self?.consumeMotion(motion)
            }
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func consumeMotion(_ motion: CMDeviceMotion) {
        if let lastMotionTimestamp, motion.timestamp < lastMotionTimestamp {
            currentAccelerationG = 0
            return
        }
        lastMotionTimestamp = motion.timestamp

        let acceleration = motion.userAcceleration
        let g = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        guard g.isFinite, g <= maximumReasonableMotionG else {
            currentAccelerationG = 0
            return
        }

        let normalizedG = g < 0.015 ? 0 : g

        currentAccelerationG = normalizedG
        if isRecording {
            maxAccelerationG = max(maxAccelerationG, normalizedG)
        }
    }

    private func consume(_ location: CLLocation) {
        if let ignoreLocationUntil, location.timestamp < ignoreLocationUntil {
            lastLocation = location
            lastSpeedMPS = nil
            currentSpeedKmh = 0
            return
        }

        let previousLocation = lastLocation
        let previousSpeed = lastSpeedMPS
        let previousDate = previousLocation?.timestamp
        let deltaTime = previousDate.map { location.timestamp.timeIntervalSince($0) } ?? 0
        let segmentDistance = previousLocation.map { location.distance(from: $0) } ?? 0

        let speedMPS: Double
        if location.speed >= 0, (location.speedAccuracy <= 0 || location.speedAccuracy <= 8) {
            speedMPS = location.speed
        } else if deltaTime >= minimumLocationDeltaTime, deltaTime <= maximumLocationDeltaTimeForSpeed {
            speedMPS = max(segmentDistance / deltaTime, 0)
        } else {
            speedMPS = 0
        }

        let speedKmh = speedMPS * 3.6
        guard speedKmh.isFinite, speedKmh <= maximumReasonableSpeedKmh else {
            currentSpeedKmh = 0
            if !motionManager.isDeviceMotionActive {
                currentAccelerationG = 0
            }
            lastLocation = location
            lastSpeedMPS = nil
            return
        }

        let gpsAccelerationG: Double
        if let previousSpeed,
           deltaTime >= minimumLocationDeltaTime,
           deltaTime <= maximumLocationDeltaTimeForSpeed {
            gpsAccelerationG = max((speedMPS - previousSpeed) / deltaTime / 9.80665, 0)
        } else {
            gpsAccelerationG = 0
        }
        let sanitizedGPSAccelerationG = gpsAccelerationG.isFinite && gpsAccelerationG <= maximumReasonableGPSAccelerationG ? gpsAccelerationG : 0

        currentSpeedKmh = speedKmh
        if !motionManager.isDeviceMotionActive {
            currentAccelerationG = sanitizedGPSAccelerationG
        }

        let point = NinebotRideTrackPoint(
            date: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedKmh: speedKmh,
            accelerationG: currentAccelerationG,
            horizontalAccuracy: location.horizontalAccuracy
        )
        currentLocationPoint = point

        if isRecording {
            maxSpeedKmh = max(maxSpeedKmh, speedKmh)
            if !motionManager.isDeviceMotionActive {
                maxAccelerationG = max(maxAccelerationG, sanitizedGPSAccelerationG)
            }
            speedSamples.append(speedKmh)

            if deltaTime >= minimumLocationDeltaTime,
               deltaTime <= maximumLocationDeltaTimeForSpeed,
               segmentDistance >= 0,
               segmentDistance < maximumReasonableSegmentDistance {
                distanceMeters += segmentDistance
            }

            points.append(point)
        }

        lastLocation = location
        lastSpeedMPS = speedMPS
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        return location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 80
            && age <= maximumLocationAge
            && (-90...90).contains(location.coordinate.latitude)
            && (-180...180).contains(location.coordinate.longitude)
    }
}

private struct RecordingBackground: View {
    var body: some View {
        Color.teslaPageBackground
    }
}

private struct RecordingHeader: View {
    var snapshot: NinebotVehicleSnapshot?
    @ObservedObject var recorder: NinebotRideRecorder

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot?.vehicle.name ?? "暂无车辆")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.teslaGreen)
                    .frame(width: 8, height: 8)
                Text(recorder.isRecording ? "REC" : "READY")
                    .font(.caption.monospacedDigit().weight(.bold))
            }
            .foregroundStyle(Color.teslaPrimaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.teslaCardBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.teslaHairline, lineWidth: 1)
            }
        }
    }

    private var statusText: String {
        if let error = recorder.lastErrorText {
            return error
        }
        if recorder.isRecording {
            return "正在记录速度、G 值和轨迹"
        }
        if recorder.authorizationStatus == .notDetermined {
            return "允许定位后会显示实时位置"
        }
        if !recorder.isAuthorized {
            return "需要在系统设置里允许定位"
        }
        return "当前位置实时显示，点击开始记录"
    }

    private var statusColor: Color {
        recorder.lastErrorText == nil ? Color.teslaSecondaryText : .orange
    }
}

private struct RecordingSpeedGauge: View {
    var speedKmh: Double
    var maxSpeedKmh: Double
    var isRecording: Bool

    private let maxGaugeSpeed = 80.0

    var body: some View {
        ZStack {
            ForEach(0..<33, id: \.self) { index in
                Capsule()
                    .fill(index % 4 == 0 ? Color.teslaSecondaryText.opacity(0.74) : Color.teslaSecondaryText.opacity(0.28))
                    .frame(width: index % 4 == 0 ? 3 : 2, height: index % 4 == 0 ? 18 : 10)
                    .offset(y: -128)
                    .rotationEffect(.degrees(Double(index) / 32 * 270 - 135))
            }

            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(Color.teslaControlBackground, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.125, to: 0.125 + min(max(speedKmh / maxGaugeSpeed, 0), 1) * 0.75)
                .stroke(
                    LinearGradient(
                        colors: [Color.teslaGreen, .yellow, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: Color.teslaGreen.opacity(isRecording ? 0.55 : 0.18), radius: isRecording ? 18 : 6)

            VStack(spacing: 6) {
                Text(formatRecordingSpeed(speedKmh, showsUnit: false))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Text("km/h")
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward")
                    Text("MAX \(formatRecordingSpeed(maxSpeedKmh))")
                }
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.teslaGreen)
                .padding(.top, 8)
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct RecordingControlPanel: View {
    @ObservedObject var recorder: NinebotRideRecorder
    var canRecord: Bool
    var onStart: () -> Void
    var onStop: () -> Void

    var body: some View {
        Button {
            recorder.isRecording ? onStop() : onStart()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "play.fill")
                    .font(.headline.weight(.bold))
                Text(recorder.isRecording ? "结束记录" : "开始记录")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(recorder.isRecording ? .white : .black)
            .background(recorder.isRecording ? Color.red : Color.teslaGreen)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: (recorder.isRecording ? Color.red : Color.teslaGreen).opacity(0.28), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .opacity(canRecord ? 1 : 0.45)
    }
}

private struct RecordingMetricsGrid: View {
    @ObservedObject var recorder: NinebotRideRecorder

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                RecordingMetricTile(title: "当前 G", value: formatRecordingG(recorder.currentAccelerationG), systemImage: "bolt.circle.fill", tint: .yellow)
                RecordingMetricTile(title: "最大 G", value: formatRecordingG(recorder.maxAccelerationG), systemImage: "bolt.fill", tint: .red)
                RecordingMetricTile(title: "距离", value: formatRecordingDistance(recorder.distanceKilometers), systemImage: "point.3.connected.trianglepath.dotted", tint: Color.teslaGreen)
                RecordingMetricTile(title: "时长", value: formatRecordingDuration(recorder.elapsedSeconds), systemImage: "timer", tint: Color.teslaSecondaryText)
            }
        }
    }
}

private struct RecordingMetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }

            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
        }
        .padding(14)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct RecordingTrackPreview: View {
    var points: [NinebotRideTrackPoint]
    var currentPoint: NinebotRideTrackPoint?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时轨迹")
                    .font(.headline)
                    .foregroundStyle(Color.teslaPrimaryText)
                Spacer()
                Text("\(points.count) 点")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            ZStack {
                Map(position: $cameraPosition, interactionModes: []) {
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(Color.teslaGreen, lineWidth: 4)
                    }

                    if let last = displayCoordinates.last {
                        Marker("当前位置", systemImage: "location.fill", coordinate: last)
                            .tint(Color.teslaGreen)
                    }
                }
                .onChange(of: points.count) { _, _ in
                    followCurrentLocation()
                }
                .onChange(of: currentPoint?.id) { _, _ in
                    followCurrentLocation()
                }
                .onAppear {
                    followCurrentLocation()
                }

                if displayCoordinates.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "location.viewfinder")
                            .font(.title2.weight(.semibold))
                        Text("正在获取当前位置")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Color.teslaSecondaryText)
                    .padding(18)
                    .background(Color.teslaCardBackground.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        points.map {
            recordingMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        currentPoint.map {
            recordingMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var displayCoordinates: [CLLocationCoordinate2D] {
        if !coordinates.isEmpty {
            return coordinates
        }
        return currentCoordinate.map { [$0] } ?? []
    }

    private func followCurrentLocation() {
        guard let current = displayCoordinates.last else {
            cameraPosition = .automatic
            return
        }

        cameraPosition = .region(
            MKCoordinateRegion(
                center: current,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
        )
    }
}

private struct RecordingHistorySection: View {
    var records: [NinebotRecordedRide]
    var onDelete: (NinebotRecordedRide) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近记录")
                .font(.headline)
                .foregroundStyle(Color.teslaPrimaryText)

            if records.isEmpty {
                Text("结束一次记录后会出现在这里")
                    .font(.subheadline)
                    .foregroundStyle(Color.teslaSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.teslaCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.teslaHairline, lineWidth: 1)
                    }
            } else {
                VStack(spacing: 8) {
                    ForEach(records.prefix(5)) { record in
                        NavigationLink {
                            RecordedRideDetailView(record: record, onDelete: onDelete)
                        } label: {
                            RecordedRideRowContent(record: record)
                        }
                        .buttonStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct RecordedRideRowContent: View {
    var record: NinebotRecordedRide

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.associatedRideID == nil ? "record.circle" : "checkmark.circle.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(record.associatedRideID == nil ? Color.teslaSecondaryText : Color.teslaGreen)

            VStack(alignment: .leading, spacing: 3) {
                Text(formatRecordingDate(record.startedAt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.teslaPrimaryText)
                Text(record.associatedRideID == nil ? "未关联行程" : "已关联行程")
                    .font(.caption)
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formatRecordingDistance(record.distanceKilometers))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.teslaPrimaryText)
                Text(formatRecordingSpeed(record.maxSpeedKmh))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.teslaSecondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color.teslaCardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct RecordedRideDetailView: View {
    var record: NinebotRecordedRide
    var onDelete: (NinebotRecordedRide) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecordedRideDetailHero(record: record)
                RecordedRideTrackMap(record: record)
                RecordedRideDetailMetrics(record: record)

                if let associatedRideID = record.associatedRideID {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("已关联接口行程", systemImage: "link")
                            .font(.headline)
                            .foregroundStyle(Color.teslaPrimaryText)
                        Text(associatedRideID)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.teslaSecondaryText)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teslaCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.teslaHairline, lineWidth: 1)
                    }
                }

                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("删除这条记录", systemImage: "trash.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Color.teslaPageBackground.ignoresSafeArea())
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("删除这条记录？", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                onDelete(record)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(formatRecordingDate(record.startedAt)) · \(formatRecordingDistance(record.distanceKilometers))")
        }
    }
}

private struct RecordedRideDetailHero: View {
    var record: NinebotRecordedRide

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatRecordingDate(record.startedAt))
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text("\(formatRecordingDate(record.startedAt)) - \(formatRecordingDate(record.endedAt))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Image(systemName: "map.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.teslaGreen)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(formatRecordingDistance(record.distanceKilometers))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.teslaPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("本地记录")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct RecordedRideTrackMap: View {
    var record: NinebotRecordedRide
    @State private var cameraPosition: MapCameraPosition

    init(record: NinebotRecordedRide) {
        self.record = record
        _cameraPosition = State(initialValue: .region(Self.region(for: record.recordingCoordinates)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("轨迹")
                    .font(.headline)
                    .foregroundStyle(Color.teslaPrimaryText)
                Spacer()
                Text("\(record.points.count) 点")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            ZStack {
                Map(position: $cameraPosition) {
                    if record.recordingCoordinates.count > 1 {
                        MapPolyline(coordinates: record.recordingCoordinates)
                            .stroke(Color.teslaGreen, lineWidth: 4)
                    }

                    if let first = record.recordingCoordinates.first {
                        Marker("开始", systemImage: "play.fill", coordinate: first)
                            .tint(Color.teslaGreen)
                    }

                    if let last = record.recordingCoordinates.last {
                        Marker("结束", systemImage: "stop.fill", coordinate: last)
                            .tint(.red)
                    }
                }

                if record.recordingCoordinates.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.title2.weight(.semibold))
                        Text("这条记录没有轨迹点")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Color.teslaSecondaryText)
                    .padding(18)
                    .background(Color.teslaCardBackground.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
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
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.5, 0.006),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.5, 0.006)
            )
        )
    }
}

private struct RecordedRideDetailMetrics: View {
    var record: NinebotRecordedRide

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            RecordingDetailMetric(title: "开始", value: formatRecordingDate(record.startedAt), systemImage: "play.fill", tint: Color.teslaGreen)
            RecordingDetailMetric(title: "结束", value: formatRecordingDate(record.endedAt), systemImage: "stop.fill", tint: .red)
            RecordingDetailMetric(title: "时长", value: formatRecordingDuration(record.durationSeconds), systemImage: "timer", tint: Color.teslaSecondaryText)
            RecordingDetailMetric(title: "均速", value: formatRecordingSpeed(record.averageSpeedKmh), systemImage: "speedometer", tint: Color.teslaGreen)
            RecordingDetailMetric(title: "最快", value: formatRecordingSpeed(record.maxSpeedKmh), systemImage: "gauge.with.dots.needle.67percent", tint: .yellow)
            RecordingDetailMetric(title: "最大 G", value: formatRecordingG(record.maxAccelerationG), systemImage: "bolt.circle.fill", tint: .red)
            RecordingDetailMetric(title: "轨迹点", value: "\(record.points.count) 个", systemImage: "point.3.connected.trianglepath.dotted", tint: Color.teslaGreen)
            RecordingDetailMetric(title: "关联", value: record.associatedRideID == nil ? "未关联" : "已关联", systemImage: "link", tint: record.associatedRideID == nil ? Color.teslaSecondaryText : Color.teslaGreen)
        }
    }
}

private struct RecordingDetailMetric: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }
}

private struct RideAssociationSheet: View {
    var snapshot: NinebotVehicleSnapshot?
    var record: NinebotRecordedRide
    var onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(formatRecordingDistance(record.distanceKilometers))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        HStack {
                            Label(formatRecordingSpeed(record.maxSpeedKmh), systemImage: "speedometer")
                            Spacer()
                            Label(formatRecordingG(record.maxAccelerationG), systemImage: "bolt.circle.fill")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("关联到哪段行程") {
                    if let rides = snapshot?.state.rides, !rides.isEmpty {
                        ForEach(Array(rides.prefix(20).enumerated()), id: \.element.id) { index, ride in
                            Button {
                                onSave(ride.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ride.startedAt.map(formatRecordingDate) ?? "行程 \(index + 1)")
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(formatRecordingDistance(ride.mileage ?? 0)) · \(formatRecordingDuration((ride.durationMinutes ?? 0) * 60))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } else {
                        Text("当前车辆暂无可关联的接口行程")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        onSave(nil)
                        dismiss()
                    } label: {
                        Label("暂不关联，直接保存", systemImage: "tray.and.arrow.down.fill")
                    }
                }
            }
            .navigationTitle("保存记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        pendingDiscard()
                    }
                }
            }
        }
    }

    private func pendingDiscard() {
        dismiss()
    }
}

private extension NinebotRecordedRide {
    var recordingCoordinates: [CLLocationCoordinate2D] {
        points.map {
            recordingMapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}

private func formatRecordingSpeed(_ value: Double, showsUnit: Bool = true) -> String {
    formatRecordingNumber(value, unit: showsUnit ? " km/h" : "", maximumFractionDigits: 1)
}

private func formatRecordingDistance(_ value: Double) -> String {
    formatRecordingNumber(value, unit: " km", maximumFractionDigits: 2)
}

private func formatRecordingG(_ value: Double) -> String {
    formatRecordingNumber(value, unit: " G", maximumFractionDigits: 2, minimumFractionDigits: 2)
}

private func formatRecordingDuration(_ seconds: TimeInterval) -> String {
    let seconds = max(Int(seconds), 0)
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let restSeconds = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, restSeconds)
    }
    return String(format: "%02d:%02d", minutes, restSeconds)
}

private func formatRecordingDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}

private func formatRecordingNumber(
    _ value: Double,
    unit: String,
    maximumFractionDigits: Int,
    minimumFractionDigits: Int = 0
) -> String {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = maximumFractionDigits
    formatter.minimumFractionDigits = minimumFractionDigits
    let text = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    return "\(text)\(unit)"
}

private func recordingMapCoordinate(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
    let mapCoordinate = NinebotCoordinateTransform.gcj02Coordinate(latitude: latitude, longitude: longitude)
    return CLLocationCoordinate2D(latitude: mapCoordinate.latitude, longitude: mapCoordinate.longitude)
}
