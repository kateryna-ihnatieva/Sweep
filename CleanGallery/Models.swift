import Foundation
import Photos

/// Returned after a confirmed delete so UI can show photo vs video breakdown.
struct DeletionCommitResult: Equatable {
    var freedBytes: Int64
    var photoCount: Int
    var videoCount: Int

    var totalCount: Int { photoCount + videoCount }

    static let empty = DeletionCommitResult(freedBytes: 0, photoCount: 0, videoCount: 0)
}

struct MonthBucket: Identifiable {
    let id: String
    let sortDate: Date
    let title: String
    let assets: [PHAsset]

    var photoCount: Int { assets.filter { $0.mediaType == .image }.count }
    var videoCount: Int { assets.filter { $0.mediaType == .video }.count }
}

extension MonthBucket: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MonthBucket, rhs: MonthBucket) -> Bool {
        lhs.id == rhs.id
    }
}
