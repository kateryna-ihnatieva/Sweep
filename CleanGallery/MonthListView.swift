import SwiftUI

struct MonthListView: View {
    @EnvironmentObject private var gallery: GalleryViewModel
    @StateObject private var duplicateFinder = DuplicateFinderViewModel()
    @State private var path: [MonthBucket] = []
    @State private var showRandom = false
    @State private var showDuplicatesSheet = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch gallery.authorization {
                case .authorized, .limited:
                    listContent
                case .denied, .restricted:
                    accessDenied
                case .notDetermined:
                    requestAccessView
                @unknown default:
                    requestAccessView
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRandom = true
                    } label: {
                        Label("Random 10", systemImage: "shuffle")
                    }
                    .buttonStyle(.plain)
                    .disabled(gallery.months.isEmpty || !(gallery.authorization == .authorized || gallery.authorization == .limited))
                }
            }
            .navigationDestination(for: MonthBucket.self) { month in
                MonthCleanFlowView(month: month)
            }
            .sheet(isPresented: $showRandom) {
                NavigationStack {
                    RandomCleanView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showRandom = false }
                            }
                        }
                }
                .environmentObject(gallery)
            }
            .sheet(isPresented: $showDuplicatesSheet) {
                DuplicatesSheetView()
                    .environmentObject(gallery)
                    .environmentObject(duplicateFinder)
            }
            .task {
                gallery.refreshAuthorization()
                if gallery.authorization == .authorized || gallery.authorization == .limited {
                    await gallery.reloadMonths()
                }
            }
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DuplicatesEntryCard(viewModel: duplicateFinder) {
                    showDuplicatesSheet = true
                }

                LazyVStack(spacing: 10) {
                    if gallery.isLoading && gallery.months.isEmpty {
                        ProgressView("Loading…")
                            .tint(AppTheme.accent)
                            .padding(40)
                    } else if let err = gallery.loadError {
                        Text(err)
                            .foregroundStyle(AppTheme.danger)
                            .padding()
                    }

                    ForEach(gallery.months) { month in
                        Button {
                            path = [month]
                        } label: {
                            monthRow(month)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if gallery.completedMonthIds.contains(month.id) {
                                Button("Mark not done", systemImage: "arrow.uturn.backward") {
                                    gallery.markMonthIncomplete(month.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await gallery.reloadMonths()
        }
        .background(AppTheme.background)
    }

    private func monthRow(_ month: MonthBucket) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(month.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(month.photoCount) photos · \(month.videoCount) videos")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if gallery.completedMonthIds.contains(month.id) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.title3)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                .fill(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
        )
    }

    private var requestAccessView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent)
            Text("Photos access")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Sweep reads your library on device to group items by month and help you swipe through clutter.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal)
            Button("Allow access") {
                gallery.requestAccess()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }

    private var accessDenied: some View {
        VStack(spacing: 16) {
            Text("Photos access is off")
                .font(.title3.weight(.semibold))
            Text("Turn it on in Settings → Privacy & Security → Photos → Sweep.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
