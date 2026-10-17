import SwiftUI

struct ProfileToolbar: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var showingSettings = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if appState.profiles.isEmpty { Text(String(localized: "尚无服务器配置")) }
                    ForEach(appState.profiles) { profile in
                        Button {
                            appState.select(profile.id)
                        } label: {
                            if appState.currentProfile?.id == profile.id {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Label(String(localized: "管理服务器…"), systemImage: "gearshape")
                    }
                } label: {
                    Label(appState.currentProfile?.name ?? String(localized: "选择服务器"), systemImage: "server.rack")
                        .lineLimit(1).frame(maxWidth: 170)
                }
                .accessibilityLabel(String(format: String(localized: "服务器：%@"), locale: Locale.current, String(describing: appState.currentProfile?.name ?? "未选择")))
            }
            ToolbarItem(placement: .topBarTrailing) {
                VStack(alignment: .trailing, spacing: DS.Spacing.xSmall) {
                    if appState.isMockMode { MockBadge().labelStyle(.titleAndIcon) }
                    if appState.currentProfile?.isInsecure == true { InsecureBadge().labelStyle(.titleAndIcon) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(String(localized: "设置"))
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

extension View { func profileToolbar() -> some View { modifier(ProfileToolbar()) } }
