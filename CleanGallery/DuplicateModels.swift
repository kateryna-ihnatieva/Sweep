import Foundation
import Photos

enum DuplicateKind: String, CaseIterable {
    /// Byte-identical photos (matching dimensions and total file size, then SHA-256 of the original resource).
    case photoVisual
    /// Byte-identical videos (matching resolution, duration, total file size, then SHA-256 of the original resource).
    case videoHeuristic

    var listSectionTitle: String {
        switch self {
        case .photoVisual: return "Identical photos"
        case .videoHeuristic: return "Identical videos"
        }
    }

    var footnote: String {
        switch self {
        case .photoVisual:
            return "Truly identical bytes only: matches dimensions and exact file size, then verifies with a SHA-256 hash of the original photo. Visually similar photos that were re-edited or re-encoded are not grouped here."
        case .videoHeuristic:
            return "Truly identical bytes only: matches resolution, duration, and exact file size, then verifies with a SHA-256 hash of the original video."
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
