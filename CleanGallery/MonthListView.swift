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
            content
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showRandom = true
                        } label: {
                            Label("Random 10", systemImage: "shuffle")
                        }
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

    @ViewBuilder
    private var content: some View {
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

    private var listContent: some View {
        List {
            Section {
                DuplicatesEntryRow(viewModel: duplicateFinder, onBrowse: { showDuplicatesSheet = true })
            }

            if gallery.isLoading && gallery.months.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading…")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else if let err = gallery.loadError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if !gallery.months.isEmpty {
                Section {
                    ForEach(gallery.months) { month in
                        let reviewed = gallery.completedMonthIds.contains(month.id)
                        Button {
                            if reviewed {
                                pendingReopen = month
                            } else {
                                path = [month]
                            }
                        } label: {
                            monthRow(month, isReviewed: reviewed)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if reviewed {
                                Button {
                                    gallery.markMonthIncomplete(month.id)
                                } label: {
                                    Label("Reset", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.orange)
                            } else {
                                Button {
                                    gallery.markMonthCompleted(month.id)
                                } label: {
                                    Label("Reviewed", systemImage: "checkmark.seal.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .contextMenu {
                            if reviewed {
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
                } header: {
                    HStack {
                        Text("Months")
                        Spacer()
                        if reviewedCount > 0 {
                            Text("\(reviewedCount) of \(gallery.months.count) reviewed")
                                .textCase(nil)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await gallery.reloadMonths()
        }
    }

    private func monthRow(_ month: MonthBucket, isReviewed: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isReviewed ? AppTheme.accent.opacity(0.14) : AppTheme.accent.opacity(0.10))
                    .frame(width: 38, height: 38)
                Image(systemName: isReviewed ? "checkmark.seal.fill" : "calendar")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.accent)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(month.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isReviewed ? AppTheme.textSecondary : AppTheme.textPrimary)
                Text("\(month.photoCount) photos · \(month.videoCount) videos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isReviewed {
                Text("Reviewed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .opacity(isReviewed ? 0.7 : 1)
        .contentShape(Rectangle())
    }

    private var requestAccessView: some View {
        ContentUnavailableView {
            Label("Photos access", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Sweep reads your library on device to group items by month and help you swipe through clutter.")
        } actions: {
            Button("Allow access") {
                gallery.requestAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var accessDenied: some View {
        ContentUnavailableView {
            Label("Photos access is off", systemImage: "lock.fill")
        } description: {
            Text("Turn it on in Settings → Privacy & Security → Photos → Sweep.")
        }
    }
}
