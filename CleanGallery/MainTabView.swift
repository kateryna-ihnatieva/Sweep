import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            MonthListView()
                .tabItem {
                    Label("Library", systemImage: "photo.on.rectangle.angled")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
