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

    // MARK: - Photo clusters (perceptual dHash + union–find)

    /// Groups visually similar photos: exact 64-bit dHash matches anywhere, plus near-matches (Hamming) within a time window.
    static func clusterPhotos(
        _ assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async -> [DuplicateGroup] {
        guard !assets.isEmpty else { return [] }

        struct Row {
            let asset: PHAsset
            let hash: UInt64
        }

        let batchSize = 24
        var rows: [Row] = []
        rows.reserveCapacity(assets.count)
        var processed = 0
        let total = assets.count

        while processed < total {
            let end = min(processed + batchSize, total)
            let slice = Array(assets[processed..<end])
            await withTaskGroup(of: Row?.self) { group in
                for a in slice {
                    group.addTask {
                        guard a.mediaType == .image else { return nil }
                        guard let image = await requestSquareThumbnail(asset: a, pixelLength: 200) else { return nil }
                        let hashOpt: UInt64? = await MainActor.run { dHash64(from: image) }
                        guard let h = hashOpt else { return nil }
                        return Row(asset: a, hash: h)
                    }
                }
                for await row in group {
                    if let row { rows.append(row) }
                }
            }
            processed = end
            progress(Double(processed) / Double(total))
        }

        guard !rows.isEmpty else { return [] }

        let n = rows.count
        var uf = UnionFind(count: n)

        var firstIndex: [UInt64: Int] = [:]
        for i in 0..<n {
            let h = rows[i].hash
            if let j = firstIndex[h] {
                uf.union(i, j)
            } else {
                firstIndex[h] = i
            }
        }

        let nearHammingMax = 11
        let dateWindow = 100
        let order = (0..<n).sorted {
            (rows[$0].asset.creationDate ?? .distantPast) < (rows[$1].asset.creationDate ?? .distantPast)
        }
        for p in 0..<order.count {
            let i = order[p]
            let upper = min(p + dateWindow, order.count)
            for q in (p + 1)..<upper {
                let j = order[q]
                if hamming(rows[i].hash, rows[j].hash) <= nearHammingMax {
                    uf.union(i, j)
                }
            }
        }

        var buckets: [Int: [PHAsset]] = [:]
        for i in 0..<n {
            let r = uf.find(i)
            buckets[r, default: []].append(rows[i].asset)
        }

        return buckets.values
            .filter { $0.count >= 2 }
            .map { list in
                let sorted = list.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
                let seed = sorted.map(\.localIdentifier).sorted().joined(separator: "|")
                let idBody = sha256hex(Data(seed.utf8))
                return DuplicateGroup(id: "p_\(idBody)", kind: .photoVisual, assets: sorted)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.id < rhs.id
            }
    }

    // MARK: - Video clusters (sorted metadata, stricter than before)

    static func clusterVideosWeak(
        _ assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async -> [DuplicateGroup] {
        guard !assets.isEmpty else { return [] }

        let sorted = assets.sorted { a, b in
            if a.pixelWidth != b.pixelWidth { return a.pixelWidth < b.pixelWidth }
            if a.pixelHeight != b.pixelHeight { return a.pixelHeight < b.pixelHeight }
            let da = Int((a.duration * 1000).rounded())
            let db = Int((b.duration * 1000).rounded())
            if da != db { return da < db }
            return byteSum(for: a) < byteSum(for: b)
        }

        var clusters: [[PHAsset]] = []
        var cur: [PHAsset] = []
        for (idx, a) in sorted.enumerated() {
            if let prev = cur.last, videoMetadataMatch(prev, a) {
                cur.append(a)
            } else {
                if cur.count >= 2 { clusters.append(cur) }
                cur = [a]
            }
            if idx % 50 == 0 || idx == sorted.count - 1 {
                progress(Double(idx + 1) / Double(sorted.count))
            }
        }
        if cur.count >= 2 { clusters.append(cur) }

        return clusters.map { list in
            let sortedList = list.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            let seed = sortedList.map(\.localIdentifier).sorted().joined(separator: "|")
            let idBody = sha256hex(Data(seed.utf8))
            return DuplicateGroup(id: "v_\(idBody)", kind: .videoHeuristic, assets: sortedList)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Private

    private static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// 64-bit difference hash (9×8 luminance gradient). Uses `UIImage.draw` so EXIF orientation is applied.
    private static func dHash64(from image: UIImage) -> UInt64? {
        let w = 9
        let h = 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let tiny = renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: w, height: h)).fill()
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let cg = tiny.cgImage else { return nil }

        let bytesPerPixel = 4
        let rowBytes = w * bytesPerPixel
        var data = [UInt8](repeating: 0, count: rowBytes * h)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .default
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        func lum(_ x: Int, _ y: Int) -> Int {
            let o = y * rowBytes + x * bytesPerPixel
            let r = Int(data[o])
            let g = Int(data[o + 1])
            let b = Int(data[o + 2])
            return (299 * r + 587 * g + 114 * b) / 1000
        }

        var hash: UInt64 = 0
        var bit = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                if lum(x, y) > lum(x + 1, y) {
                    hash |= (1 << bit)
                }
                bit += 1
            }
        }
        return hash
    }

    private static func requestSquareThumbnail(asset: PHAsset, pixelLength: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
            var result: UIImage?
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = true
            let target = CGSize(width: pixelLength, height: pixelLength)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: opts
            ) { image, _ in
                result = image
            }
            return result
        }.value
    }

    fileprivate static func sha256hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func byteSum(for asset: PHAsset) -> Int64 {
        var total: Int64 = 0
        for r in PHAssetResource.assetResources(for: asset) {
            if let n = r.value(forKey: "fileSize") as? CLongLong {
                total += Int64(n)
            }
        }
        return total
    }

    private static func videoMetadataMatch(_ a: PHAsset, _ b: PHAsset) -> Bool {
        guard a.pixelWidth == b.pixelWidth, a.pixelHeight == b.pixelHeight else { return false }
        let da = Int((a.duration * 1000).rounded())
        let db = Int((b.duration * 1000).rounded())
        guard abs(da - db) <= 80 else { return false }

        let sa = byteSum(for: a)
        let sb = byteSum(for: b)
        if sa > 0, sb > 0 {
            let diff = abs(sa - sb)
            let mx = max(sa, sb)
            return diff <= max(393_216, mx / 256)
        }
        return sa == 0 && sb == 0
    }
}

// MARK: - Union–find (Hamming clusters)

private struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ i: Int) -> Int {
        if parent[i] != i {
            parent[i] = find(parent[i])
        }
        return parent[i]
    }

    mutating func union(_ i: Int, _ j: Int) {
        var ri = find(i)
        var rj = find(j)
        if ri == rj { return }
        if rank[ri] < rank[rj] {
            swap(&ri, &rj)
        }
        parent[rj] = ri
        if rank[ri] == rank[rj] {
            rank[ri] += 1
        }
    }
}
