# Sweep

Tinder-style cleanup for your iPhone photo library. Swipe through months, random samples, or duplicate sets — keep what matters, send the rest to *Recently Deleted*.

> Built in SwiftUI for iOS 17+. Uses PhotoKit only — nothing leaves your device.

---

## Features

- **Months view** — your library grouped by `Month Year`, with photo / video counts. Mark a month as cleaned when you’re done.
- **Swipe deck** — Tinder-style cards: swipe **left** to stage for deletion, **right** to keep. Inline video preview with sound and a real timeline. Big *Delete / Undo / Keep* buttons under the card for non-swipers.
- **Random 10** — quick daily cleanup with a random sample from the whole library.
- **Duplicates** —
  - **Photos**: identical preview fingerprint (perceptual hash on the system thumbnail).
  - **Videos**: heuristic by exact byte size + duration + native resolution.
- **Staged review** — nothing is deleted until you confirm. Items move to **Photos → Recently Deleted**, where iOS keeps them recoverable for the standard window.
- **Stats** — total photos / videos cleaned and bytes freed, persisted across launches.
- **Dark, minimal UI**. Portrait only.

## Requirements

- Xcode 15+ (project tested with Xcode 16.4 / iOS 18.5 SDK)
- iOS 17.0+ device or simulator
- A signed-in Apple Developer team for on-device runs (the project uses automatic signing)

## Getting started

```bash
git clone <this-repo>
cd "clean galery"
open CleanGallery.xcodeproj
```

In Xcode:

1. Select the **CleanGallery** scheme.
2. Pick a real device or simulator.
3. Hit **Run** (`⌘R`).

On first launch the app asks for **Photos access (read & write)**. Both *Full access* and *Limited access* work; with *Limited*, only the assets you allow are visible.

> Tip: in the simulator, drag a few photos and a video into the Photos app first — otherwise the library is empty and the deck has nothing to show.

## Project layout

```
CleanGallery/
├─ SweepApp.swift           // @main entry — wires GalleryViewModel
├─ MainTabView.swift        // Tab bar: Clean / Stats
├─ MonthListView.swift      // Months + duplicates entry card
├─ MonthCleanFlowView.swift // Per-month: swipe → review → result
├─ RandomCleanView.swift    // Random 10 flow
├─ SwipeDeckView.swift      // Card deck, gestures, video preview
├─ StagedReviewView.swift   // Confirm-before-delete grid
├─ DeletionSummaryView.swift
├─ DuplicateScanner.swift   // pHash for photos, heuristic for videos
├─ DuplicateFinderViewModel.swift
├─ DuplicateModels.swift
├─ DuplicatesViews.swift    // Entry card + sheet + per-group flow
├─ AssetThumbnailView.swift
├─ PHAssetImageView.swift   // UIImageView-backed PhotoKit loader
├─ GalleryViewModel.swift   // Auth, fetching, deletion, stats
├─ Models.swift
├─ AppTheme.swift           // Colors + PrimaryButtonStyle
└─ ByteFormatting.swift
```

The single source of truth for library state is `GalleryViewModel` (an `@MainActor ObservableObject`). PhotoKit fetching and deletion happen there; views observe the state.

## How deletion works

1. While swiping, items go into a `staged` `Set<String>` of `localIdentifier`s in the flow view.
2. The **Review** screen shows a grid of staged assets with quick *unstage* buttons.
3. **Confirm** runs `PHPhotoLibrary.shared().performChanges` with `PHAssetChangeRequest.deleteAssets(...)`. iOS shows the system confirmation; rejecting it surfaces an alert and nothing is removed.
4. On success, stats are updated and the months list refreshes.

Nothing is deleted permanently by Sweep — items land in **Recently Deleted** and follow Apple’s standard recovery window.

## Privacy

- All scanning, hashing, and deletion happens **on-device** via PhotoKit.
- The app does not have networking code of its own. PhotoKit may go to iCloud to fetch full assets you have stored there (`isNetworkAccessAllowed = true` so previews actually appear).
- No analytics, no third-party SDKs.

## Roadmap ideas

- Smart suggestions: blurry photos, screenshots, large videos
- Per-album mode in addition to per-month
- Batch confirm across multiple months
- iPad layout

## License

MIT — do whatever you want, attribution appreciated.
