import SwiftUI
import UIKit
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct NinebotWidgetBundle: WidgetBundle {
    var body: some Widget {
        NinebotStatusWidget()
        NinebotLockScreenWidget()
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            NinebotChargingLiveActivity()
        }
        #endif
    }
}

struct NinebotStatusWidget: Widget {
    private let kind = "NinebotStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NinebotTimelineProvider()) { entry in
            NinebotHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("九号车况")
        .description("显示车辆电量、续航和更新时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct NinebotLockScreenWidget: Widget {
    private let kind = "NinebotLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NinebotTimelineProvider()) { entry in
            NinebotAccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("九号锁屏")
        .description("在锁屏显示九号车辆状态。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct NinebotChargingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NinebotChargingActivityAttributes.self) { context in
            NinebotChargingLiveActivityCard(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(WidgetTheme.chargingActivityBackground)
            .activitySystemActionForegroundColor(WidgetTheme.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ChargingIslandTitle(attributes: context.attributes, state: context.state)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ChargingIslandRemaining(state: context.state)
                        .padding(.top, 2)
                        .padding(.trailing, 12)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ChargingIslandBottom(state: context.state)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetTheme.green)
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                Text("\(context.state.battery)%")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(WidgetTheme.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(WidgetTheme.green)
            }
            .keylineTint(WidgetTheme.green)
        }
        .configurationDisplayName("九号充电")
        .description("充电时在锁屏和灵动岛显示电量、预计时间和电池状态。")
    }
}

@available(iOS 16.1, *)
private struct NinebotChargingLiveActivityCard: View {
    var attributes: NinebotChargingActivityAttributes
    var state: NinebotChargingActivityAttributes.ContentState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            chargingCardGradient(for: colorScheme)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Label("充电中", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(chargingCardPrimaryText(for: colorScheme))

                    Spacer(minLength: 8)

                    Image(systemName: "bolt.batteryblock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(chargingCardPrimaryText(for: colorScheme).opacity(0.90))
                }

                HStack(alignment: .bottom, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(state.battery)%")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetTheme.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        Text(chargingRangeText(state))
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetTheme.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("剩余时间")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(chargingCardSecondaryText(for: colorScheme))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        ChargingRemainingText(estimatedFullAt: state.estimatedFullAt)
                            .font(.system(size: 29, weight: .heavy, design: .rounded).italic())
                            .monospacedDigit()
                            .foregroundStyle(chargingCardSecondaryText(for: colorScheme).opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.52)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(width: 112, alignment: .trailing)
                }

                ChargingLiveProgressBar(value: Double(state.battery) / 100)
                    .frame(height: 6)
                    .padding(.top, 1)

                HStack(spacing: 8) {
                    ChargingLiveMetric(value: chargingPowerText(state), title: "充电功率")
                    ChargingLiveMetric(value: chargingTemperatureText(state), title: "电池温度")
                    ChargingLiveMetric(value: chargingSpeedText(state), title: "充电速度")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

@available(iOS 16.1, *)
private struct ChargingIslandTitle: View {
    var attributes: NinebotChargingActivityAttributes
    var state: NinebotChargingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("充电中", systemImage: "bolt.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetTheme.green)
            Text(attributes.vehicleName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(state.battery)%")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.green)
        }
        .frame(maxWidth: 124, alignment: .leading)
    }
}

@available(iOS 16.1, *)
private struct ChargingIslandRemaining: View {
    var state: NinebotChargingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("剩余")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ChargingRemainingText(estimatedFullAt: state.estimatedFullAt)
                .font(.system(size: 22, weight: .heavy, design: .rounded).italic())
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(chargingRangeText(state))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.green)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 88, alignment: .trailing)
    }
}

@available(iOS 16.1, *)
private struct ChargingIslandBottom: View {
    var state: NinebotChargingActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            ChargingLiveProgressBar(value: Double(state.battery) / 100)
                .frame(height: 5)

            HStack(spacing: 8) {
                ChargingIslandMetric(value: chargingPowerText(state), title: "功率")
                ChargingIslandMetric(value: chargingTemperatureText(state), title: "温度")
                ChargingIslandMetric(value: chargingSpeedText(state), title: "速度")
            }
        }
    }
}

@available(iOS 16.1, *)
private struct ChargingCompactRemainingText: View {
    var state: NinebotChargingActivityAttributes.ContentState

    var body: some View {
        ChargingRemainingText(estimatedFullAt: state.estimatedFullAt)
            .font(.caption2.monospacedDigit().weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

private struct ChargingRemainingText: View {
    var estimatedFullAt: Date?

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            Text(remainingText(now: context.date))
        }
    }

    private func remainingText(now: Date) -> String {
        guard let estimatedFullAt else { return "--" }
        let remainingSeconds = estimatedFullAt.timeIntervalSince(now)
        guard remainingSeconds > 0 else { return "0分" }

        let totalMinutes = max(Int(ceil(remainingSeconds / 60)), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        }
        return "\(minutes)分"
    }
}

private struct ChargingLiveMetric: View {
    var value: String
    var title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 23, weight: .heavy, design: .rounded).italic())
                .monospacedDigit()
                .foregroundStyle(chargingCardSecondaryText(for: colorScheme).opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(chargingCardSecondaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChargingIslandMetric: View {
    var value: String
    var title: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChargingLiveProgressBar: View {
    var value: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(chargingProgressTrackColor(for: colorScheme))
                Capsule()
                    .fill(WidgetTheme.green)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), 8))
            }
        }
    }
}

private func chargingCardGradient(for colorScheme: ColorScheme) -> LinearGradient {
    if colorScheme == .dark {
        return LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.11),
                Color(red: 0.045, green: 0.08, blue: 0.075),
                Color(red: 0.055, green: 0.11, blue: 0.085)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    return LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.90, blue: 1.0),
            Color(red: 0.91, green: 0.96, blue: 1.0),
            Color(red: 0.82, green: 1.0, blue: 0.96)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private func chargingCardPrimaryText(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.86)
}

private func chargingCardSecondaryText(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.46)
}

private func chargingProgressTrackColor(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
}

@available(iOS 16.1, *)
private func chargingRangeText(_ state: NinebotChargingActivityAttributes.ContentState) -> String {
    guard let range = state.estimatedRange else { return "--km" }
    return "\(formatWidgetNumber(range, maximumFractionDigits: 0))km"
}

@available(iOS 16.1, *)
private func chargingPowerText(_ state: NinebotChargingActivityAttributes.ContentState) -> String {
    guard let power = state.chargingPower else { return "--W" }
    return "\(formatWidgetNumber(power, maximumFractionDigits: 0))W"
}

@available(iOS 16.1, *)
private func chargingTemperatureText(_ state: NinebotChargingActivityAttributes.ContentState) -> String {
    guard let temperature = state.batteryTemperature else { return "--°C" }
    return "\(formatWidgetNumber(temperature, maximumFractionDigits: 0))°C"
}

@available(iOS 16.1, *)
private func chargingSpeedText(_ state: NinebotChargingActivityAttributes.ContentState) -> String {
    guard let speed = state.chargingSpeed else { return "--km/h" }
    return "\(formatWidgetNumber(speed, maximumFractionDigits: 0))km/h"
}
#endif

private struct NinebotHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NinebotWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.dashboard.primaryVehicle {
                switch family {
                case .systemSmall:
                    SmallStatusWidget(
                        snapshot: snapshot,
                        vehicleImageData: entry.vehicleImages[snapshot.vehicle.sn]
                    )
                case .systemLarge:
                    LargeStatusWidget(
                        dashboard: entry.dashboard,
                        vehicleImages: entry.vehicleImages
                    )
                default:
                    MediumStatusWidget(dashboard: entry.dashboard)
                }
            } else {
                EmptyWidgetView(message: entry.errorMessage ?? "暂无车辆")
            }
        }
        .containerBackground(WidgetTheme.pageBackground, for: .widget)
    }
}

private struct SmallStatusWidget: View {
    var snapshot: NinebotVehicleSnapshot
    var vehicleImageData: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(WidgetTheme.smallVehicleBackground)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 20)
                .frame(width: 128, height: 128)
                .offset(x: 54, y: 40)

            WidgetVehicleImage(imageData: vehicleImageData)
                .frame(width: 154, height: 94)
                .offset(x: 48, y: 42)

            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.vehicle.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(alignment: .center, spacing: 8) {
                    SmallWidgetBatteryRing(
                        value: snapshot.state.batteryFraction,
                        battery: snapshot.state.battery,
                        isCharging: snapshot.state.isCharging == true
                    )
                    .frame(width: 30, height: 30)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(estimatedRangeDigits(snapshot.state))
                            .font(.system(size: 35, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                        Text("km")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 34)

                if snapshot.state.isCharging == true {
                    Label("充电中", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetTheme.green)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct SmallWidgetBatteryRing: View {
    var value: Double
    var battery: Int?
    var isCharging: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 5)

            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(activeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(WidgetTheme.smallVehicleBackground)
                .frame(width: 12, height: 12)
        }
    }

    private var activeColor: Color {
        if isCharging { return WidgetTheme.green }
        guard let battery else { return WidgetTheme.green }
        return battery < 20 ? .red : WidgetTheme.green
    }
}

private struct MediumStatusWidget: View {
    var dashboard: NinebotDashboard

    var body: some View {
        if let primary = dashboard.primaryVehicle {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(primary.vehicle.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(estimatedRangeDigits(primary.state))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(WidgetTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.58)

                            Text("km")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(WidgetTheme.primaryText)

                            Text("预估")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WidgetTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(formatWidgetTime(primary.state.updatedAt)) 更新")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(WidgetTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(primary.state.batteryText)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(batteryColor(primary.state.battery, isCharging: primary.state.isCharging == true))
                            .lineLimit(1)

                        MediumWidgetStatusPill(state: primary.state)
                    }
                    .frame(width: 112, alignment: .trailing)
                }

                MediumBatteryProgressBar(
                    value: primary.state.batteryFraction,
                    battery: primary.state.battery,
                    isCharging: primary.state.isCharging == true
                )
                .frame(height: 7)

                MediumWidgetControlStrip(state: primary.state)
                    .frame(height: 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        } else {
            EmptyWidgetView(message: "暂无车辆")
        }
    }
}

private struct MediumBatteryProgressBar: View {
    var value: Double
    var battery: Int?
    var isCharging: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WidgetTheme.secondaryText.opacity(0.18))
                Capsule()
                    .fill(activeColor)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), 5))
            }
        }
    }

    private var activeColor: Color {
        if isCharging { return WidgetTheme.green }
        guard let battery else { return WidgetTheme.green }
        return battery < 20 ? .red : WidgetTheme.green
    }
}

private struct MediumWidgetInlineStatus: View {
    var state: NinebotVehicleState

    var body: some View {
        Label(widgetStatusText(state), systemImage: widgetStatusImage(state))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(state))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct MediumWidgetStatusPill: View {
    var state: NinebotVehicleState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)

            Text(statusText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WidgetTheme.cardBackground.opacity(0.86))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private var statusText: String {
        if state.isFullyCharged { return "电量已充满" }
        if state.isCharging == true { return "正在充电" }
        if state.isLocked == true { return "守卫模式已开启" }
        if state.isLocked == false { return "车辆未上锁" }
        return widgetStatusText(state)
    }

    private var statusDotColor: Color {
        if state.isLocked == false { return .orange }
        if state.isCharging == true || state.isFullyCharged { return WidgetTheme.green }
        return WidgetTheme.primaryText
    }
}

private struct MediumWidgetControlStrip: View {
    var state: NinebotVehicleState

    var body: some View {
        HStack(spacing: 0) {
            MediumWidgetControlIcon(systemImage: state.isFullyCharged ? "battery.100" : (state.isCharging == true ? "bolt.fill" : "power"))
            MediumWidgetControlIcon(systemImage: "shippingbox.fill")
            MediumWidgetControlIcon(systemImage: "speaker.wave.2.fill")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetTheme.cardBackground.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
    }
}

private struct MediumWidgetControlIcon: View {
    var systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(WidgetTheme.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .minimumScaleFactor(0.78)
    }
}

private struct LargeStatusWidget: View {
    var dashboard: NinebotDashboard
    var vehicleImages: [String: Data] = [:]

    var body: some View {
        if let primary = dashboard.primaryVehicle {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(primary.vehicle.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WidgetTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        Text("\(formatWidgetTime(primary.state.updatedAt)) 更新")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WidgetTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    WidgetVehicleImage(imageData: vehicleImages[primary.vehicle.sn])
                        .frame(width: 142, height: 72)
                }

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(estimatedRangeText(primary.state))
                        .font(.system(size: 39, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.52)

                    Spacer(minLength: 8)

                    Text(primary.state.batteryText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(batteryColor(primary.state.battery, isCharging: primary.state.isCharging == true))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }

                WidgetBatteryBar(value: primary.state.batteryFraction, isCharging: primary.state.isCharging == true, height: 7)

                HStack(spacing: 8) {
                    WidgetInfoTile(title: "本月日均", value: primary.state.dailyAverageMileageText, systemImage: "calendar")
                    WidgetInfoTile(title: "行程均速", value: primary.state.averageSpeedText, systemImage: "speedometer")
                    WidgetInfoTile(title: "最近骑行", value: primary.state.lastRideSummaryText, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .frame(height: 60)

                WidgetLargeControlStrip(state: primary.state)
                    .frame(height: 44)
            }
            .padding(14)
        } else {
            EmptyWidgetView(message: "暂无车辆")
        }
    }
}

private struct NinebotAccessoryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NinebotWidgetEntry

    var body: some View {
        let snapshot = entry.dashboard.primaryVehicle

        Group {
            switch family {
            case .accessoryCircular:
                AccessoryCircularStatus(snapshot: snapshot)
            case .accessoryInline:
                if let snapshot {
                    Label("\(snapshot.vehicle.name) \(snapshot.state.batteryText) \(compactWidgetStatus(snapshot.state))", systemImage: widgetStatusImage(snapshot.state))
                } else {
                    Label("九号暂无数据", systemImage: "bolt.car.fill")
                }
            default:
                AccessoryRectangularStatus(snapshot: snapshot)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct AccessoryRectangularStatus: View {
    var snapshot: NinebotVehicleSnapshot?

    var body: some View {
        if let snapshot {
            HStack(spacing: 8) {
                Image(systemName: widgetStatusImage(snapshot.state))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(statusColor(snapshot.state))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.vehicle.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(accessoryRectangularText(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 4)

                Text(snapshot.state.batteryText)
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(batteryColor(snapshot.state.battery, isCharging: snapshot.state.isCharging == true))
                    .lineLimit(1)
            }
        } else {
            Label("九号暂无数据", systemImage: "bolt.car.fill")
                .font(.headline)
                .lineLimit(1)
        }
    }
}

private struct AccessoryCircularStatus: View {
    var snapshot: NinebotVehicleSnapshot?

    var body: some View {
        let state = snapshot?.state
        let fraction = max(0.04, min(state?.batteryFraction ?? 0, 1))

        ZStack {
            AccessoryWidgetBackground()

            Circle()
                .stroke(.primary.opacity(0.24), lineWidth: 7)
                .padding(2)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)

            Text(accessoryCircularPercentText(state))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.54)
                .padding(.horizontal, 7)
            .foregroundStyle(.primary)
            .widgetAccentable()
        }
    }
}

private struct EmptyWidgetView: View {
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .foregroundStyle(.secondary)
        .padding()
    }
}

private struct WidgetLargeControlStrip: View {
    var state: NinebotVehicleState

    var body: some View {
        HStack(spacing: 8) {
            WidgetLargeControlItem(
                title: state.isFullyCharged ? "已满" : (state.isCharging == true ? "充电" : "电源"),
                systemImage: state.isFullyCharged ? "battery.100" : (state.isCharging == true ? "bolt.fill" : "power"),
                accent: (state.isFullyCharged || state.isCharging == true) ? WidgetTheme.green : WidgetTheme.primaryText
            )
            WidgetLargeControlItem(title: "座桶", systemImage: "shippingbox.fill", accent: WidgetTheme.primaryText)
            WidgetLargeControlItem(title: "寻车", systemImage: "bell.fill", accent: WidgetTheme.primaryText)
        }
    }
}

private struct WidgetLargeControlItem: View {
    var title: String
    var systemImage: String
    var accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WidgetControlGrid: View {
    var state: NinebotVehicleState
    var padding: CGFloat = 18
    var spacing: CGFloat = 18
    var cornerRadius: CGFloat = 30
    var glyphSize: CGFloat = 34

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: spacing
        ) {
            WidgetControlGlyph(systemImage: state.isFullyCharged ? "battery.100" : (state.isCharging == true ? "bolt.fill" : "power"), size: glyphSize)
            WidgetControlGlyph(systemImage: "shippingbox.fill", size: glyphSize)
            WidgetControlGlyph(systemImage: "bell.fill", size: glyphSize)
        }
        .padding(padding)
        .background(WidgetTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct WidgetControlGlyph: View {
    var systemImage: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(17, size * 0.68), weight: .semibold))
            .foregroundStyle(WidgetTheme.primaryText)
            .frame(width: size, height: size)
    }
}

private struct WidgetRoundControlIcon: View {
    var systemImage: String

    var body: some View {
        ZStack {
            Circle()
                .fill(WidgetTheme.cardBackground)
            Image(systemName: systemImage)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(WidgetTheme.primaryText)
        }
    }
}

private struct WidgetVehicleImage: View {
    var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fallback: some View {
        Image(systemName: "bicycle")
            .font(.system(size: 42, weight: .medium))
            .foregroundStyle(WidgetTheme.secondaryText.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WidgetBatteryBar: View {
    var value: Double
    var isCharging: Bool
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WidgetTheme.controlBackground)
                Capsule()
                    .fill(batteryAccent(isCharging: isCharging))
                    .frame(width: max(proxy.size.width * value, 8))
            }
        }
        .frame(height: height)
    }
}

private struct WidgetStatusLine: View {
    var state: NinebotVehicleState

    var body: some View {
        Label(widgetStatusText(state), systemImage: widgetStatusImage(state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor(state))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct WidgetStatusPill: View {
    var state: NinebotVehicleState

    var body: some View {
        Label(widgetStatusText(state), systemImage: widgetStatusImage(state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetTheme.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(WidgetTheme.controlBackground)
            .clipShape(Capsule())
    }
}

private struct WidgetInfoTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WidgetTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func batteryColor(_ value: Int?, isCharging: Bool = false) -> Color {
    if isCharging { return WidgetTheme.green }
    guard let value else { return .gray }
    if value < 15 { return .red }
    if value < 50 { return .orange }
    return WidgetTheme.green
}

private func healthColor(_ level: NinebotVehicleHealthLevel) -> Color {
    switch level {
    case .good:
        return WidgetTheme.green
    case .attention:
        return .orange
    case .critical:
        return .red
    case .charging:
        return WidgetTheme.green
    case .unknown:
        return .secondary
    }
}

private func statusColor(_ state: NinebotVehicleState) -> Color {
    healthColor(state.health.level)
}

private func batteryAccent(isCharging: Bool) -> Color {
    isCharging ? WidgetTheme.green : WidgetTheme.green
}

private func estimatedRangeText(_ state: NinebotVehicleState) -> String {
    "\(estimatedRangeShortText(state))(预估)"
}

private func estimatedRangeShortText(_ state: NinebotVehicleState) -> String {
    guard let mileage = state.localEstimatedMileage else { return "--km" }
    return "\(formatWidgetNumber(mileage, maximumFractionDigits: 0))km"
}

private func estimatedRangeDigits(_ state: NinebotVehicleState) -> String {
    guard let mileage = state.localEstimatedMileage else { return "--" }
    return formatWidgetNumber(mileage, maximumFractionDigits: 0)
}

private func formatWidgetNumber(_ value: Double, maximumFractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = maximumFractionDigits
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formatWidgetDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

private func formatWidgetTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func primaryWidgetStatus(_ state: NinebotVehicleState) -> String {
    state.health.message
}

private func compactWidgetStatus(_ state: NinebotVehicleState) -> String {
    if state.isFullyCharged {
        return "已充满"
    }
    if state.isCharging == true {
        return "充电 \(state.estimatedFullChargeTimeText)"
    }
    return state.health.title
}

private func accessoryRectangularText(_ snapshot: NinebotVehicleSnapshot?) -> String {
    guard let snapshot else { return "-- km · 未连接" }
    if snapshot.state.isFullyCharged {
        return "\(estimatedRangeText(snapshot.state)) · 已充满"
    }
    if snapshot.state.isCharging == true {
        return "充电中 · \(snapshot.state.estimatedFullChargeTimeText)充满"
    }
    return "\(estimatedRangeText(snapshot.state)) · \(widgetStatusText(snapshot.state))"
}

private func widgetStatusText(_ state: NinebotVehicleState) -> String {
    if state.isFullyCharged { return "已充满" }
    if state.isCharging == true { return "充电中" }
    if state.isPoweredOn == true { return "已上电" }
    if state.isLocked == true { return "已上锁" }
    if state.isLocked == false { return "未上锁" }
    return state.health.title
}

private func widgetStatusImage(_ state: NinebotVehicleState) -> String {
    if state.isFullyCharged { return "battery.100" }
    if state.isCharging == true { return "bolt.fill" }
    if state.isPoweredOn == true { return "power" }
    if state.isLocked == true { return "lock.fill" }
    if state.isLocked == false { return "lock.open.fill" }
    return state.health.systemImage
}

private func accessoryCircularPercentText(_ state: NinebotVehicleState?) -> String {
    guard let battery = state?.battery else { return "--" }
    return "\(battery)%"
}

private enum WidgetTheme {
    static let pageBackground = dynamic(
        light: UIColor(red: 0.945, green: 0.952, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.025, green: 0.029, blue: 0.035, alpha: 1)
    )
    static let cardBackground = dynamic(
        light: UIColor(red: 0.995, green: 0.995, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.08, blue: 0.092, alpha: 1)
    )
    static let controlBackground = dynamic(
        light: UIColor(red: 0.91, green: 0.925, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.125, green: 0.135, blue: 0.152, alpha: 1)
    )
    static let smallVehicleBackground = dynamic(
        light: UIColor(red: 0.105, green: 0.108, blue: 0.112, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.048, blue: 0.054, alpha: 1)
    )
    static let chargingActivityBackground = dynamic(
        light: UIColor(red: 0.91, green: 0.97, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.045, blue: 0.055, alpha: 1)
    )
    static let primaryText = dynamic(
        light: UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.965, alpha: 1)
    )
    static let secondaryText = dynamic(
        light: UIColor(red: 0.42, green: 0.45, blue: 0.49, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.65, blue: 0.69, alpha: 1)
    )
    static let green = dynamic(
        light: UIColor(red: 0.13, green: 0.82, blue: 0.28, alpha: 1),
        dark: UIColor(red: 0.20, green: 0.93, blue: 0.38, alpha: 1)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
