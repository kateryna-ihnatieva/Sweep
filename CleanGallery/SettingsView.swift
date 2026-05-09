import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var gallery: GalleryViewModel

    @State private var resetStatsConfirm = false
    @State private var resetMonthsConfirm = false

    var body: some View {
        NavigationStack {
            List {
                feedbackSection
                safetySection
                appearanceSection
                resetSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                "Reset all stats?",
                isPresented: $resetStatsConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset stats", role: .destructive) {
                    gallery.resetStats()
                    Haptics.warn()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Lifetime totals on the Stats screen will go to zero. Your library is not touched.")
            }
            .confirmationDialog(
                "Reset month progress?",
                isPresented: $resetMonthsConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset progress", role: .destructive) {
                    gallery.resetMonthCompletion()
                    Haptics.warn()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All months become “not reviewed” again. Your library is not touched.")
            }
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        Section {
            Toggle(isOn: $settings.hapticsEnabled) {
                Label("Haptic feedback", systemImage: "hand.tap.fill")
            }
            .tint(settings.accentColor)
            .onChange(of: settings.hapticsEnabled) { _, isOn in
                if isOn { Haptics.selectionChanged() }
            }

            Toggle(isOn: $settings.videoAutoplayEnabled) {
                Label("Auto-play videos", systemImage: "play.rectangle.fill")
            }
            .tint(settings.accentColor)
        } header: {
            Text("Feedback")
        } footer: {
            Text("Haptics react to swipe, undo and successful deletions. Auto-play starts videos as soon as a card appears in the deck.")
        }
    }

    // MARK: Safety

    private var safetySection: some View {
        Section {
            Toggle(isOn: $settings.bigDeleteConfirmEnabled) {
                Label("Confirm large deletions", systemImage: "exclamationmark.shield.fill")
            }
            .tint(settings.accentColor)

            if settings.bigDeleteConfirmEnabled {
                Stepper(value: $settings.bigDeleteItemsThreshold, in: 5...500, step: 5) {
                    HStack {
                        Text("Ask if more than")
                        Spacer()
                        Text("\(settings.bigDeleteItemsThreshold) items")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Stepper(value: $settings.bigDeleteMegabytesThreshold, in: 50...10_000, step: 50) {
                    HStack {
                        Text("Ask if larger than")
                        Spacer()
                        Text("\(settings.bigDeleteMegabytesThreshold) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Safety")
        } footer: {
            Text("When either threshold is exceeded, Sweep adds an extra confirmation before sending items to Recently Deleted.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Accent color")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        accentSwatch(for: choice)
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Appearance")
        } footer: {
            Text("The chosen color tints buttons, progress bars, the active tab and accent badges across the app.")
        }
    }

    private func accentSwatch(for choice: AccentChoice) -> some View {
        let isSelected = settings.accentChoice == choice
        return Button {
            settings.accentChoice = choice
            Haptics.selectionChanged()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(choice.color.gradient)
                        .frame(width: 38, height: 38)
                        .shadow(color: choice.color.opacity(0.35), radius: 4, y: 2)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary.opacity(0.7) : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                Text(choice.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                resetStatsConfirm = true
            } label: {
                Label("Reset stats", systemImage: "chart.bar.xaxis")
            }

            Button(role: .destructive) {
                resetMonthsConfirm = true
            } label: {
                Label("Reset month progress", systemImage: "arrow.counterclockwise.circle")
            }
        } header: {
            Text("Reset")
        } footer: {
            Text("Neither action touches your photo library. Items deleted earlier remain in Recently Deleted as Photos manages them.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "app.badge")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Link(destination: URL(string: "https://github.com/kateryna-ihnatieva/Sweep")!) {
                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}
