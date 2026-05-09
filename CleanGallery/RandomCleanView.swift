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
    @State private var isRecyclingSeen = false

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
                    VStack(spacing: 0) {
                        if isRecyclingSeen {
                            recyclingBanner
                        }
                        SwipeDeckView(
                            assets: assets,
                            stagedIds: $staged,
                            onFinished: { phase = .review }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
                let batch = gallery.nextRandomBatch(count: 10)
                assets = batch.assets
                isRecyclingSeen = batch.isRecyclingSeen
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

    /// Shown above the deck when Sweep had to top up the random batch with
    /// previously swiped items because the unseen pool is exhausted.
    private var recyclingBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accent)
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("You've seen everything")
                    .font(.subheadline.weight(.semibold))
                Text("Showing items you've already swiped before. Reset viewed photos in Settings to start fresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.accent.opacity(0.12))
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
            Haptics.deleteSucceeded()
            staged.removeAll()
            phase = .result
        } catch {
            Haptics.errorOccurred()
            errorMessage = error.localizedDescription
        }
    }
}
