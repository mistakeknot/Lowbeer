import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            RulesSettingsView()
                .tabItem {
                    Label("Rules", systemImage: "list.bullet.rectangle")
                }

            AllowlistView()
                .tabItem {
                    Label("Allowlist", systemImage: "shield")
                }
        }
        .frame(width: 480, height: 400)
    }
}
