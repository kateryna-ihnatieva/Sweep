import Photos
import SwiftUI
import UIKit

/// Hosts a `UIImageView` pinned to edges so SwiftUI always proposes a non-zero frame (plain `UIImageView`
/// has no intrinsic size until an image loads, which can collapse to 0×0 in nested layouts).
final class AssetImageContainerView: UIView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Loads a still preview from the Photos library into a `UIImageView`.
struct PHAssetImageView: UIViewRepresentable {
    let asset: PHAsset
    /// Target size in **pixels** (typically `points × UIScreen.main.scale`).
    var targetPixelSize: CGSize
    var contentMode: UIView.ContentMode

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AssetImageContainerView {
        let v = AssetImageContainerView()
        v.imageView.contentMode = contentMode
        v.imageView.isAccessibilityElement = true
        v.imageView.accessibilityLabel = "Photo"
        return v
    }

    func updateUIView(_ container: AssetImageContainerView, context: Context) {
        let imageView = container.imageView
        imageView.contentMode = contentMode

        let c = context.coordinator
        let id = asset.localIdentifier
        // PhotoKit is happiest with reasonable pixel sizes; huge targets can fail or take very long.
        let maxEdge: CGFloat = 2048
        var w = max(1, targetPixelSize.width)
        var h = max(1, targetPixelSize.height)
        let longEdge = max(w, h)
        if longEdge > maxEdge {
            let s = maxEdge / longEdge
            w = max(1, floor(w * s))
            h = max(1, floor(h * s))
        }
        let size = CGSize(width: w, height: h)

        if c.expectedAssetId == id,
           c.lastRequestedPixelSize == size,
           c.lastContentMode == contentMode {
            return
        }

        c.cancel()
        c.expectedAssetId = id
        c.lastRequestedPixelSize = size
        c.lastContentMode = contentMode
        imageView.image = nil

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = true
        opts.version = .current

        let phMode: PHImageContentMode = contentMode == .scaleAspectFit ? .aspectFit : .aspectFill

        let expectedId = id
        let req = PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: phMode,
            options: opts
        ) { image, info in
            if (info?[PHImageCancelledKey] as? Bool) == true { return }
            if let err = info?[PHImageErrorKey] as? Error {
                #if DEBUG
                print("PHAssetImageView requestImage error: \(err.localizedDescription)")
                #endif
            }
            DispatchQueue.main.async {
                guard c.expectedAssetId == expectedId else { return }
                if let image {
                    imageView.image = image
                }
            }
        }
        c.requestID = req
    }

    static func dismantleUIView(_ uiView: AssetImageContainerView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    /// Ensures the representable participates in SwiftUI layout even before pixels arrive.
    static func sizeThatFits(_ proposal: ProposedViewSize, uiView: AssetImageContainerView, context: Context) -> CGSize? {
        guard let w = proposal.width, let h = proposal.height else { return nil }
        let ww = max(1, w)
        let hh = max(1, h)
        return CGSize(width: ww, height: hh)
    }

    final class Coordinator {
        var requestID: PHImageRequestID = PHInvalidImageRequestID
        var expectedAssetId: String?
        var lastRequestedPixelSize: CGSize = .zero
        var lastContentMode: UIView.ContentMode = .scaleAspectFill

        func cancel() {
            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
                requestID = PHInvalidImageRequestID
            }
        }
    }
}
