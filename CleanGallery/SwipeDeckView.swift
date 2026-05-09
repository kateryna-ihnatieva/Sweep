import AVFoundation
import AVKit
import Photos
import SwiftUI

private enum SwipeDeckViewMetrics {
    /// Uses most of the space between the header and bottom actions (GeometryReader).
    static func cardSize(in container: CGSize) -> CGSize {
        // GeometryReader can report 0×0 on first layout; avoid zero card (invisible media).
        let cw = max(1, container.width)
        let ch = max(1, container.height)
        let w = max(288, min(cw - 8, 480))
        let maxH = ch - 8
        let idealH = max(440, min(w * 1.35, 680))
        // When geometry height is still 0, use ideal height so the card is visible after layout.
        let h = maxH > 0 ? min(maxH, idealH) : idealH
        return CGSize(width: w, height: max(120, h))
    }
}

private enum SwipeChoice {
    case markedDelete(String)
    case kept(String)
}

struct SwipeDeckView: View {
    let assets: [PHAsset]
    @Binding var stagedIds: Set<String>
    var onFinished: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var videoPrefetcher = VideoPrefetcher()

    @State private var index = 0
    @State private var history: [SwipeChoice] = []
    @State private var drag: CGSize = .zero
    @State private var hintOpacity: Double = 1
    @State private var didFireFinished = false
    /// True while the user is pinch/double-tap zoomed into the current photo.
    /// Blocks the deck swipe so one-finger pan navigates the zoomed image instead.
    @State private var photoZoomed = false

    private var current: PHAsset? {
        guard index < assets.count else { return nil }
        return assets[index]
    }

    var body: some View {
        VStack(spacing: 12) {
            if let asset = current {
                progressHeader
                GeometryReader { geo in
                    let cardSize = SwipeDeckViewMetrics.cardSize(in: geo.size)
                    ZStack {
                        swipeHints
                            .allowsHitTesting(false)
                            .opacity(photoZoomed ? 0 : 1)
                        card(for: asset, cardSize: cardSize)
                            .offset(drag)
                            .rotationEffect(.degrees(Double(drag.width / 20)))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: asset.mediaType == .video ? 28 : 14)
                            .onChanged { v in
                                let tx = v.translation.width
                                let ty = v.translation.height
                                // Ignore mostly-vertical motion: keeps the card still on accidental flicks
                                // and never competes with the sheet's "swipe down to dismiss" gesture.
                                guard abs(tx) > abs(ty) else {
                                    if drag != .zero {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            drag = .zero
                                            hintOpacity = 1
                                        }
                                    }
                                    return
                                }
                                drag = CGSize(width: tx, height: 0)
                                hintOpacity = max(0.15, 1 - min(abs(tx) / 120.0, 1))
                            }
                            .onEnded { v in
                                let tx = v.translation.width
                                let ty = v.translation.height
                                guard abs(tx) > abs(ty) else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        drag = .zero
                                        hintOpacity = 1
                                    }
                                    return
                                }
                                decide(translation: tx)
                            },
                        // While the photo is zoomed in, hand off all single-finger gestures
                        // to the inner UIScrollView so the user can pan the zoomed image.
                        including: photoZoomed ? .subviews : .all
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 280)

                actionBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                Color.clear
                    .frame(maxHeight: 240)
                    .onAppear {
                        guard !didFireFinished else { return }
                        didFireFinished = true
                        onFinished()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .onAppear {
            Haptics.prepare()
            prefetchUpcomingVideos()
            // Also prime the very first card if it's a video.
            if assets.indices.contains(0), assets[0].mediaType == .video {
                videoPrefetcher.prefetch(asset: assets[0])
            }
        }
        .onDisappear {
            videoPrefetcher.reset()
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("of \(assets.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let c = current, c.mediaType == .video {
                    Label("Video", systemImage: "play.rectangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if let a = current, let date = a.creationDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(index), total: Double(max(1, assets.count)))
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
    }

    private var swipeHints: some View {
        HStack {
            hintBadge(text: "DELETE", color: AppTheme.danger, system: "trash.fill")
                .opacity(drag.width < -24 ? 1 : 0.18 * hintOpacity)
                .scaleEffect(drag.width < -24 ? 1.05 : 1)
            Spacer()
            hintBadge(text: "KEEP", color: AppTheme.keep, system: "checkmark")
                .opacity(drag.width > 24 ? 1 : 0.18 * hintOpacity)
                .scaleEffect(drag.width > 24 ? 1.05 : 1)
        }
        .padding(.horizontal, 16)
    }

    private func hintBadge(text: String, color: Color, system: String) -> some View {
        Label(text, systemImage: system)
            .font(.caption.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            actionButton(
                icon: "trash.fill",
                title: "Delete",
                tint: AppTheme.danger,
                role: .destructive,
                action: swipeLeftCommit
            )
            undoButton
            actionButton(
                icon: "checkmark",
                title: "Keep",
                tint: AppTheme.keep,
                role: .none,
                action: swipeRightCommit
            )
        }
    }

    private func actionButton(
        icon: String,
        title: String,
        tint: Color,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(tint.gradient)
                    Image(systemName: icon)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                .shadow(color: tint.opacity(0.35), radius: 6, y: 3)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var undoButton: some View {
        Button(action: undo) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(Circle().stroke(AppTheme.border, lineWidth: 0.5))
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(history.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                }
                .frame(width: 56, height: 56)

                Text("Undo")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(history.isEmpty)
    }

    private func card(for asset: PHAsset, cardSize: CGSize) -> some View {
        let side = max(cardSize.width, cardSize.height)
        let scale = max(1, UIScreen.main.scale)
        let px = CGSize(width: side * scale, height: side * scale)
        let innerRadius = AppTheme.cardCorner - 2

        return ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cardCorner, style: .continuous)
                .fill(AppTheme.mediaBackdrop)

            Group {
                if asset.mediaType == .video {
                    SwipeCardVideoPreview(
                        asset: asset,
                        targetSide: side,
                        prefetcher: videoPrefetcher,
                        autoplay: settings.videoAutoplayEnabled
                    )
                } else {
                    ZoomablePhotoView(
                        asset: asset,
                        targetPixelSize: px,
                        onZoomChange: { zoomed in
                            if photoZoomed != zoomed {
                                photoZoomed = zoomed
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
            .padding(3)
            // Forces a fresh ZoomablePhotoView (and therefore a reset zoom level) when the asset changes.
            .id(asset.localIdentifier)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    }

    private func decide(translation: CGFloat) {
        if translation < -90 {
            swipeLeftCommit()
        } else if translation > 90 {
            swipeRightCommit()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                drag = .zero
                hintOpacity = 1
            }
        }
    }

    private func swipeLeftCommit() {
        guard let asset = current else { return }
        Haptics.swipeDelete()
        stagedIds.insert(asset.localIdentifier)
        history.append(.markedDelete(asset.localIdentifier))
        advance()
    }

    private func swipeRightCommit() {
        guard let asset = current else { return }
        Haptics.swipeKeep()
        stagedIds.remove(asset.localIdentifier)
        history.append(.kept(asset.localIdentifier))
        advance()
    }

    private func advance() {
        photoZoomed = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            drag = .zero
            hintOpacity = 1
            index += 1
        }
        prefetchUpcomingVideos()
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        Haptics.undo()
        photoZoomed = false
        index = max(0, index - 1)
        switch last {
        case let .markedDelete(id):
            stagedIds.remove(id)
        case .kept:
            break
        }
    }

    /// Warm the next 1–2 video assets so the next card doesn't decode from cold.
    /// Runs after every advance() and once on first appear.
    private func prefetchUpcomingVideos() {
        for offset in 1...2 {
            let i = index + offset
            guard assets.indices.contains(i) else { break }
            videoPrefetcher.prefetch(asset: assets[i])
        }
    }
}

// MARK: - Video preview (swipe card only)

/// Full `AVPlayerViewController` with sound and timeline; deck uses `simultaneousGesture` so scrubber still works.
private struct SwipeCardVideoPreview: View {
    let asset: PHAsset
    let targetSide: CGFloat
    let prefetcher: VideoPrefetcher
    let autoplay: Bool

    @State private var player: AVPlayer?

    var body: some View {
        let scale = max(1, UIScreen.main.scale)
        let px = CGSize(width: max(1, targetSide) * scale, height: max(1, targetSide) * scale)
        GeometryReader { geo in
            ZStack {
                Color.black
                PHAssetImageView(asset: asset, targetPixelSize: px, contentMode: .scaleAspectFit)
                    .frame(width: geo.size.width, height: geo.size.height)
                if let player {
                    VideoAspectFitPlayer(player: player)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .clipped()
        }
        .task(id: asset.localIdentifier) {
            await startPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    @MainActor
    private func stopPlayback() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        Self.deactivatePlaybackAudioSessionIfPossible()
    }

    @MainActor
    private func startPlayback() async {
        stopPlayback()
        Self.configurePlaybackAudioSession()
        // Prefer a prefetched item so the next swiped video starts instantly. `??` can't
        // host an `await` autoclosure, so check the cache first and fall back to a request.
        let resolvedItem: AVPlayerItem?
        if let cached = prefetcher.takePlayerItem(for: asset.localIdentifier) {
            resolvedItem = cached
        } else {
            resolvedItem = await Self.fetchPlayerItem(for: asset)
        }
        guard let item = resolvedItem else {
            Self.deactivatePlaybackAudioSessionIfPossible()
            return
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = false
        p.volume = 1
        // `AVPlayerViewController` sits above the poster; until the item is ready it is often solid black.
        await Self.waitUntilReadyOrFailed(item: item)
        guard item.status != .failed else {
            Self.deactivatePlaybackAudioSessionIfPossible()
            return
        }
        player = p
        if autoplay { p.play() }
    }

    @MainActor
    private static func waitUntilReadyOrFailed(item: AVPlayerItem) async {
        var ticks = 0
        while item.status == .unknown, ticks < 400 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            ticks += 1
        }
    }

    nonisolated private static func fetchPlayerItem(for asset: PHAsset) async -> AVPlayerItem? {
        await withCheckedContinuation { (cont: CheckedContinuation<AVPlayerItem?, Never>) in
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .automatic
            var done = false
            let lock = NSLock()
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { item, _ in
                lock.lock()
                defer { lock.unlock() }
                guard !done else { return }
                done = true
                cont.resume(returning: item)
            }
        }
    }

    /// Video apps use the playback session so clip audio is audible even when the Ring/Silent switch is on.
    @MainActor
    private static func configurePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("SwipeCardVideoPreview: AVAudioSession \(error.localizedDescription)")
            #endif
        }
    }

    @MainActor
    private static func deactivatePlaybackAudioSessionIfPossible() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            #if DEBUG
            print("SwipeCardVideoPreview: AVAudioSession deactivate \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Letterboxed video (AVPlayerViewController)

private struct VideoAspectFitPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player {
            vc.player = player
        }
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: ()) {
        vc.player?.pause()
        vc.player = nil
    }
}

