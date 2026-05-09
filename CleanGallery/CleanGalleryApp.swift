import SwiftUI

@main
struct SweepApp: App {
    @StateObject private var gallery = GalleryViewModel()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(gallery)
                .environmentObject(settings)
                .tint(settings.accentColor)
                .task { Haptics.prepare() }
        }
    }
}
