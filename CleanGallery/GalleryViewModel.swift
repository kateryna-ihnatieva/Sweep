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
        await reloadMonths()
        return DeletionCommitResult(freedBytes: bytes, photoCount: photos, videoCount: videos)
    }

    func markMonthCompleted(_ monthId: String) {
        completedMonthIds.insert(monthId)
    }

    func markMonthIncomplete(_ monthId: String) {
        completedMonthIds.remove(monthId)
    }

    private func persistCompletedMonths() {
        UserDefaults.standard.set(Array(completedMonthIds), forKey: Keys.completedMonths)
    }

    func randomSample(count: Int = 10) -> [PHAsset] {
        let all = months.flatMap(\.assets)
        guard !all.isEmpty else { return [] }
        return Array(all.shuffled().prefix(count))
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
