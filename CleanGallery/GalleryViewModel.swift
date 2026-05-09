import Combine
import Foundation
import Photos
import UIKit

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var authorization: PHAuthorizationStatus = .notDetermined
    @Published private(set) var months: [MonthBucket] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    /// Months user finished cleaning (after final confirm).
    @Published var completedMonthIds: Set<String> {
        didSet { persistCompletedMonths() }
    }

    /// Snapshot of a month at the moment the user marked it "reviewed".
    /// We store it so the next library reload can detect new media and auto-unmark.
    /// Persisted as JSON keyed by month id.
    private var completionSnapshots: [String: MonthCompletionSnapshot] = [:]

    /// `localIdentifier`s of assets the user has already swiped at least once in
    /// any flow (deck, random, duplicates). Used by `randomSample(count:)` to
    /// avoid showing the same items repeatedly. Persisted across launches.
    @Published private(set) var seenAssetIds: Set<String> = []

    @Published var totalDeletedItems: Int {
        didSet { UserDefaults.standard.set(totalDeletedItems, forKey: Keys.totalDeletedItems) }
    }

    @Published var totalDeletedPhotos: Int {
        didSet { UserDefaults.standard.set(totalDeletedPhotos, forKey: Keys.totalDeletedPhotos) }
    }

    @Published var totalDeletedVideos: Int {
        didSet { UserDefaults.standard.set(totalDeletedVideos, forKey: Keys.totalDeletedVideos) }
    }

    @Published var totalFreedBytes: Int64 {
        didSet { UserDefaults.standard.set(totalFreedBytes, forKey: Keys.totalFreedBytes) }
    }

    private let imageManager = PHCachingImageManager()
    private let calendar = Calendar.current

    private enum Keys {
        static let completedMonths = "cg.completedMonthIds"
        static let completionSnapshots = "cg.completionSnapshots"
        static let seenAssetIds = "cg.seenAssetIds"
        static let totalDeletedItems = "cg.totalDeletedItems"
        static let totalDeletedPhotos = "cg.totalDeletedPhotos"
        static let totalDeletedVideos = "cg.totalDeletedVideos"
        static let totalFreedBytes = "cg.totalFreedBytes"
    }

    init() {
        if let saved = UserDefaults.standard.array(forKey: Keys.completedMonths) as? [String] {
            completedMonthIds = Set(saved)
        } else {
            completedMonthIds = []
        }
        if let data = UserDefaults.standard.data(forKey: Keys.completionSnapshots),
           let decoded = try? JSONDecoder().decode([String: MonthCompletionSnapshot].self, from: data) {
            completionSnapshots = decoded
        }
        if let savedSeen = UserDefaults.standard.array(forKey: Keys.seenAssetIds) as? [String] {
            seenAssetIds = Set(savedSeen)
        }
        totalDeletedItems = UserDefaults.standard.integer(forKey: Keys.totalDeletedItems)
        totalDeletedPhotos = UserDefaults.standard.integer(forKey: Keys.totalDeletedPhotos)
        totalDeletedVideos = UserDefaults.standard.integer(forKey: Keys.totalDeletedVideos)
        let b = UserDefaults.standard.object(forKey: Keys.totalFreedBytes) as? Int64
        totalFreedBytes = b ?? 0
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refreshAuthorization() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                self?.authorization = status
                if status == .authorized || status == .limited {
                    await self?.reloadMonths()
                }
            }
        }
    }

    func reloadMonths() async {
        guard authorization == .authorized || authorization == .limited else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let result = await Task.detached(priority: .userInitiated) { Self.fetchMonthBuckets() }.value
        switch result {
        case let .success(buckets):
            months = buckets
            reconcileCompletionWithLibrary()
            pruneSeenAssetsAgainstLibrary()
        case let .failure(err):
            loadError = err.localizedDescription
        }
    }

    nonisolated private static func fetchMonthBuckets() -> Result<[MonthBucket], Error> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: options)
        var map: [String: [PHAsset]] = [:]
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"

        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let y = comps.year, let m = comps.month else { return }
            let key = String(format: "%04d-%02d", y, m)
            map[key, default: []].append(asset)
        }

        let keys = map.keys.sorted(by: >)
        let buckets: [MonthBucket] = keys.compactMap { key in
            guard var assets = map[key], !assets.isEmpty else { return nil }
            assets.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            let sortDate = assets.first?.creationDate ?? .distantPast
            let title = Self.title(forMonthKey: key, formatter: formatter, calendar: cal)
            return MonthBucket(id: key, sortDate: sortDate, title: title, assets: assets)
        }
        return .success(buckets)
    }

    nonisolated private static func title(forMonthKey key: String, formatter: DateFormatter, calendar: Calendar) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: 1)) else {
            return key
        }
        return formatter.string(from: date).capitalized
    }

    func estimatedBytes(for localIds: [String]) async -> Int64 {
        await Task.detached(priority: .utility) {
            Self.byteSize(for: localIds)
        }.value
    }

    nonisolated private static func byteSize(for localIds: [String]) -> Int64 {
        var total: Int64 = 0
        let opts = PHFetchOptions()
        opts.includeHiddenAssets = true
        for id in localIds {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: opts)
            guard let asset = fetch.firstObject else { continue }
            let resources = PHAssetResource.assetResources(for: asset)
            for r in resources {
                if let n = r.value(forKey: "fileSize") as? CLongLong {
                    total += Int64(n)
                }
            }
        }
        return total
    }

    func commitDeletion(for localIds: [String]) async throws -> DeletionCommitResult {
        let bytes = await estimatedBytes(for: localIds)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: localIds, options: nil)
        var list: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in list.append(a) }

        var photos = 0
        var videos = 0
        for a in list {
            switch a.mediaType {
            case .image: photos += 1
            case .video: videos += 1
            default: break
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(list as NSArray)
            } completionHandler: { ok, err in
                if let err {
                    cont.resume(throwing: err)
                } else if ok {
                    cont.resume()
                } else {
                    cont.resume(throwing: NSError(domain: "Sweep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not delete selected items."]))
                }
            }
        }

        let count = localIds.count
        totalDeletedItems += count
        totalDeletedPhotos += photos
        totalDeletedVideos += videos
        totalFreedBytes += bytes
        // Deleted assets disappear from the library and never need to be filtered
        // out of future random samples; drop them from the seen-set so it doesn't
        // accumulate stale ids forever.
        forgetSeenAssets(ids: localIds)
        await reloadMonths()
        return DeletionCommitResult(freedBytes: bytes, photoCount: photos, videoCount: videos)
    }

    func markMonthCompleted(_ monthId: String) {
        completedMonthIds.insert(monthId)
        if let bucket = months.first(where: { $0.id == monthId }) {
            completionSnapshots[monthId] = Self.snapshot(of: bucket)
            persistCompletionSnapshots()
        }
    }

    func markMonthIncomplete(_ monthId: String) {
        completedMonthIds.remove(monthId)
        if completionSnapshots.removeValue(forKey: monthId) != nil {
            persistCompletionSnapshots()
        }
    }

    /// Wipe lifetime stats. The library and "completed months" set are untouched.
    func resetStats() {
        totalDeletedItems = 0
        totalDeletedPhotos = 0
        totalDeletedVideos = 0
        totalFreedBytes = 0
    }

    /// Forget which months the user already swiped through.
    /// The library (and any actually deleted assets) is untouched.
    func resetMonthCompletion() {
        completedMonthIds.removeAll()
        if !completionSnapshots.isEmpty {
            completionSnapshots.removeAll()
            persistCompletionSnapshots()
        }
    }

    private func persistCompletedMonths() {
        UserDefaults.standard.set(Array(completedMonthIds), forKey: Keys.completedMonths)
    }

    private func persistCompletionSnapshots() {
        if let data = try? JSONEncoder().encode(completionSnapshots) {
            UserDefaults.standard.set(data, forKey: Keys.completionSnapshots)
        }
    }

    /// After a fresh library snapshot, walk completed months and:
    ///   * auto-unmark any month whose asset count grew or that received
    ///     a newer-dated asset since the user marked it reviewed,
    ///   * back-fill snapshots for months that were marked reviewed before
    ///     this feature shipped (legacy users) so the next import triggers
    ///     auto-unmark properly.
    private func reconcileCompletionWithLibrary() {
        guard !completedMonthIds.isEmpty else { return }
        var snapshotsChanged = false
        var idsToUnmark: Set<String> = []

        for month in months where completedMonthIds.contains(month.id) {
            let current = Self.snapshot(of: month)
            if let previous = completionSnapshots[month.id] {
                if current.assetCount > previous.assetCount
                    || current.latestCreationTimestamp > previous.latestCreationTimestamp {
                    idsToUnmark.insert(month.id)
                }
            } else {
                completionSnapshots[month.id] = current
                snapshotsChanged = true
            }
        }

        if !idsToUnmark.isEmpty {
            completedMonthIds.subtract(idsToUnmark)
            for id in idsToUnmark {
                completionSnapshots.removeValue(forKey: id)
            }
            snapshotsChanged = true
        }

        if snapshotsChanged {
            persistCompletionSnapshots()
        }
    }

    private static func snapshot(of bucket: MonthBucket) -> MonthCompletionSnapshot {
        let count = bucket.assets.count
        let latest = bucket.assets
            .compactMap { $0.creationDate?.timeIntervalSince1970 }
            .max() ?? 0
        return MonthCompletionSnapshot(assetCount: count, latestCreationTimestamp: latest)
    }

    /// Result of `nextRandomBatch` — knows whether we had to recycle previously
    /// seen items because the library is fully reviewed.
    struct RandomBatch {
        let assets: [PHAsset]
        /// True when the user has already swiped through every asset in their library
        /// at least once, and the batch is padded with previously seen items.
        let isRecyclingSeen: Bool
    }

    /// Random pick that prefers items the user has *not* swiped before. When the
    /// pool of unseen items is smaller than `count`, the batch is filled from
    /// previously seen items so the user still has something to act on.
    func nextRandomBatch(count: Int = 10) -> RandomBatch {
        let all = months.flatMap(\.assets)
        guard !all.isEmpty else { return RandomBatch(assets: [], isRecyclingSeen: false) }

        let unseen = all.filter { !seenAssetIds.contains($0.localIdentifier) }
        if unseen.count >= count {
            return RandomBatch(
                assets: Array(unseen.shuffled().prefix(count)),
                isRecyclingSeen: false
            )
        }

        var batch = unseen.shuffled()
        let needed = count - batch.count
        if needed > 0 {
            let seen = all.filter { seenAssetIds.contains($0.localIdentifier) }
            batch.append(contentsOf: seen.shuffled().prefix(needed))
        }
        return RandomBatch(
            assets: batch,
            isRecyclingSeen: !batch.isEmpty && batch.count > unseen.count
        )
    }

    /// Legacy single-pick API kept for callers that just want a quick handful
    /// without awareness of the seen-set. Internally goes through
    /// `nextRandomBatch` so behavior is consistent.
    func randomSample(count: Int = 10) -> [PHAsset] {
        nextRandomBatch(count: count).assets
    }

    // MARK: - Seen-asset tracking

    /// Mark a single asset as seen. Idempotent and persists immediately so the
    /// information survives a force-quit mid-deck.
    func markAssetSeen(_ id: String) {
        guard !id.isEmpty, !seenAssetIds.contains(id) else { return }
        seenAssetIds.insert(id)
        persistSeenAssets()
    }

    /// Bulk variant for batched updates (e.g. on deck completion).
    func markAssetsSeen(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let new = ids.filter { !seenAssetIds.contains($0) }
        guard !new.isEmpty else { return }
        for id in new { seenAssetIds.insert(id) }
        persistSeenAssets()
    }

    /// User-facing reset (Settings → Reset viewed photos).
    func resetSeenAssets() {
        guard !seenAssetIds.isEmpty else { return }
        seenAssetIds.removeAll()
        persistSeenAssets()
    }

    /// Drop ids from the seen-set without touching anything else. Called from
    /// `commitDeletion` because removed assets can never appear in a sample again.
    private func forgetSeenAssets(ids: [String]) {
        let removable = ids.filter { seenAssetIds.contains($0) }
        guard !removable.isEmpty else { return }
        for id in removable { seenAssetIds.remove(id) }
        persistSeenAssets()
    }

    /// Garbage-collect ids that no longer correspond to any asset in the library
    /// (e.g. user deleted them in the Photos app outside Sweep). Called after
    /// every successful library reload.
    private func pruneSeenAssetsAgainstLibrary() {
        guard !seenAssetIds.isEmpty else { return }
        let alive = Set(months.flatMap { $0.assets.map(\.localIdentifier) })
        let pruned = seenAssetIds.intersection(alive)
        guard pruned.count != seenAssetIds.count else { return }
        seenAssetIds = pruned
        persistSeenAssets()
    }

    private func persistSeenAssets() {
        UserDefaults.standard.set(Array(seenAssetIds), forKey: Keys.seenAssetIds)
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    /// May invoke `completion` more than once (opportunistic: preview then final). Callers must tolerate nils and coalesce.
    func requestImage(asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast
        let w = max(1, targetSize.width)
        let h = max(1, targetSize.height)
        let size = CGSize(width: w, height: h)
        opts.version = .current
        PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: opts) { img, _ in
            DispatchQueue.main.async {
                completion(img)
            }
        }
    }
}
