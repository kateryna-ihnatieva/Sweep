import Combine
import Foundation
import Photos
import SwiftUI
import UIKit

// MARK: - User-facing accent palette

/// Pre-curated palette so users can pick an accent without dealing with raw colors.
/// Names map to system colors that adapt to light/dark and accessibility tints.
enum AccentChoice: String, CaseIterable, Identifiable, Codable {
    case indigo
    case blue
    case purple
    case teal
    case mint
    case pink
    case orange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .teal: return "Teal"
        case .mint: return "Mint"
        case .pink: return "Pink"
        case .orange: return "Orange"
        }
    }

    var color: Color {
        switch self {
        case .indigo: return .indigo
        case .blue: return .blue
        case .purple: return .purple
        case .teal: return .teal
        case .mint: return .mint
        case .pink: return .pink
        case .orange: return .orange
        }
    }
}

// MARK: - Settings store

/// Persistent app-wide preferences. Backed by UserDefaults; observe via `@EnvironmentObject`.
/// Singleton so non-View code (e.g. `Haptics`, `AppTheme.accent`) can read current values
/// without plumbing the dependency everywhere. The class is intentionally not isolated to
/// `@MainActor` so it can be read from any thread (UserDefaults is thread-safe). All
/// publisher-triggering writes happen on the main thread because SwiftUI bindings are
/// always invoked on the main actor.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Feedback
    @Published var hapticsEnabled: Bool { didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics) } }
    @Published var videoAutoplayEnabled: Bool { didSet { UserDefaults.standard.set(videoAutoplayEnabled, forKey: Keys.videoAutoplay) } }

    // Safety
    @Published var bigDeleteConfirmEnabled: Bool { didSet { UserDefaults.standard.set(bigDeleteConfirmEnabled, forKey: Keys.bigDeleteConfirm) } }
    @Published var bigDeleteItemsThreshold: Int { didSet { UserDefaults.standard.set(bigDeleteItemsThreshold, forKey: Keys.bigDeleteItems) } }
    @Published var bigDeleteMegabytesThreshold: Int { didSet { UserDefaults.standard.set(bigDeleteMegabytesThreshold, forKey: Keys.bigDeleteMB) } }

    // Appearance
    @Published var accentChoice: AccentChoice {
        didSet { UserDefaults.standard.set(accentChoice.rawValue, forKey: Keys.accent) }
    }

    var accentColor: Color { accentChoice.color }

    private enum Keys {
        static let haptics = "sw.settings.haptics"
        static let videoAutoplay = "sw.settings.videoAutoplay"
        static let bigDeleteConfirm = "sw.settings.bigDeleteConfirm"
        static let bigDeleteItems = "sw.settings.bigDeleteItems"
        static let bigDeleteMB = "sw.settings.bigDeleteMB"
        static let accent = "sw.settings.accent"
    }

    private init() {
        let d = UserDefaults.standard
        hapticsEnabled = d.object(forKey: Keys.haptics) as? Bool ?? true
        videoAutoplayEnabled = d.object(forKey: Keys.videoAutoplay) as? Bool ?? true
        bigDeleteConfirmEnabled = d.object(forKey: Keys.bigDeleteConfirm) as? Bool ?? true
        let items = d.integer(forKey: Keys.bigDeleteItems)
        bigDeleteItemsThreshold = items == 0 ? 50 : items
        let mb = d.integer(forKey: Keys.bigDeleteMB)
        bigDeleteMegabytesThreshold = mb == 0 ? 500 : mb
        let raw = d.string(forKey: Keys.accent) ?? AccentChoice.indigo.rawValue
        accentChoice = AccentChoice(rawValue: raw) ?? .indigo
    }
}

// MARK: - Haptics

/// Centralised haptic feedback. Each call respects `AppSettings.hapticsEnabled` so
/// turning haptics off in Settings silences them app-wide without per-call branching.
@MainActor
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Call before a triggering interaction to reduce first-fire latency.
    static func prepare() {
        guard AppSettings.shared.hapticsEnabled else { return }
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        selection.prepare()
        notification.prepare()
    }

    /// Swiping a card to "Delete" — heavier so destructive choice feels intentional.
    static func swipeDelete() {
        guard AppSettings.shared.hapticsEnabled else { return }
        rigidImpact.impactOccurred(intensity: 0.85)
    }

    /// Swiping a card to "Keep" — lighter, encouraging tap.
    static func swipeKeep() {
        guard AppSettings.shared.hapticsEnabled else { return }
        lightImpact.impactOccurred(intensity: 0.7)
    }

    /// Undoing a swipe — soft, reverse character.
    static func undo() {
        guard AppSettings.shared.hapticsEnabled else { return }
        softImpact.impactOccurred(intensity: 0.6)
    }

    /// User picked something on a list/segment.
    static func selectionChanged() {
        guard AppSettings.shared.hapticsEnabled else { return }
        selection.selectionChanged()
    }

    /// After a confirmed deletion successfully completes.
    static func deleteSucceeded() {
        guard AppSettings.shared.hapticsEnabled else { return }
        notification.notificationOccurred(.success)
    }

    /// Surface an error (deletion failed, etc.).
    static func errorOccurred() {
        guard AppSettings.shared.hapticsEnabled else { return }
        notification.notificationOccurred(.error)
    }

    /// "Be careful" prompt before a heavy action.
    static func warn() {
        guard AppSettings.shared.hapticsEnabled else { return }
        notification.notificationOccurred(.warning)
    }
}

// MARK: - Video prefetcher

/// Warms the next 1–2 video assets so `AVPlayerViewController` doesn't spend the first
/// second of playback decoding from cold. Items are consumed (popped) on use to avoid
/// double-attaching the same `AVPlayerItem` to two players.
@MainActor
final class VideoPrefetcher: ObservableObject {
    private var cache: [String: AVPlayerItem] = [:]
    private var inFlight: Set<String> = []

    /// Pop a previously prefetched item if available.
    func takePlayerItem(for assetID: String) -> AVPlayerItem? {
        cache.removeValue(forKey: assetID)
    }

    /// Begin loading a video asset's `AVPlayerItem` in the background.
    /// Idempotent: repeated calls for the same asset are coalesced.
    func prefetch(asset: PHAsset) {
        guard asset.mediaType == .video else { return }
        let id = asset.localIdentifier
        if cache[id] != nil || inFlight.contains(id) { return }
        inFlight.insert(id)

        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                self.inFlight.remove(id)
                guard let item else { return }
                self.cache[id] = item
            }
        }
    }

    /// Drop everything (e.g. when leaving the swipe screen).
    func reset() {
        cache.removeAll()
        inFlight.removeAll()
    }
}
