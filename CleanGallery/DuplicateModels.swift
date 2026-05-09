import Foundation
import Photos

enum DuplicateKind: String, CaseIterable {
    /// Perceptual dHash clustering (exact + near match in time).
    case photoVisual
    /// Same resolution, duration (rounded), and file size (may include false positives).
    case videoHeuristic

    var listSectionTitle: String {
        switch self {
        case .photoVisual: return "Photo duplicates"
        case .videoHeuristic: return "Possible duplicate videos"
        }
    }

    var footnote: String {
        switch self {
        case .photoVisual:
            return "Perceptual hash (dHash) on a preview: finds same or very similar photos, including re-saves. A short time window catches copies taken apart; review groups before deleting."
        case .videoHeuristic:
            return "Matched by length, resolution, and file size only — review before deleting."
        }
    }
}

struct DuplicateGroup: Identifiable, Equatable {
    /// Stable id: content fingerprint for photos, hashed metadata key for videos.
    let id: String
    let kind: DuplicateKind
    let assets: [PHAsset]

    var count: Int { assets.count }
    var extraCount: Int { max(0, count - 1) }

    static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }
}
