import Photos
import SwiftUI

struct StagedReviewView: View {
    let title: String
    let allAssetsInScope: [PHAsset]
    @Binding var stagedIds: Set<String>
    var onConfirmDelete: () -> Void
    var onExitWithoutDeleting: () -> Void

    private var stagedAssets: [PHAsset] {
        let map = Dictionary(uniqueKeysWithValues: allAssetsInScope.map { ($0.localIdentifier, $0) })
        return stagedIds.compactMap { map[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                if stagedAssets.isEmpty {
                    Text("Nothing marked for removal. Everything stays in your library.")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text("After you confirm, selected photos and videos move to Recently Deleted in the Photos app. You can recover them there for the period Apple allows.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(stagedAssets, id: \.localIdentifier) { asset in
                            ZStack(alignment: .topTrailing) {
                                AssetThumbnailView(asset: asset, targetSide: 120)
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                Button {
                                    stagedIds.remove(asset.localIdentifier)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    if !stagedAssets.isEmpty {
                        Button("Confirm deletion (\(stagedAssets.count))") {
                            onConfirmDelete()
                        }
                        .buttonStyle(PrimaryButtonStyle(role: .destructive))
                    }

                    Button(stagedAssets.isEmpty ? "Done" : "Exit without deleting") {
                        stagedIds.removeAll()
                        onExitWithoutDeleting()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.textSecondary)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .background(AppTheme.background)
    }
}
