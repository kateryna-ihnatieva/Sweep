import SwiftUI

struct MonthListView: View {
    @EnvironmentObject private var gallery: GalleryViewModel
    @StateObject private var duplicateFinder = DuplicateFinderViewModel()
    @State private var path: [MonthBucket] = []
    @State private var showRandom = false
    @State private var showDuplicatesSheet = false
    @State private var pendingReopen: MonthBucket?

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
            .confirmationDialog(
                pendingReopen.map { "“\($0.title)” is already reviewed" } ?? "Open this month?",
                isPresented: Binding(
                    get: { pendingReopen != nil },
                    set: { if !$0 { pendingReopen = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingReopen
            ) { month in
                Button("Open anyway") {
                    let target = month
                    pendingReopen = nil
                    path = [target]
                }
                Button("Mark not done", role: .destructive) {
                    gallery.markMonthIncomplete(month.id)
                    pendingReopen = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingReopen = nil
                }
            } message: { _ in
                Text("You’ve already swiped through this month. Open it again only if you want to revisit it.")
            }
            .task {
                gallery.refreshAuthorization()
                if gallery.authorization == .authorized || gallery.authorization == .limited {
                    await gallery.reloadMonths()
                }
            }
        }
    }

    private var reviewedCount: Int {
        gallery.months.reduce(0) { acc, m in acc + (gallery.completedMonthIds.contains(m.id) ? 1 : 0) }
    }

    private var listContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DuplicatesEntryCard(viewModel: duplicateFinder) {
                    showDuplicatesSheet = true
                }

                if gallery.isLoading && gallery.months.isEmpty {
                    ProgressView("Loading…")
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else if let err = gallery.loadError {
                    Text(err)
                        .foregroundStyle(AppTheme.danger)
                        .padding()
                }

                if !gallery.months.isEmpty {
                    monthsHeader
                    LazyVStack(spacing: 10) {
                        ForEach(gallery.months) { month in
                            monthButton(month, isReviewed: gallery.completedMonthIds.contains(month.id))
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

    private var monthsHeader: some View {
        HStack(spacing: 8) {
            Text("MONTHS")
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            if reviewedCount > 0 {
                Text("\(reviewedCount) of \(gallery.months.count) reviewed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.16), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }

    private func monthButton(_ month: MonthBucket, isReviewed: Bool) -> some View {
        Button {
            if isReviewed {
                pendingReopen = month
            } else {
                path = [month]
            }
        } label: {
            monthRow(month, isReviewed: isReviewed)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isReviewed {
                Button("Mark not done", systemImage: "arrow.uturn.backward") {
                    gallery.markMonthIncomplete(month.id)
                }
                Button("Open anyway", systemImage: "chevron.right") {
                    path = [month]
                }
            } else {
                Button("Mark as reviewed", systemImage: "checkmark.seal") {
                    gallery.markMonthCompleted(month.id)
                }
            }
        }
    }

    private func monthRow(_ month: MonthBucket, isReviewed: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(month.title)
                    .font(.headline)
                    .foregroundStyle(isReviewed ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .strikethrough(isReviewed, color: AppTheme.textSecondary.opacity(0.6))
                Text("\(month.photoCount) photos · \(month.videoCount) videos")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary.opacity(isReviewed ? 0.7 : 1))
            }
            Spacer()
            if isReviewed {
                reviewedBadge
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(isReviewed ? 0.35 : 0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                .fill(isReviewed ? AppTheme.surface.opacity(0.55) : AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.listRowCorner, style: .continuous)
                        .stroke(isReviewed ? AppTheme.border.opacity(0.5) : AppTheme.border, lineWidth: 1)
                }
        )
        .opacity(isReviewed ? 0.78 : 1)
    }

    private var reviewedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
            Text("Reviewed")
                .font(.caption2.weight(.bold))
                .tracking(0.4)
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.accent.opacity(0.16), in: Capsule())
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
