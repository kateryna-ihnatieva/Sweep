import Photos
import SwiftUI

struct StagedReviewView: View {
    let title: String
    let allAssetsInScope: [PHAsset]
    @Binding var stagedIds: Set<String>
    var onConfirmDelete: () -> Void
    var onExitWithoutDeleting: () -> Void

    @EnvironmentObject private var gallery: GalleryViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var bigConfirmShown = false
    @State private var pendingBytes: Int64 = 0

    private var stagedAssets: [PHAsset] {
        let map = Dictionary(uniqueKeysWithValues: allAssetsInScope.map { ($0.localIdentifier, $0) })
        return stagedIds.compactMap { map[$0] }
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if stagedAssets.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .safeAreaInset(edge: .bottom) {
            actionBar
                .background(.bar)
        }
        .confirmationDialog(
            "Delete \(stagedAssets.count) item\(stagedAssets.count == 1 ? "" : "s")?",
            isPresented: $bigConfirmShown,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onConfirmDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bigDeleteMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(stagedAssets.isEmpty
                 ? "Nothing marked for removal. Everything stays in your library."
                 : "After you confirm, selected items move to Recently Deleted in the Photos app and stay recoverable for the period Apple allows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing staged", systemImage: "tray")
        } description: {
            Text("Swipe left on items in the deck to stage them, or use the Delete button under the card.")
        }
        .padding(.top, 20)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(stagedAssets, id: \.localIdentifier) { (asset: PHAsset) in
                ZStack(alignment: .topTrailing) {
                    AssetThumbnailView(asset: asset, targetSide: 120)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.5)
                        }

                    Button {
                        stagedIds.remove(asset.localIdentifier)
                        Haptics.selectionChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.65))
                            .font(.title3)
                            .padding(6)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if !stagedAssets.isEmpty {
                Button(role: .destructive) {
                    Task { await maybeConfirmDelete() }
                } label: {
                    Label("Delete \(stagedAssets.count) item\(stagedAssets.count == 1 ? "" : "s")",
                          systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.danger)
            }

            Button(stagedAssets.isEmpty ? "Done" : "Cancel") {
                if !stagedAssets.isEmpty { stagedIds.removeAll() }
                onExitWithoutDeleting()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// Centralised guard before sending items to Photos. When the user enabled the
    /// "Confirm large deletions" safety net, we look up the staged size on a background
    /// task and add an extra confirmation if either threshold is hit.
    @MainActor
    private func maybeConfirmDelete() async {
        let count = stagedAssets.count
        guard count > 0 else {
            onConfirmDelete()
            return
        }
        guard settings.bigDeleteConfirmEnabled else {
            onConfirmDelete()
            return
        }

        if count >= settings.bigDeleteItemsThreshold {
            pendingBytes = await gallery.estimatedBytes(for: stagedAssets.map(\.localIdentifier))
            Haptics.warn()
            bigConfirmShown = true
            return
        }

        let bytes = await gallery.estimatedBytes(for: stagedAssets.map(\.localIdentifier))
        pendingBytes = bytes
        let mbThresholdBytes = Int64(settings.bigDeleteMegabytesThreshold) * 1_048_576
        if bytes >= mbThresholdBytes {
            Haptics.warn()
            bigConfirmShown = true
            return
        }

        onConfirmDelete()
    }

    private var bigDeleteMessage: String {
        let count = stagedAssets.count
        let suffix = count == 1 ? "" : "s"
        if pendingBytes > 0 {
            return "Sweep will move \(count) item\(suffix) (~\(pendingBytes.formattedByteCount)) to Recently Deleted. You can recover them in the Photos app for the period Apple allows."
        }
        return "Sweep will move \(count) item\(suffix) to Recently Deleted. You can recover them in the Photos app for the period Apple allows."
    }
}
