import CryptoKit
import Foundation
import Photos
import UIKit

enum DuplicateScanner {

    // MARK: - Fetch

    static func fetchAssets(mediaType: PHAssetMediaType) async -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.includeHiddenAssets = false
            let fetch = PHAsset.fetchAssets(with: mediaType, options: options)
            var list: [PHAsset] = []
            fetch.enumerateObjects { a, _, _ in list.append(a) }
            return list
        }.value
    }

    // MARK: - Photo clusters (truly identical bytes)

    /// Two-pass photo grouping:
    /// 1. Cheap candidate filter on `pixelWidth × pixelHeight × primaryResourceSize`.
    ///    The size of the *primary* resource is used (not the sum across resources),
    ///    so an unedited copy and an edited copy of the same original still bucket
    ///    together. When the size is unknown (iCloud-only assets that haven't been
    ///    downloaded yet), the asset still gets a dimension-only fallback bucket
    ///    so the hashing pass can still match it to a peer.
    /// 2. SHA-256 of the primary `PHAssetResource` data (streamed) for each candidate, then group by hash.
    /// Only assets with identical bytes end up in the same group.
    static func clusterPhotos(
        _ assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async -> [DuplicateGroup] {
        guard !assets.isEmpty else { return [] }
        return await clusterIdentical(
            assets,
            kind: .photoVisual,
            idPrefix: "p_",
            progress: progress,
            cheapKey: { a in
                let dims = "\(a.pixelWidth)x\(a.pixelHeight)"
                let size = primaryResourceSize(for: a)
                return size > 0 ? "\(dims)|\(size)" : "\(dims)|cloud"
            }
        )
    }

    // MARK: - Video clusters (truly identical bytes)

    /// Same idea as `clusterPhotos`, with duration baked into the cheap key. Falls
    /// back to a `dimensions × duration` bucket for cloud-only videos with no
    /// readable file size.
    static func clusterVideosWeak(
        _ assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async -> [DuplicateGroup] {
        guard !assets.isEmpty else { return [] }
        return await clusterIdentical(
            assets,
            kind: .videoHeuristic,
            idPrefix: "v_",
            progress: progress,
            cheapKey: { a in
                let durMs = Int((a.duration * 1000).rounded())
                let dims = "\(a.pixelWidth)x\(a.pixelHeight)|\(durMs)"
                let size = primaryResourceSize(for: a)
                return size > 0 ? "\(dims)|\(size)" : "\(dims)|cloud"
            }
        )
    }

    // MARK: - Shared identical-bytes pipeline

    /// Cap on concurrent SHA-256 streaming requests. Keeps iCloud / disk pressure
    /// reasonable when a fallback dimensions-only bucket contains many assets.
    private static let maxConcurrentHashes = 4

    private static func clusterIdentical(
        _ assets: [PHAsset],
        kind: DuplicateKind,
        idPrefix: String,
        progress: @Sendable @escaping (Double) -> Void,
        cheapKey: (PHAsset) -> String?
    ) async -> [DuplicateGroup] {
        var byCheapKey: [String: [PHAsset]] = [:]
        var skipped = 0
        for a in assets {
            guard let key = cheapKey(a) else {
                skipped += 1
                continue
            }
            byCheapKey[key, default: []].append(a)
        }

        let candidates = byCheapKey.values.filter { $0.count >= 2 }
        #if DEBUG
        let candidateAssets = candidates.reduce(0) { $0 + $1.count }
        print("DuplicateScanner[\(kind)]: \(assets.count) input, \(skipped) skipped, \(byCheapKey.count) cheap-key buckets, \(candidates.count) candidate buckets covering \(candidateAssets) assets")
        #endif

        guard !candidates.isEmpty else {
            progress(1)
            return []
        }

        let totalToHash = candidates.reduce(0) { $0 + $1.count }
        var hashed = 0
        var finalClusters: [[PHAsset]] = []

        for candidate in candidates {
            let byHash = await hashCandidateBucket(candidate) { _ in
                hashed += 1
                progress(min(0.99, Double(hashed) / Double(totalToHash)))
            }
            for cluster in byHash.values where cluster.count >= 2 {
                finalClusters.append(cluster)
            }
        }

        #if DEBUG
        let identicalAssets = finalClusters.reduce(0) { $0 + $1.count }
        print("DuplicateScanner[\(kind)]: produced \(finalClusters.count) duplicate groups covering \(identicalAssets) assets")
        #endif

        progress(1)

        return finalClusters
            .map { list in
                let sorted = list.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
                let seed = sorted.map(\.localIdentifier).sorted().joined(separator: "|")
                let idBody = sha256hex(Data(seed.utf8))
                return DuplicateGroup(id: "\(idPrefix)\(idBody)", kind: kind, assets: sorted)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.id < rhs.id
            }
    }

    /// Hash a candidate bucket with bounded concurrency. Returns assets grouped
    /// by SHA-256 hex digest; assets that fail to hash are silently dropped.
    private static func hashCandidateBucket(
        _ bucket: [PHAsset],
        progressTick: @escaping (PHAsset) -> Void
    ) async -> [String: [PHAsset]] {
        var byHash: [String: [PHAsset]] = [:]
        await withTaskGroup(of: (PHAsset, String?).self) { group in
            var dispatched = 0
            var iterator = bucket.makeIterator()
            // Prime the pump with up to `maxConcurrentHashes` parallel hashes.
            while dispatched < maxConcurrentHashes, let asset = iterator.next() {
                group.addTask {
                    let h = await sha256OfPrimaryResource(asset)
                    return (asset, h)
                }
                dispatched += 1
            }
            // For each completed hash, slot in the next asset until the bucket is drained.
            for await (asset, hash) in group {
                if let hash {
                    byHash[hash, default: []].append(asset)
                }
                progressTick(asset)
                if let next = iterator.next() {
                    group.addTask {
                        let h = await sha256OfPrimaryResource(next)
                        return (next, h)
                    }
                }
            }
        }
        return byHash
    }

    // MARK: - Hashing

    /// SHA-256 of the asset's primary file resource, streamed in chunks (no full file in memory).
    private static func sha256OfPrimaryResource(_ asset: PHAsset) async -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = pickPrimaryResource(resources, mediaType: asset.mediaType) else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            // SHA256 is value-typed; mutate it inside the data callback (called serially on a private queue).
            let box = HasherBox()
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().requestData(
                for: primary,
                options: opts,
                dataReceivedHandler: { chunk in
                    box.update(chunk)
                },
                completionHandler: { error in
                    if error != nil {
                        cont.resume(returning: nil)
                    } else {
                        cont.resume(returning: box.hexDigest())
                    }
                }
            )
        }
    }

    private static func pickPrimaryResource(_ resources: [PHAssetResource], mediaType: PHAssetMediaType) -> PHAssetResource? {
        switch mediaType {
        case .image:
            return resources.first { $0.type == .photo }
                ?? resources.first { $0.type == .fullSizePhoto }
                ?? resources.first
        case .video:
            return resources.first { $0.type == .video }
                ?? resources.first { $0.type == .fullSizeVideo }
                ?? resources.first
        default:
            return resources.first
        }
    }

    fileprivate static func sha256hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Resource helpers

    /// Size of the *primary* resource only — i.e. the file we will SHA-256.
    /// Returns 0 for cloud-only assets where PhotoKit hasn't surfaced a fileSize yet,
    /// in which case the caller should bucket by dimensions instead of dropping.
    private static func primaryResourceSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = pickPrimaryResource(resources, mediaType: asset.mediaType) else { return 0 }
        if let n = primary.value(forKey: "fileSize") as? CLongLong, n > 0 {
            return Int64(n)
        }
        return 0
    }
}

/// Reference wrapper around `SHA256` so we can mutate inside `@Sendable` callbacks safely
/// (PHAssetResourceManager dispatches the data callbacks serially per request).
private final class HasherBox: @unchecked Sendable {
    private var hasher = SHA256()

    func update(_ data: Data) {
        hasher.update(data: data)
    }

    func hexDigest() -> String {
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
