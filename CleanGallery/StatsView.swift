import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var gallery: GalleryViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Items removed")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(gallery.totalDeletedItems)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Space freed")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(gallery.totalFreedBytes.formattedByteCount)
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("All time")
                }

                Section {
                    StatRow(systemImage: "photo.fill", title: "Photos", value: "\(gallery.totalDeletedPhotos)", tint: AppTheme.accent)
                    StatRow(systemImage: "film.fill", title: "Videos", value: "\(gallery.totalDeletedVideos)", tint: AppTheme.accent)
                    StatRow(systemImage: "square.stack.3d.down.right.fill", title: "Total items", value: "\(gallery.totalDeletedItems)", tint: AppTheme.accent)
                } header: {
                    Text("Breakdown")
                }

                Section {
                    Label {
                        Text("Totals update after each confirmed deletion. iCloud copies and on-device storage optimization can make actual freed space differ from these estimates.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct StatRow: View {
    let systemImage: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .font(.callout.weight(.semibold))
            }
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
