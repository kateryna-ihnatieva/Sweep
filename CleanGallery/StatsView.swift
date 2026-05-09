import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var gallery: GalleryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Statistics")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    statRow(title: "Total removed in app", value: "\(gallery.totalDeletedItems) items")
                    statRow(title: "Photos", value: "\(gallery.totalDeletedPhotos)")
                    statRow(title: "Videos", value: "\(gallery.totalDeletedVideos)")
                    statRow(title: "Estimated space freed", value: gallery.totalFreedBytes.formattedByteCount)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                )

                Text("Totals update after each confirmed deletion. iCloud copies and optimization can make on-device space differ from these estimates.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(20)
        }
        .background(AppTheme.background)
    }

    private func statRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}
