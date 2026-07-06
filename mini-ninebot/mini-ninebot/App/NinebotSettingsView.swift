import SwiftUI
import UIKit

struct NinebotSettingsView: View {
    @ObservedObject var model: NinebotViewModel
    @Environment(\.openURL) private var openURL
    @State private var loginMode: LoginMode = .password
    @State private var isEditingProxy = false
    @State private var isBindingAccount = false

    var body: some View {
        Form {
            Section {
                SettingsOverviewCard(
                    hasConfiguration: model.hasConfiguration,
                    vehicleCount: model.dashboard.vehicles.count,
                    baseURLString: model.baseURLString,
                    accountCount: model.loginAccountCount
                )
            }

            if model.errorMessage != nil || model.statusMessage != nil {
                Section {
                    SettingsStatusBanner(
                        errorMessage: model.errorMessage,
                        statusMessage: model.statusMessage
                    )
                }
            }

            Section("当前代理") {
                ProxySummaryRow(
                    hasConfiguration: model.hasConfiguration,
                    baseURLString: model.baseURLString
                )

                if isEditingProxy {
                    TextField("http://127.0.0.1:18009", text: $model.baseURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Bearer Token", text: $model.bearerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 12) {
                        Button {
                            isEditingProxy = false
                        } label: {
                            SettingsButtonLabel(title: "取消", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            saveProxy()
                        } label: {
                            SettingsButtonLabel(title: "保存", systemImage: "tray.and.arrow.down.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasText(model.baseURLString))

                        Button {
                            Task { await model.testConnection() }
                        } label: {
                            SettingsButtonLabel(title: "测试", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasText(model.baseURLString))
                    }
                } else {
                    Button {
                        isEditingProxy = true
                    } label: {
                        SettingsButtonLabel(
                            title: model.hasConfiguration ? "修改代理" : "连接代理",
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("登录账号") {
                AccountSummaryRow(
                    accountText: model.currentAccountDisplay,
                    loginResult: model.loginResult,
                    hasAccount: model.hasLoginAccount
                )
                Text("当前代理是单账号会话，切换登录会替换当前账号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isBindingAccount {
                    TextField("手机号", text: $model.account)
                        .keyboardType(.phonePad)
                        .textContentType(.username)

                    Picker("方式", selection: $loginMode) {
                        ForEach(LoginMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if loginMode == .password {
                        SecureField("密码", text: $model.password)
                            .textContentType(.password)

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
                        TextField("验证码", text: $model.smsCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)

                        HStack(spacing: 12) {
                            Button {
                                Task { await model.sendSMSCode() }
                            } label: {
                                SettingsButtonLabel(title: "发送验证码", systemImage: "message.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasText(model.account))

                            Spacer()

                            Button {
                                Task {
                                    await model.consumeSMSCode()
                                    if model.errorMessage == nil, model.hasLoginAccount {
                                        isBindingAccount = false
                                    }
                                }
                            } label: {
                                SettingsButtonLabel(title: "验证登录", systemImage: "checkmark.seal.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasText(model.account) || !hasText(model.smsCode))
                        }
                    }

                    Button {
                        isBindingAccount = false
                        model.password = ""
                        model.smsCode = ""
                    } label: {
                        SettingsButtonLabel(title: "取消", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        isBindingAccount = true
                    } label: {
                        SettingsButtonLabel(
                            title: model.hasLoginAccount ? "切换登录账号" : "登录账号",
                            systemImage: model.hasLoginAccount ? "person.crop.circle.badge.plus" : "person.badge.key.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("账号维护") {
                Button {
                    Task { await model.refreshLoginToken() }
                } label: {
                    SettingsButtonLabel(title: "刷新登录状态", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!model.hasConfiguration)

                Button(role: .destructive) {
                    model.clearMessages()
                } label: {
                    SettingsButtonLabel(title: "清除当前提示", systemImage: "xmark.circle")
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

    private func saveProxy() {
        model.saveConfiguration()
        if model.hasConfiguration {
            isEditingProxy = false
        }
    }
}

private struct SettingsOverviewCard: View {
    var hasConfiguration: Bool
    var vehicleCount: Int
    var baseURLString: String
    var accountCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                    Image(systemName: hasConfiguration ? "checkmark.seal.fill" : "link.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("当前代理")
                        .font(.headline)
                    Text(hasConfiguration ? cleanBaseURL : "填写代理地址后即可登录和刷新车况")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                SettingsInfoPill(title: "车辆", value: "\(vehicleCount)", systemImage: "bolt.car.fill")
                SettingsInfoPill(title: "账号", value: "\(accountCount)", systemImage: "person.fill")
                SettingsInfoPill(title: "快捷指令", value: "5 个", systemImage: "sparkles")
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        hasConfiguration ? .green : .orange
    }

    private var cleanBaseURL: String {
        let value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "代理地址为空" : value
    }
}

private struct ProxySummaryRow: View {
    var hasConfiguration: Bool
    var baseURLString: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasConfiguration ? "link.circle.fill" : "link.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(hasConfiguration ? Color.green : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasConfiguration ? "代理已连接" : "未配置代理")
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
        return value.isEmpty ? "未填写代理地址" : value
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

struct NinebotSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NinebotSettingsView(model: NinebotViewModel())
                .navigationTitle("我的")
        }
    }
}
