import Photos
import SwiftUI

struct AssetThumbnailView: View {
    let asset: PHAsset
    var targetSide: CGFloat
    /// Letterboxed `aspectFit` on black (e.g. swipe card). Cropped `aspectFill` for grids.
    var letterboxedFit: Bool = false

    var body: some View {
        let scale = max(1, UIScreen.main.scale)
        let side = max(1, targetSide) * scale
        let px = CGSize(width: side, height: side)

        ZStack {
            if letterboxedFit {
                Color.black
            } else {
                Color(uiColor: .secondarySystemBackground)
            }
            PHAssetImageView(
                asset: asset,
                targetPixelSize: px,
                contentMode: letterboxedFit ? .scaleAspectFit : .scaleAspectFill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(12)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }
}
