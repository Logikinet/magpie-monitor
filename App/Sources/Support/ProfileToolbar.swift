import SwiftUI

struct ProfileToolbar: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var showingSettings = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if appState.profiles.isEmpty { Text("尚无服务器配置") }
                    ForEach(appState.profiles) { profile in
                        Button { appState.select(profile.id) } label: {
                            if appState.currentProfile?.id == profile.id { Label(profile.name, systemImage: "checkmark") } else { Text(profile.name) }
                        }
                    }
                    Button { showingSettings = true } label: { Label("管理服务器…", systemImage: "gearshape") }
                } label: {
                    Label(appState.currentProfile?.name ?? "选择服务器", systemImage: "server.rack")
                        .lineLimit(1).frame(maxWidth: 170)
                }
                .accessibilityLabel("服务器：\(appState.currentProfile?.name ?? "未选择")")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("设置")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: DS.Spacing.small) {
                if appState.isMockMode { MockBadge() }
                if appState.currentProfile?.isInsecure == true { InsecureBadge() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.medium)
            .padding(.vertical, DS.Spacing.xSmall)
            .background(.bar)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

extension View { func profileToolbar() -> some View { modifier(ProfileToolbar()) } }
