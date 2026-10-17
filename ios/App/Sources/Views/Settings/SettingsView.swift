import SwiftUI
import UIKit
import MagpieKit

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editing: ProfileConfig?
    @State private var adding = false
    @State private var alertMessage: String?
    @State private var showLicense = false
    @State private var fingerprints: [UUID: String] = [:]
    private let intervals: [TimeInterval] = [10, 20, 30, 60]

    var body: some View {
        NavigationStack {
            List {
                if let error = appState.persistenceError {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section(String(localized: "服务器")) {
                    ForEach(appState.profiles) { profile in
                        HStack {
                            Button {
                                appState.select(profile.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                                        Text(profile.name).foregroundStyle(.primary)
                                        Text(profile.gatewayURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if appState.currentProfile?.id == profile.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                    }
                                }
                            }.buttonStyle(.plain)
                            if profile.isInsecure { InsecureBadge() }
                            Button {
                                editing = profile
                            } label: {
                                Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel(String(format: String(localized: "编辑%@"), locale: Locale.current, String(describing: profile.name)))
                        }
                    }.onDelete { offsets in
                        let ids = offsets.compactMap { appState.profiles.indices.contains($0) ? appState.profiles[$0].id : nil }
                        for id in ids { appState.deleteProfile(id) }
                    }
                    Button {
                        adding = true
                    } label: {
                        Label(String(localized: "添加服务器"), systemImage: "plus")
                    }
                }
                Section(String(localized: "显示与刷新")) {
                    Toggle(String(localized: "模拟数据模式"), isOn: Bindable(appState).isMockMode)
                    Text(String(localized: "开启后使用本地示例数据，不连接服务器或 SSH。页面会持续显示 Mock data 徽章。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let profile = appState.currentProfile {
                        Picker(String(localized: "刷新间隔"), selection: refreshBinding(profile)) {
                            ForEach(intervals, id: \.self) { Text(String(format: String(localized: "%@ 秒"), locale: Locale.current, String(describing: Int($0)))).tag($0) }
                        }
                    }
                }
                Section(String(localized: "SSH 主机指纹")) {
                    if appState.profiles.isEmpty { Text(String(localized: "添加服务器后可管理指纹。")).foregroundStyle(.secondary) }
                    ForEach(appState.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                Text(fingerprints[profile.id] ?? String(localized: "未记录指纹")).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(
                                    2)
                            }
                            Spacer()
                            Button(String(localized: "清除指纹"), role: .destructive) {
                                Task {
                                    do {
                                        try await appState.secretStore.delete(account: SecretField.hostKey.account(profileID: profile.id))
                                        fingerprints[profile.id] = nil
                                    } catch { alertMessage = ErrorMessages.chinese(for: error) }
                                }
                            }
                        }
                    }
                }
                Section(String(localized: "语言")) {
                    Text(String(localized: "可在 iOS 设置的 Magpie 页面选择应用语言。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "打开应用设置")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section(String(localized: "连接应用")) {
                    Button(String(localized: "打开 Tailscale")) { openApp(scheme: "tailscale://", label: "Tailscale") }
                    Button(String(localized: "打开 UU Remote")) { openApp(scheme: "uuremote://", label: "UU Remote") }
                }
                Section(String(localized: "关于")) {
                    LabeledContent(
                        String(localized: "版本"),
                        value:
                            """
                            \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")\
                             (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))
                            """
                    )
                    Button(String(localized: "开源许可")) { showLicense = true }
                }
            }
            .navigationTitle(String(localized: "设置"))
            .task { await loadFingerprints() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成")) { dismiss() } } }
            .sheet(isPresented: $adding) { ProfileEditView(initial: nil, onSave: persist) }
            .sheet(item: $editing) { profile in ProfileEditView(initial: profile, onSave: persist) }
            .sheet(isPresented: $showLicense) {
                NavigationStack {
                    List {
                        NavigationLink("magpie — MIT License") { LicenseTextView(resource: "LICENSE-magpie") }
                        NavigationLink("SwiftTerm — MIT License") { LicenseTextView(resource: "LICENSE-SwiftTerm") }
                        NavigationLink("Citadel — MIT License") { LicenseTextView(resource: "LICENSE-Citadel") }
                    }.navigationTitle(String(localized: "许可与致谢")).toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成")) { showLicense = false } }
                    }
                }
            }
            .alert(String(localized: "无法打开应用"), isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button(String(localized: "好"), role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }
    private func loadFingerprints() async {
        for profile in appState.profiles {
            do {
                fingerprints[profile.id] = try await appState.secretStore.get(account: SecretField.hostKey.account(profileID: profile.id))
            } catch { alertMessage = ErrorMessages.chinese(for: error) }
        }
    }
    private func refreshBinding(_ profile: ProfileConfig) -> Binding<TimeInterval> {
        Binding(
            get: { appState.currentProfile?.refreshInterval ?? 20 },
            set: {
                var updated = profile
                updated.refreshInterval = $0
                appState.saveProfile(updated)
            })
    }
    private func persist(_ profile: ProfileConfig, _ secrets: [SecretField: String]) {
        Task {
            do {
                for (field, value) in secrets {
                    try await appState.secretStore.set(value, account: field.account(profileID: profile.id))
                }
                appState.saveProfile(profile)
            } catch { alertMessage = ErrorMessages.chinese(for: error) }
        }
    }
    private func openApp(scheme: String, label: String) {
        guard let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) else {
            alertMessage = String(format: String(localized: "未检测到%@，请先安装后再试。"), locale: Locale.current, String(describing: label))
            return
        }
        openURL(url)
    }
}

private struct LicenseTextView: View {
    let resource: String
    private var text: String {
        guard
            let url = Bundle.main.url(forResource: resource, withExtension: "txt", subdirectory: "Licenses")
                ?? Bundle.main.url(forResource: resource, withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return String(localized: "无法读取许可文本。") }
        return contents
    }
    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.medium)
        }
        .navigationTitle(resource.replacingOccurrences(of: "LICENSE-", with: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
