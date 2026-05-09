import Photos
import SwiftUI

// MARK: - Library entry (lives inside MonthListView's List section)

struct DuplicatesEntryRow: View {
    @ObservedObject var viewModel: DuplicateFinderViewModel
    var onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "square.on.square")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.accent)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicates")
                        .font(.body.weight(.semibold))
                    if viewModel.hasResults {
                        Text(summaryLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Find byte-identical photos and videos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if viewModel.isScanning {
                ProgressView(value: viewModel.progress)
                    .tint(AppTheme.accent)
            }

            HStack(spacing: 8) {
                if viewModel.hasResults {
                    Button(action: onBrowse) {
                        Label("Browse sets", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        Task { await viewModel.scanLibrary() }
                    } label: {
                        Label("Scan again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        Task { await viewModel.scanLibrary() }
                    } label: {
                        Label("Scan library", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .disabled(viewModel.isScanning)
        }
        .padding(.vertical, 4)
    }

    private var summaryLine: String {
        let sets = viewModel.photoGroups.count + viewModel.videoGroups.count
        let items = viewModel.totalDuplicateItems
        let extras = viewModel.totalExtraCopies
        return "\(sets) sets · \(items) items (\(extras) extra)"
    }
}

// MARK: - Sheet: list of groups

struct DuplicatesSheetView: View {
    @EnvironmentObject private var gallery: GalleryViewModel
    @EnvironmentObject private var dup: DuplicateFinderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Duplicates")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await dup.scanLibrary() }
                        } label: {
                            Label("Scan again", systemImage: "arrow.clockwise")
                        }
                        .disabled(dup.isScanning)
                    }
                }
                .navigationDestination(for: String.self) { id in
                    if let group = dup.group(id: id) {
                        DuplicateGroupCleanFlowView(group: group)
                            .environmentObject(gallery)
                    } else {
                        ContentUnavailableView("Unavailable", systemImage: "exclamationmark.triangle")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !dup.hasResults && dup.isScanning {
            VStack(spacing: 14) {
                ProgressView(value: dup.progress)
                    .tint(AppTheme.accent)
                    .frame(maxWidth: 280)
                Text("Scanning library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
        } else if !dup.hasResults {
            ContentUnavailableView(
                "No scan yet",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Tap Scan again in the top-right corner to look for duplicates.")
            )
        } else {
            duplicatesList
                .overlay(alignment: .bottom) {
                    if dup.isScanning {
                        HStack(spacing: 10) {
                            ProgressView(value: dup.progress)
                                .frame(maxWidth: 160)
                            Text("Updating…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                    }
                }
        }
    }

    private var duplicatesList: some View {
        List {
            if !dup.photoGroups.isEmpty {
                Section {
                    ForEach(dup.photoGroups) { group in
                        duplicateRow(group)
                    }
                } header: {
                    Text(DuplicateKind.photoVisual.listSectionTitle)
                } footer: {
                    Text(DuplicateKind.photoVisual.footnote)
                }
            }

            if !dup.videoGroups.isEmpty {
                Section {
                    ForEach(dup.videoGroups) { group in
                        duplicateRow(group)
                    }
                } header: {
                    Text(DuplicateKind.videoHeuristic.listSectionTitle)
                } footer: {
                    Text(DuplicateKind.videoHeuristic.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func duplicateRow(_ group: DuplicateGroup) -> some View {
        Button {
            path.append(group.id)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    if let first = group.assets.first {
                        AssetThumbnailView(asset: first, targetSide: 56)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if group.count > 1 {
                        Text("+\(group.extraCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.danger, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.count) items")
                        .font(.body.weight(.semibold))
                    Text(kindSubtitle(group.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let d = group.assets.first?.creationDate {
                        Text(d, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
    }

    private func kindSubtitle(_ kind: DuplicateKind) -> String {
        switch kind {
        case .photoVisual: return "Byte-identical photo"
        case .videoHeuristic: return "Byte-identical video"
        }
    }
}

// MARK: - Clean one duplicate set (reuse swipe + review)

struct DuplicateGroupCleanFlowView: View {
    let group: DuplicateGroup
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
                    assets: group.assets,
                    stagedIds: $staged,
                    onFinished: { phase = .review }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .review:
                StagedReviewView(
                    title: "Review removals",
                    allAssetsInScope: group.assets,
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
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(phase == .swipe)
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var navTitle: String {
        switch group.kind {
        case .photoVisual: return "Identical photos"
        case .videoHeuristic: return "Identical videos"
        }
    }

    private var resultScreen: some View {
        DeletionSummaryView(
            result: lastResult,
            monthCompletion: nil,
            doneButtonTitle: "Back to duplicate sets",
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
