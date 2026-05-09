import SwiftUI

/// Polished post-delete screen: distinct layouts when something was removed vs when nothing was.
struct DeletionSummaryView: View {
    let result: DeletionCommitResult
    /// When non-nil, shows the month-cleaned toggle (month flow only).
    var monthCompletion: Binding<Bool>?
    let doneButtonTitle: String
    let onDone: () -> Void

    private var hasDeletions: Bool { result.totalCount > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if hasDeletions {
                    successLayout
                } else {
                    emptyLayout
                }

                if let monthCompletion {
                    monthProgressCard(binding: monthCompletion)
                }

                Button(action: onDone) {
                    Text(doneButtonTitle)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }

    // MARK: - Removed something

    private var successLayout: some View {
        VStack(spacing: 0) {
            badge(text: "Done", systemImage: "checkmark", tint: AppTheme.accent)
                .padding(.bottom, 4)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.accent.opacity(0.32), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 132, height: 132)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 8)
            .padding(.bottom, 6)

            Text("Removed from this session")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(breakdownLine)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack(spacing: 10) {
                pillStat(title: "Photos", value: "\(result.photoCount)", systemImage: "photo.fill")
                pillStat(title: "Videos", value: "\(result.videoCount)", systemImage: "film.fill")
                pillStat(title: "Total", value: "\(result.totalCount)", systemImage: "square.stack.3d.down.right.fill")
            }
            .padding(.top, 18)

            infoCard(
                icon: "externaldrive.badge.icloud",
                tint: AppTheme.accent
            ) {
                (
                    Text("Estimated ")
                        + Text(result.freedBytes.formattedByteCount)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        + Text(" freed on this device. iCloud and Optimize Storage can change the real number.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            }
            .padding(.top, 14)

            infoCard(
                icon: "arrow.uturn.backward.circle.fill",
                tint: AppTheme.keep
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Deleted")
                        .font(.subheadline.weight(.semibold))
                    Text("Items remain in the Photos app under Recently Deleted for the period Apple allows. You can put them back from there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        }
    }

    private var breakdownLine: String {
        var parts: [String] = []
        if result.photoCount > 0 {
            parts.append("\(result.photoCount) photo\(result.photoCount == 1 ? "" : "s")")
        }
        if result.videoCount > 0 {
            parts.append("\(result.videoCount) video\(result.videoCount == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "\(result.totalCount) items" }
        return parts.joined(separator: " · ")
    }

    private func badge(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private func pillStat(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func infoCard<Content: View>(
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Nothing removed

    private var emptyLayout: some View {
        VStack(spacing: 0) {
            badge(text: "All clear", systemImage: "sparkles", tint: .secondary)
                .padding(.bottom, 4)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.secondary.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 72
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Text("Nothing was deleted")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text("You didn’t confirm any removals (or the list was already empty). Your originals stay in the library.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                emptyBullet(icon: "arrow.left.arrow.right", text: "Swipe again to mark items, then confirm on the review screen.")
                emptyBullet(icon: "hand.tap", text: "Use Delete / Keep below the card if you prefer taps over swipes.")
                emptyBullet(icon: "arrow.uturn.backward", text: "Undo steps back one decision while you’re still on the deck.")
            }
            .padding(.top, 18)
            .padding(.horizontal, 4)
        }
    }

    private func emptyBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared month card

    private func monthProgressCard(binding: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESS")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Toggle("Mark this month as cleaned", isOn: binding)
                .font(.body.weight(.medium))
                .tint(AppTheme.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
