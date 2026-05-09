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
            VStack(spacing: 0) {
                if hasDeletions {
                    successLayout
                } else {
                    emptyLayout
                }

                Button(action: onDone) {
                    Text(doneButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }

    // MARK: - Removed something

    private var successLayout: some View {
        VStack(spacing: 0) {
            Text("Done")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.accent.opacity(0.18), in: Capsule())
                .padding(.top, 20)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.accent.opacity(0.38), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 76
                        )
                    )
                    .frame(width: 132, height: 132)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            Text("Removed from this session")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textPrimary)

            Text(breakdownLine)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 6)
                .padding(.horizontal, 8)

            HStack(spacing: 10) {
                pillStat(title: "Photos", value: "\(result.photoCount)", systemImage: "photo")
                pillStat(title: "Videos", value: "\(result.videoCount)", systemImage: "film")
                pillStat(title: "Total", value: "\(result.totalCount)", systemImage: "square.stack.3d.down.right")
            }
            .padding(.top, 20)
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.badge.icloud")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent.opacity(0.9))
                (
                    Text("Estimated ")
                        + Text(result.freedBytes.formattedByteCount).fontWeight(.semibold).foregroundStyle(AppTheme.textPrimary.opacity(0.95))
                        + Text(" freed on this device. iCloud and Optimize Storage can change the real number.")
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
            )
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.keep.opacity(0.95))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Deleted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Items remain in the Photos app under Recently Deleted for the period Apple allows. You can put them back from there.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surfaceElevated.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
            )
            .padding(.bottom, 20)

            if let monthCompletion {
                monthProgressCard(binding: monthCompletion)
            }
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

    private func pillStat(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
        )
    }

    // MARK: - Nothing removed

    private var emptyLayout: some View {
        VStack(spacing: 0) {
            Text("All clear")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.surfaceElevated, in: Capsule())
                .padding(.top, 24)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.textSecondary.opacity(0.28), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 72
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.top, 18)
            .padding(.bottom, 10)

            Text("Nothing was deleted")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textPrimary)

            Text("You didn’t confirm any removals (or the list was already empty). Your originals stay in the library.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 8)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                emptyBullet(icon: "arrow.left.arrow.right", text: "Swipe again to mark items, then confirm on the review screen.")
                emptyBullet(icon: "hand.tap", text: "Use Delete / Keep below the card if you prefer taps over swipes.")
                emptyBullet(icon: "arrow.uturn.backward", text: "Undo steps back one decision while you’re still on the deck.")
            }
            .padding(.top, 22)
            .padding(.bottom, 8)

            if let monthCompletion {
                monthProgressCard(binding: monthCompletion)
                    .padding(.top, 12)
            }
        }
    }

    private func emptyBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared month card

    private func monthProgressCard(binding: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Toggle("Mark this month as cleaned", isOn: binding)
                .font(.body.weight(.medium))
                .tint(AppTheme.accent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
        )
        .padding(.bottom, 8)
    }
}
