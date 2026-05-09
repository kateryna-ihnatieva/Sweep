import Photos
import SwiftUI

struct RandomCleanView: View {
    @EnvironmentObject private var gallery: GalleryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var phase: Phase = .swipe
    @State private var staged: Set<String> = []
    @State private var lastResult = DeletionCommitResult.empty
    @State private var errorMessage: String?

    private enum Phase {
        case swipe
        case review
        case result
    }

    var body: some View {
        Group {
            switch phase {
            case .swipe:
                if assets.isEmpty {
                    ContentUnavailableView(
                        "No items",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Add photos or videos to your library and check access permissions.")
                    )
                    .foregroundStyle(AppTheme.textSecondary)
                } else {
                    SwipeDeckView(
                        assets: assets,
                        stagedIds: $staged,
                        onFinished: { phase = .review }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .review:
                StagedReviewView(
                    title: "Random picks — review",
                    allAssetsInScope: assets,
                    stagedIds: $staged,
                    onConfirmDelete: { Task { await performDelete() } },
                    onExitWithoutDeleting: { dismiss() }
                )

            case .result:
                resultScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(phase == .swipe ? AppTheme.backgroundFlat : AppTheme.background)
        .navigationTitle("Random 10")
        .navigationBarTitleDisplayMode(.inline)
        // While swiping cards, a slight downward drag would otherwise dismiss the sheet and lose progress.
        .interactiveDismissDisabled(phase == .swipe && !assets.isEmpty)
        .onAppear {
            if assets.isEmpty {
                assets = gallery.randomSample(count: 10)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var resultScreen: some View {
        DeletionSummaryView(
            result: lastResult,
            monthCompletion: nil,
            doneButtonTitle: "Close",
            onDone: { dismiss() }
        )
    }

    @MainActor
    private func performDelete() async {
        let ids = Array(staged)
        guard !ids.isEmpty else {
            lastResult = .empty
            phase = .result
            return
        }
        do {
            lastResult = try await gallery.commitDeletion(for: ids)
            staged.removeAll()
            phase = .result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
