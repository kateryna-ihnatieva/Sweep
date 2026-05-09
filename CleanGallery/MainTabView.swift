import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            MonthListView()
                .tabItem {
                    Label("Clean", systemImage: "square.stack.3d.down.right")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }
        }
        .tint(AppTheme.accent)
    }
}
