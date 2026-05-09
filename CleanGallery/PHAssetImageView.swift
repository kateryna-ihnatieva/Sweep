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

// MARK: - Zoomable photo view (pinch + double-tap + one-finger pan)

/// `UIScrollView`-backed photo viewer for the swipe deck.
/// - Pinch to zoom (between fit-to-card and 4× of fit).
/// - Double-tap to toggle between fit and ~2×, centered on the tap.
/// - When zoomed, the scroll view’s native pan handles single-finger navigation.
/// - `onZoomChange` reports whether the user is currently zoomed in, so the
///   parent deck can suppress its swipe gesture while the user is exploring the photo.
struct ZoomablePhotoView: UIViewRepresentable {
    let asset: PHAsset
    /// Target size in **pixels** for the PhotoKit request.
    var targetPixelSize: CGSize
    var onZoomChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ZoomScrollView {
        let v = ZoomScrollView()
        v.onZoomedChanged = { zoomed in
            DispatchQueue.main.async { onZoomChange(zoomed) }
        }
        loadImage(into: v, coordinator: context.coordinator)
        return v
    }

    func updateUIView(_ v: ZoomScrollView, context: Context) {
        // Re-bind the closure each update so it captures the latest SwiftUI state.
        v.onZoomedChanged = { zoomed in
            DispatchQueue.main.async { onZoomChange(zoomed) }
        }
        let id = asset.localIdentifier
        if context.coordinator.expectedAssetId != id {
            context.coordinator.cancel()
            loadImage(into: v, coordinator: context.coordinator)
        }
    }

    static func dismantleUIView(_ uiView: ZoomScrollView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    static func sizeThatFits(_ proposal: ProposedViewSize, uiView: ZoomScrollView, context: Context) -> CGSize? {
        guard let w = proposal.width, let h = proposal.height else { return nil }
        return CGSize(width: max(1, w), height: max(1, h))
    }

    private func loadImage(into v: ZoomScrollView, coordinator: Coordinator) {
        let id = asset.localIdentifier
        let maxEdge: CGFloat = 4096
        var w = max(1, targetPixelSize.width)
        var h = max(1, targetPixelSize.height)
        let longEdge = max(w, h)
        if longEdge > maxEdge {
            let s = maxEdge / longEdge
            w = floor(w * s)
            h = floor(h * s)
        }
        let size = CGSize(width: w, height: h)
        coordinator.expectedAssetId = id

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = true
        opts.version = .current

        let req = PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: opts
        ) { image, info in
            if (info?[PHImageCancelledKey] as? Bool) == true { return }
            DispatchQueue.main.async {
                guard coordinator.expectedAssetId == id, let image else { return }
                v.setImage(image)
            }
        }
        coordinator.requestID = req
    }

    final class Coordinator {
        var requestID: PHImageRequestID = PHInvalidImageRequestID
        var expectedAssetId: String?

        func cancel() {
            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
                requestID = PHInvalidImageRequestID
            }
        }
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onZoomedChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        decelerationRate = .fast
        clipsToBounds = true
        minimumZoomScale = 1
        maximumZoomScale = 1
        addSubview(imageView)
        imageView.contentMode = .scaleToFill

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        if imageView.image === image { return }
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        recomputeZoomScales(snapToFit: true)
        centerContent()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageView.image != nil else { return }
        let wasAtFit = abs(zoomScale - minimumZoomScale) < 0.0005
        recomputeZoomScales(snapToFit: wasAtFit)
        centerContent()
    }

    private func recomputeZoomScales(snapToFit: Bool) {
        guard let img = imageView.image,
              bounds.width > 0, bounds.height > 0,
              img.size.width > 0, img.size.height > 0 else { return }
        let xScale = bounds.width / img.size.width
        let yScale = bounds.height / img.size.height
        let fit = min(xScale, yScale)
        minimumZoomScale = fit
        maximumZoomScale = max(fit * 4, fit + 0.01)
        if snapToFit || zoomScale < fit {
            setZoomScale(fit, animated: false)
        }
    }

    private func centerContent() {
        let xPad = max(0, (bounds.width - contentSize.width) / 2)
        let yPad = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: yPad, left: xPad, bottom: yPad, right: xPad)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        let zoomed = zoomScale > minimumZoomScale + 0.001
        onZoomedChanged?(zoomed)
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.001 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let target = min(maximumZoomScale, minimumZoomScale * 2)
            let point = g.location(in: imageView)
            let w = bounds.width / target
            let h = bounds.height / target
            let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
            zoom(to: rect, animated: true)
        }
    }
}
