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
    /// 1. Cheap candidate filter on `pixelWidth × pixelHeight × byteSum`.
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
                let bs = byteSum(for: a)
                guard bs > 0 else { return nil }
                return "\(a.pixelWidth)x\(a.pixelHeight)|\(bs)"
            }
        )
    }

    // MARK: - Video clusters (truly identical bytes)

    /// Same idea as `clusterPhotos`, with a slightly stricter cheap filter (also requires identical duration).
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
                let bs = byteSum(for: a)
                guard bs > 0 else { return nil }
                let durMs = Int((a.duration * 1000).rounded())
                return "\(a.pixelWidth)x\(a.pixelHeight)|\(durMs)|\(bs)"
            }
        )
    }

    // MARK: - Shared identical-bytes pipeline

    private static func clusterIdentical(
        _ assets: [PHAsset],
        kind: DuplicateKind,
        idPrefix: String,
        progress: @Sendable @escaping (Double) -> Void,
        cheapKey: (PHAsset) -> String?
    ) async -> [DuplicateGroup] {
        var byCheapKey: [String: [PHAsset]] = [:]
        for a in assets {
            guard let key = cheapKey(a) else { continue }
            byCheapKey[key, default: []].append(a)
        }

        let candidates = byCheapKey.values.filter { $0.count >= 2 }
        guard !candidates.isEmpty else {
            progress(1)
            return []
        }

        let totalToHash = candidates.reduce(0) { $0 + $1.count }
        var hashed = 0
        var finalClusters: [[PHAsset]] = []

        for candidate in candidates {
            var byHash: [String: [PHAsset]] = [:]
            await withTaskGroup(of: (PHAsset, String?).self) { group in
                for a in candidate {
                    group.addTask {
                        let h = await sha256OfPrimaryResource(a)
                        return (a, h)
                    }
                }
                for await (asset, hash) in group {
                    if let hash {
                        byHash[hash, default: []].append(asset)
                    }
                    hashed += 1
                    progress(min(0.99, Double(hashed) / Double(totalToHash)))
                }
            }
            for cluster in byHash.values where cluster.count >= 2 {
                finalClusters.append(cluster)
            }
        }

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

    private static func byteSum(for asset: PHAsset) -> Int64 {
        var total: Int64 = 0
        for r in PHAssetResource.assetResources(for: asset) {
            if let n = r.value(forKey: "fileSize") as? CLongLong {
                total += Int64(n)
            }
        }
        return total
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
