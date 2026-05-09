import Photos
import SwiftUI

// MARK: - Library entry (top of month list)

struct DuplicatesEntryCard: View {
    @ObservedObject var viewModel: DuplicateFinderViewModel
    var onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.on.square")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicates")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Find identical-looking photos and videos with matching size, length, and resolution.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if viewModel.isScanning {
                ProgressView(value: viewModel.progress) {
                    Text("Scanning library…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .tint(AppTheme.accent)
            }

            if viewModel.hasResults, !viewModel.isScanning {
                Text(summaryLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Button(action: onBrowse) {
                    Text("Browse duplicate sets")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Group {
                if viewModel.hasResults {
                    Button {
                        Task { await viewModel.scanLibrary() }
                    } label: {
                        Text("Scan again")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                } else {
                    Button {
                        Task { await viewModel.scanLibrary() }
                    } label: {
                        Text("Scan library")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .disabled(viewModel.isScanning)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                .fill(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
        )
    }

    private var summaryLine: String {
        let sets = viewModel.photoGroups.count + viewModel.videoGroups.count
        let items = viewModel.totalDuplicateItems
        let extras = viewModel.totalExtraCopies
        return "\(sets) sets · \(items) items (\(extras) extra copies)"
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
            Group {
                if !dup.hasResults && dup.isScanning {
                    VStack(spacing: 16) {
                        ProgressView(value: dup.progress) {
                            Text("Scanning…")
                        }
                        .tint(AppTheme.accent)
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
                } else if !dup.hasResults {
                    ContentUnavailableView(
                        "No scan yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Run a scan from the library screen, or tap Scan again above.")
                    )
                    .background(AppTheme.background)
                } else {
                    duplicatesList
                        .overlay {
                            if dup.isScanning {
                                ZStack {
                                    Color.black.opacity(0.35)
                                        .ignoresSafeArea()
                                    ProgressView(value: dup.progress) {
                                        Text("Updating…")
                                    }
                                    .tint(AppTheme.accent)
                                    .padding(24)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                }
            }
            .navigationTitle("Duplicate sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan again") {
                        Task { await dup.scanLibrary() }
                    }
                    .buttonStyle(.plain)
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
        .background(AppTheme.background)
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
                        .font(.caption2)
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
                        .font(.caption2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }

    private func duplicateRow(_ group: DuplicateGroup) -> some View {
        Button {
            path.append(group.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
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
                            .padding(.vertical, 3)
                            .background(AppTheme.danger.opacity(0.92), in: Capsule())
                            .offset(x: 22, y: -22)
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.count) items")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(kindSubtitle(group.kind))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let d = group.assets.first?.creationDate {
                        Text(d, style: .date)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func kindSubtitle(_ kind: DuplicateKind) -> String {
        switch kind {
        case .photoVisual: return "Identical preview fingerprint"
        case .videoHeuristic: return "Same size, length, and resolution"
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
        .background(AppTheme.background)
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
        case .photoVisual: return "Photo duplicates"
        case .videoHeuristic: return "Video look-alikes"
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
            staged.removeAll()
            phase = .result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
