import Photos
import SwiftUI

struct MonthCleanFlowView: View {
    let month: MonthBucket
    @EnvironmentObject private var gallery: GalleryViewModel
    @Environment(\.dismiss) private var dismiss

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
                SwipeDeckView(
                    assets: month.assets,
                    stagedIds: $staged,
                    onFinished: {
                        // Reaching the end of the deck means the user has seen every item this month.
                        // Mark it as reviewed automatically so the list can flag it as "done".
                        gallery.markMonthCompleted(month.id)
                        phase = .review
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationBarBackButtonHidden(false)

            case .review:
                StagedReviewView(
                    title: "Review before deletion",
                    allAssetsInScope: month.assets,
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
        .navigationTitle(month.title)
        .navigationBarTitleDisplayMode(.inline)
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
            monthCompletion: Binding(
                get: { gallery.completedMonthIds.contains(month.id) },
                set: { new in
                    if new { gallery.markMonthCompleted(month.id) }
                    else { gallery.markMonthIncomplete(month.id) }
                }
            ),
            doneButtonTitle: "Back to months",
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
