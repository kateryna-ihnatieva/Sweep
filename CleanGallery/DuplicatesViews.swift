import Photos
import SwiftUI

// MARK: - Library entry (lives inside MonthListView's List section)

/// Hero-style promo card for the duplicate finder. Sits as the top section of the
/// Library list and reads as a single editorial unit (icon, title, description, CTA),
/// not a toolbar of buttons crammed into a list row.
struct DuplicatesEntryRow: View {
    @ObservedObject var viewModel: DuplicateFinderViewModel
    var onBrowse: () -> Void

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            primaryAction
            if viewModel.hasResults && !viewModel.isScanning {
                rescanLink
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border.opacity(0.8), lineWidth: 0.5)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(settings.accentColor.gradient)
                Image(systemName: "square.on.square")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .shadow(color: settings.accentColor.opacity(0.30), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Find duplicates")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if viewModel.isScanning {
            scanningBlock
        } else if viewModel.hasResults {
            Button(action: onBrowse) {
                Label(browseTitle, systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button {
                Task { await viewModel.scanLibrary() }
            } label: {
                Label("Find duplicates", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var scanningBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: viewModel.progress)
                .tint(settings.accentColor)
            HStack {
                Text("Scanning your library…")
                Spacer()
                Text("\(Int((viewModel.progress * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var rescanLink: some View {
        Button {
            Task { await viewModel.scanLibrary() }
        } label: {
            Label("Scan again", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(settings.accentColor)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            settings.accentColor.opacity(0.18),
                            settings.accentColor.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: Strings

    private var subtitle: String {
        if viewModel.hasResults {
            return summaryLine
        }
        return "Surface byte-identical photos and videos and reclaim space without losing originals."
    }

    private var browseTitle: String {
        let sets = viewModel.photoGroups.count + viewModel.videoGroups.count
        return sets == 1 ? "Browse 1 set" : "Browse \(sets) sets"
    }

    private var summaryLine: String {
        let sets = viewModel.photoGroups.count + viewModel.videoGroups.count
        let extras = viewModel.totalExtraCopies
        let setsLabel = "\(sets) set\(sets == 1 ? "" : "s")"
        let extrasLabel = "\(extras) extra cop\(extras == 1 ? "y" : "ies")"
        return "\(setsLabel) · \(extrasLabel)"
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
