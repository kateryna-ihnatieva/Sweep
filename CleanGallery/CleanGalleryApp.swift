import SwiftUI

@main
struct SweepApp: App {
    @StateObject private var gallery = GalleryViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(gallery)
                .preferredColorScheme(.dark)
        }
    }
}
