import SwiftUI
import UIKit

struct NinebotSettingsView: View {
    @ObservedObject var model: NinebotViewModel
    @Environment(\.openURL) private var openURL
    @State private var loginMode: LoginMode = .password
    @State private var isShowingConnectionSettings = false
    @State private var isBindingAccount = false

    var body: some View {
        Form {
            Section {
                SettingsProfileCard(
                    snapshot: model.dashboard.primaryVehicle,
                    accountText: model.currentAccountDisplay,
                    dataSourceMode: model.dataSourceMode,
                    vehicleCount: model.dashboard.vehicles.count
                )
            }

            Section {
                NavigationLink {
                    NinebotDiagnosticsView(model: model)
                } label: {
                    SettingsNavigationRow(
                        title: "诊断中心",
                        subtitle: "刷新、缓存、Widget 和原始字段",
                        systemImage: "stethoscope"
                    )
                }
            }

            if model.errorMessage != nil || model.statusMessage != nil {
                Section {
                    SettingsStatusBanner(
                        errorMessage: model.errorMessage,
                        statusMessage: model.statusMessage
                    )
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isShowingConnectionSettings) {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        Toggle(isOn: proxyModeBinding) {
                            SettingsNavigationRow(
                                title: "代理模式",
                                subtitle: model.dataSourceMode == .proxy ? "当前使用 ninecli 代理" : "默认使用 NinePlus 服务器",
                                systemImage: "server.rack",
                                tint: model.dataSourceMode == .proxy ? .orange : .green
                            )
                        }
                        .tint(.orange)

                        SettingsInputField(
                            title: "\(model.dataSourceMode.shortTitle)地址",
                            placeholder: model.dataSourceMode.endpointPlaceholder,
                            systemImage: model.dataSourceMode.systemImage,
                            text: $model.baseURLString,
                            keyboardType: .URL,
                            textContentType: .URL
                        )

                        SettingsInputField(
                            title: "访问 Token",
                            placeholder: model.dataSourceMode.tokenPlaceholder,
                            systemImage: "key.horizontal.fill",
                            text: $model.bearerToken,
                            isSecure: true
                        )

                        HStack(spacing: 10) {
                            Button {
                                isShowingConnectionSettings = false
                            } label: {
                                SettingsCompactButtonLabel(title: "收起", systemImage: "chevron.up")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await model.testConnection() }
                            } label: {
                                SettingsCompactButtonLabel(title: "测试", systemImage: "network")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasText(model.baseURLString))

                            Button {
                                saveConnection()
                            } label: {
                                SettingsCompactButtonLabel(title: "保存", systemImage: "tray.and.arrow.down.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasText(model.baseURLString))
                        }
                        .font(.subheadline.weight(.semibold))

                        Text(model.dataSourceMode == .platform ? "服务器模式下，多账号、APNs 和轮询策略在 NinePlus Platform 后台管理。" : "代理模式是单账号直连，适合调试；不会使用服务器轮询和通知能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        PushDeviceTokenRow(token: model.pushDeviceToken, hasConfiguration: model.hasConfiguration)

                        Button {
                            Task { await model.enableChargingNotifications() }
                        } label: {
                            SettingsButtonLabel(title: "检查权限并上报", systemImage: "bell.badge.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.dataSourceMode != .platform || !model.hasConfiguration)

                        Button {
                            Task { await model.syncPushDeviceToken() }
                        } label: {
                            SettingsButtonLabel(title: "重新上报设备", systemImage: "arrow.up.doc.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.dataSourceMode != .platform || !model.hasConfiguration)
                    }
                    .padding(.top, 8)
                } label: {
                    SettingsNavigationRow(
                        title: "连接与通知",
                        subtitle: connectionSummaryText,
                        systemImage: model.dataSourceMode.systemImage,
                        tint: model.hasConfiguration ? .green : .orange
                    )
                }
            }

            if model.dataSourceMode == .proxy {
                Section("代理账号登录") {
                    DisclosureGroup(isExpanded: $isBindingAccount) {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()

                            Text("当前代理是单账号会话，切换登录会替换当前账号。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            SettingsInputField(
                                title: "手机号",
                                placeholder: "九号账号手机号",
                                systemImage: "phone.fill",
                                text: $model.account,
                                keyboardType: .phonePad,
                                textContentType: .username
                            )

                            Picker("方式", selection: $loginMode) {
                                ForEach(LoginMode.allCases) { mode in
                                    Label(mode.title, systemImage: mode.systemImage)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if loginMode == .password {
                                SettingsInputField(
                                    title: "密码",
                                    placeholder: "九号账号密码",
                                    systemImage: "lock.fill",
                                    text: $model.password,
                                    isSecure: true,
                                    textContentType: .password
                                )

                                Button {
                                    Task {
                                        await model.loginWithPassword()
                                        if model.errorMessage == nil, model.hasLoginAccount {
                                            isBindingAccount = false
                                        }
                                    }
                                } label: {
                                    SettingsButtonLabel(title: "密码登录", systemImage: "key.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!hasText(model.account) || model.password.isEmpty)
                            } else {
                                SettingsInputField(
                                    title: "验证码",
                                    placeholder: "短信验证码",
                                    systemImage: "number.square.fill",
                                    text: $model.smsCode,
                                    keyboardType: .numberPad,
                                    textContentType: .oneTimeCode
                                )

                                HStack(spacing: 10) {
                                    Button {
                                        Task { await model.sendSMSCode() }
                                    } label: {
                                        SettingsCompactButtonLabel(title: "发送验证码", systemImage: "message.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!hasText(model.account))

                                    Button {
                                        Task {
                                            await model.consumeSMSCode()
                                            if model.errorMessage == nil, model.hasLoginAccount {
                                                isBindingAccount = false
                                            }
                                        }
                                    } label: {
                                        SettingsCompactButtonLabel(title: "验证登录", systemImage: "checkmark.seal.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!hasText(model.account) || !hasText(model.smsCode))
                                }
                            }

                            HStack(spacing: 10) {
                                Button {
                                    Task { await model.refreshLoginToken() }
                                } label: {
                                    SettingsCompactButtonLabel(title: "刷新状态", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.hasConfiguration)

                                Button {
                                    isBindingAccount = false
                                    model.password = ""
                                    model.smsCode = ""
                                } label: {
                                    SettingsCompactButtonLabel(title: "收起", systemImage: "chevron.up")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 8)
                    } label: {
                        AccountSummaryRow(
                            accountText: model.currentAccountDisplay,
                            loginResult: model.loginResult,
                            hasAccount: model.hasLoginAccount
                        )
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    model.clearMessages()
                } label: {
                    SettingsNavigationRow(
                        title: "清除当前提示",
                        subtitle: "移除页面上的状态或错误提示",
                        systemImage: "xmark.circle",
                        tint: .red
                    )
                }
            }

            Section("Siri 与快捷指令") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    SettingsButtonLabel(title: "打开 Siri 设置", systemImage: "mic.circle.fill")
                }

                ShortcutCapabilityRow(title: "刷新车况", systemImage: "arrow.clockwise")
                ShortcutCapabilityRow(title: "查询电量", systemImage: "battery.100")
                ShortcutCapabilityRow(title: "查询位置", systemImage: "location.fill")
                ShortcutCapabilityRow(title: "寻车铃", systemImage: "bell.fill")
                ShortcutCapabilityRow(title: "打开座桶", systemImage: "shippingbox.fill")
                ShortcutCapabilityRow(title: "上电", systemImage: "power.circle.fill")
                ShortcutCapabilityRow(title: "熄火", systemImage: "lock.fill")
            }
        }
        .disabled(model.isLoading)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.isLoading {
                    ProgressView()
                }
            }
        }
    }

    private func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var connectionSummaryText: String {
        if model.hasConfiguration {
            return "\(model.dataSourceMode.shortTitle)已配置 · \(model.pushDeviceToken == nil ? "APNs 未上报" : "APNs 已就绪")"
        }
        return "配置服务器、代理模式和通知上报"
    }

    private var proxyModeBinding: Binding<Bool> {
        Binding(
            get: { model.dataSourceMode == .proxy },
            set: { isProxyEnabled in
                model.dataSourceMode = isProxyEnabled ? .proxy : .platform
                model.saveDataSourceMode()
                if !isProxyEnabled {
                    isBindingAccount = false
                    Task { await model.syncPushDeviceTokenIfPossible() }
                }
            }
        )
    }

    private func saveConnection() {
        model.saveConfiguration()
        if model.hasConfiguration {
            isShowingConnectionSettings = false
            if model.dataSourceMode == .platform {
                Task { await model.syncPushDeviceTokenIfPossible() }
            }
        }
    }
}

private struct SettingsProfileCard: View {
    var snapshot: NinebotVehicleSnapshot?
    var accountText: String
    var dataSourceMode: NinebotDataSourceMode
    var vehicleCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatar(urlString: avatarURLString, displayName: displayName)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(vehicleCount)")
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(Capsule())
                .accessibilityLabel("车辆 \(vehicleCount) 台")
        }
        .padding(.vertical, 6)
    }

    private var displayName: String {
        firstRawString([
            "owner_user_nickname",
            "ownerUserNickname",
            "auth_nickname",
            "authNickname",
            "nickname",
            "user_name",
            "userName"
        ]) ?? cleanAccountText
    }

    private var subtitle: String {
        let vehicleName = snapshot?.vehicle.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !vehicleName.isEmpty {
            return "\(dataSourceMode.shortTitle) · \(vehicleName)"
        }
        return dataSourceMode.title
    }

    private var avatarURLString: String? {
        firstRawString([
            "owner_user_avatar",
            "ownerUserAvatar",
            "auth_avatar",
            "authAvatar",
            "avatar",
            "avatar_url",
            "avatarUrl"
        ])
    }

    private var cleanAccountText: String {
        let value = accountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "NineBot+" : value
    }

    private func firstRawString(_ keys: [String]) -> String? {
        guard let raw = snapshot?.vehicle.raw else { return nil }
        for key in keys {
            if let value = raw[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct ProfileAvatar: View {
    var urlString: String?
    var displayName: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemGroupedBackground))

            if let urlString,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Text(initialText)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var initialText: String {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = value.first else { return "N" }
        return String(first)
    }
}

private struct SettingsOverviewCard: View {
    var hasConfiguration: Bool
    var dataSourceMode: NinebotDataSourceMode
    var vehicleCount: Int
    var baseURLString: String
    var accountCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                    Image(systemName: hasConfiguration ? dataSourceMode.systemImage : "link.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dataSourceMode.title)
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                SettingsInfoPill(title: "车辆", value: "\(vehicleCount)", systemImage: "bolt.car.fill")
                SettingsInfoPill(title: dataSourceMode == .platform ? "归档" : "账号", value: dataSourceMode == .platform ? "开启" : "\(accountCount)", systemImage: dataSourceMode == .platform ? "externaldrive.fill" : "person.fill")
                SettingsInfoPill(title: "快捷指令", value: "7 个", systemImage: "sparkles")
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        return hasConfiguration ? .green : .orange
    }

    private var summaryText: String {
        hasConfiguration ? cleanBaseURL : (dataSourceMode == .platform ? "填写 NinePlus Platform 地址后读取服务器数据" : "填写 ninecli serve 地址后直接读取代理")
    }

    private var cleanBaseURL: String {
        let value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "\(dataSourceMode.shortTitle)地址为空" : value
    }
}

private struct ProxySummaryRow: View {
    var hasConfiguration: Bool
    var dataSourceMode: NinebotDataSourceMode
    var baseURLString: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasConfiguration ? dataSourceMode.systemImage : "link.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(hasConfiguration ? Color.green : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasConfiguration ? "\(dataSourceMode.shortTitle)已配置" : "未配置\(dataSourceMode.shortTitle)")
                    .font(.subheadline.weight(.semibold))
                Text(cleanBaseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(hasConfiguration ? "可用" : "待连接")
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasConfiguration ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((hasConfiguration ? Color.green : Color.orange).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var cleanBaseURL: String {
        let value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未填写\(dataSourceMode.shortTitle)地址" : value
    }
}

private struct SettingsInputField: View {
    var title: String
    var placeholder: String
    var systemImage: String
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                    }
                }
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
        }
    }
}

private struct PushDeviceTokenRow: View {
    var token: String?
    var hasConfiguration: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: token == nil ? "bell.slash.fill" : "bell.badge.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(token == nil ? Color.orange : Color.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(token == nil ? "APNs 设备未上报" : "APNs 设备已就绪")
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
    }

    private var detailText: String {
        guard let token, !token.isEmpty else {
            return hasConfiguration ? "点“检查权限并上报”，会重新注册 APNs 并同步到服务器后台。" : "先保存 NinePlus 服务器地址和 Token。"
        }
        let prefix = token.prefix(8)
        let suffix = token.suffix(6)
        return "Token \(prefix)...\(suffix)"
    }
}

private struct SettingsNavigationRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color = .green

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct NinebotDiagnosticsView: View {
    @ObservedObject var model: NinebotViewModel
    @State private var copiedMessage: String?

    private var diagnostics: NinebotDiagnosticsSnapshot {
        model.diagnosticsSnapshot()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DiagnosticsHeroCard(diagnostics: diagnostics)

                DiagnosticsEventCard(title: "App / 快捷指令", event: diagnostics.lastAppRefreshEvent)
                DiagnosticsEventCard(title: "桌面小组件", event: diagnostics.lastWidgetRefreshEvent)

                DiagnosticsCacheCard(diagnostics: diagnostics)

                DiagnosticsRawCopyCard(
                    snapshot: model.dashboard.primaryVehicle,
                    copiedMessage: $copiedMessage
                )
            }
            .padding(16)
        }
        .background(Color.teslaPageBackground.ignoresSafeArea())
        .navigationTitle("诊断中心")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let copiedMessage {
                Text(copiedMessage)
                    .font(.footnote.weight(.semibold))
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
}

private struct DiagnosticsHeroCard: View {
    var diagnostics: NinebotDiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill((diagnostics.hasConfiguration ? Color.green : Color.orange).opacity(0.14))
                    Image(systemName: diagnostics.hasConfiguration ? "checkmark.seal.fill" : "link.badge.plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(diagnostics.hasConfiguration ? Color.green : Color.orange)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnostics.selectedVehicleName)
                        .font(.headline)
                        .foregroundStyle(Color.teslaPrimaryText)
                        .lineLimit(1)
                    Text(diagnostics.proxyText)
                        .font(.caption)
                        .foregroundStyle(Color.teslaSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(diagnostics.vehicleCount)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.teslaPrimaryText)
                    Text("车辆")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                }
            }

            HStack(spacing: 10) {
                DiagnosticMetricPill(title: "账号", value: diagnostics.accountText == "未绑定账号" ? "0" : "1", systemImage: "person.fill")
                DiagnosticMetricPill(title: "地址", value: "\(diagnostics.resolvedAddressCount)", systemImage: "map.fill")
                DiagnosticMetricPill(title: "详情", value: "\(diagnostics.rideDetailCount)", systemImage: "doc.text.magnifyingglass")
            }

            if let updatedAt = diagnostics.dashboardUpdatedAt {
                Label("车况更新 \(formatDiagnosticsDate(updatedAt))", systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.teslaSecondaryText)
            }

            if let lastError = diagnostics.lastError, !lastError.isEmpty {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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

private struct DiagnosticsEventCard: View {
    var title: String
    var event: NinebotRefreshEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.teslaPrimaryText)
                Spacer()
                Text(event?.success == true ? "成功" : "待检查")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event?.success == true ? Color.green : Color.orange)
            }

            if let event {
                HStack(spacing: 10) {
                    DiagnosticMetricPill(title: "来源", value: event.source, systemImage: "bolt.horizontal")
                    DiagnosticMetricPill(title: "耗时", value: formatDiagnosticsDuration(event.durationSeconds), systemImage: "timer")
                    DiagnosticMetricPill(title: "时间", value: formatDiagnosticsTime(event.endedAt), systemImage: "clock")
                }

                if let message = event.message, !message.isEmpty {
                    Text("\(event.operation) · \(message)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.teslaSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("还没有记录到刷新事件")
                    .font(.subheadline)
                    .foregroundStyle(Color.teslaSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct DiagnosticsCacheCard: View {
    var diagnostics: NinebotDiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地缓存")
                .font(.headline)
                .foregroundStyle(Color.teslaPrimaryText)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                DiagnosticMetricPill(title: "接口行程", value: "\(diagnostics.interfaceRideCount)", systemImage: "road.lanes")
                DiagnosticMetricPill(title: "历史快照", value: "\(diagnostics.historyPointCount)", systemImage: "clock.arrow.circlepath")
                DiagnosticMetricPill(title: "本地轨迹", value: "\(diagnostics.recordedRideCount)", systemImage: "point.3.connected.trianglepath.dotted")
                DiagnosticMetricPill(title: "车况缓存", value: formatDiagnosticsBytes(diagnostics.dashboardCacheBytes), systemImage: "externaldrive.fill")
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

private struct DiagnosticsRawCopyCard: View {
    var snapshot: NinebotVehicleSnapshot?
    @Binding var copiedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("原始字段")
                    .font(.headline)
                    .foregroundStyle(Color.teslaPrimaryText)
                Spacer()
                Text(snapshot == nil ? "无车辆" : "可复制")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot == nil ? Color.orange : Color.green)
            }

            Text("复制当前车辆、状态、电池和行程返回值，方便排查字段。")
                .font(.caption)
                .foregroundStyle(Color.teslaSecondaryText)

            Button {
                copyRawPayload()
            } label: {
                Label("复制全部原始字段", systemImage: "doc.on.doc.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.green)
            .disabled(snapshot == nil)
        }
        .padding(16)
        .background(Color.teslaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.teslaHairline, lineWidth: 1)
        }
    }

    private func copyRawPayload() {
        guard let snapshot else { return }
        let payload: [String: JSONValue] = [
            "vehicle": .object(snapshot.vehicle.raw ?? [:]),
            "status": .object(snapshot.state.rawStatus ?? [:]),
            "battery": .object(snapshot.state.rawBattery ?? [:]),
            "travel": .object(snapshot.state.rawTravel ?? [:])
        ]
        let text = diagnosticsJSONString(.object(payload))
        UIPasteboard.general.string = text
        copiedMessage = "已复制原始字段"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            copiedMessage = nil
        }
    }
}

private struct DiagnosticMetricPill: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.teslaSecondaryText)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.teslaPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.teslaSecondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teslaControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AccountSummaryRow: View {
    var accountText: String
    var loginResult: NinebotLoginResult?
    var hasAccount: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasAccount ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(hasAccount ? Color.green : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasAccount ? "当前账号" : "未登录账号")
                    .font(.subheadline.weight(.semibold))
                Text(accountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
    }

    private var detailText: String? {
        let areaCode = loginResult?.areaCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let region = loginResult?.region?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let businessUID = loginResult?.businessUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = [areaCode.isEmpty ? nil : "+\(areaCode)", region.isEmpty ? nil : region, businessUID.isEmpty ? nil : "UID \(businessUID)"]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct SettingsInfoPill: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsButtonLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 18)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SettingsCompactButtonLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private enum LoginMode: String, CaseIterable, Identifiable {
    case password
    case sms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: return "密码"
        case .sms: return "短信"
        }
    }

    var systemImage: String {
        switch self {
        case .password: return "key.fill"
        case .sms: return "message.fill"
        }
    }
}

private struct ShortcutCapabilityRow: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text("已支持")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
    }
}

private struct SettingsStatusBanner: View {
    var errorMessage: String?
    var statusMessage: String?

    var body: some View {
        if let errorMessage {
            SettingsStatusRow(
                message: errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            )
        } else if let statusMessage {
            SettingsStatusRow(
                message: statusMessage,
                systemImage: "checkmark.circle.fill",
                color: .green
            )
        }
    }
}

private struct SettingsStatusRow: View {
    var message: String
    var systemImage: String
    var color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private func formatDiagnosticsDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}

private func formatDiagnosticsTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func formatDiagnosticsDuration(_ seconds: Double) -> String {
    if seconds >= 10 {
        return "\(Int(seconds.rounded()))s"
    }
    return String(format: "%.1fs", seconds)
}

private func formatDiagnosticsBytes(_ bytes: Int) -> String {
    guard bytes > 0 else { return "0 B" }
    if bytes >= 1024 * 1024 {
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
    if bytes >= 1024 {
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }
    return "\(bytes) B"
}

private func diagnosticsJSONString(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

struct NinebotSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NinebotSettingsView(model: NinebotViewModel())
                .navigationTitle("我的")
        }
    }
}
