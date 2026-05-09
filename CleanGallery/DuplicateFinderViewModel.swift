import Combine
import Foundation

@MainActor
final class DuplicateFinderViewModel: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var photoGroups: [DuplicateGroup] = []
    @Published private(set) var videoGroups: [DuplicateGroup] = []
    @Published private(set) var lastScanAt: Date?
    @Published var errorMessage: String?

    private var groupById: [String: DuplicateGroup] = [:]

    var hasResults: Bool { !(photoGroups.isEmpty && videoGroups.isEmpty) }

    var totalDuplicateItems: Int {
        photoGroups.reduce(0) { $0 + $1.count } + videoGroups.reduce(0) { $0 + $1.count }
    }

    var totalExtraCopies: Int {
        photoGroups.reduce(0) { $0 + $1.extraCount } + videoGroups.reduce(0) { $0 + $1.extraCount }
    }

    func group(id: String) -> DuplicateGroup? {
        groupById[id]
    }

    func scanLibrary() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        progress = 0
        defer {
            isScanning = false
            progress = 1
        }

        let images = await DuplicateScanner.fetchAssets(mediaType: .image)
        let photo = await DuplicateScanner.clusterPhotos(images) { [weak self] p in
            Task { @MainActor in self?.progress = p * 0.82 }
        }

        let videos = await DuplicateScanner.fetchAssets(mediaType: .video)
        let vid = await DuplicateScanner.clusterVideosWeak(videos) { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.progress = 0.82 + p * 0.18
            }
        }

        photoGroups = photo
        videoGroups = vid
        groupById = Dictionary(
            uniqueKeysWithValues: (photo + vid).map { ($0.id, $0) }
        )
        lastScanAt = Date()
    }

    func clearResults() {
        photoGroups = []
        videoGroups = []
        groupById = [:]
        lastScanAt = nil
        progress = 0
    }
}
