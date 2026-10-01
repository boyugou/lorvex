import LorvexCore
import SwiftUI

/// Why the watch has no Today list to show, with what to do about it and a
/// retry.
struct LorvexWatchErrorNote: View {
  @Bindable var store: LorvexWatchStore

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      Label(errorTitle, systemImage: errorSymbol)
        .font(LorvexDesign.Typography.secondaryText.weight(.medium))
        .foregroundStyle(LorvexDesign.Palette.error)
        .multilineTextAlignment(.center)
      Text(errorRemedy)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button {
        Task { await store.requestReplicaAndRefresh() }
      } label: {
        Label(String(
          localized: "watch.error.retry", defaultValue: "Retry",
          table: "Localizable", bundle: WatchL10n.bundle), systemImage: "arrow.clockwise")
      }
      .controlSize(.small)
      .accessibilityHint(String(
        localized: "watch.error.retry.hint", defaultValue: "Reloads Today from the snapshot or paired iPhone",
        table: "Localizable", bundle: WatchL10n.bundle))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(errorTitle). \(errorRemedy)")
  }

  // MARK: - Error classification (glance-friendly, with a remedy)

  /// True when the failure is a snapshot-unavailable error (the watch
  /// couldn't read its App Group data and typically needs the phone to
  /// publish a fresh snapshot), vs a generic load failure.
  private var errorIsSnapshotUnavailable: Bool {
    guard let snapshotError = store.error as? LorvexWatchSnapshotError else { return false }
    if case .unavailable = snapshotError { return true }
    return false
  }

  /// Short headline for the error banner.
  private var errorTitle: String {
    errorIsSnapshotUnavailable
      ? String(
        localized: "watch.error.unavailable.title", defaultValue: "Today unavailable",
        table: "Localizable", bundle: WatchL10n.bundle)
      : String(
        localized: "watch.error.load.title", defaultValue: "Couldn’t load Today",
        table: "Localizable", bundle: WatchL10n.bundle)
  }

  private var errorSymbol: String {
    errorIsSnapshotUnavailable ? "iphone.slash" : "exclamationmark.triangle"
  }

  /// What the user can do about it — a remedy, not a raw error string.
  private var errorRemedy: String {
    errorIsSnapshotUnavailable
      ? String(
        localized: "watch.error.unavailable.remedy", defaultValue: "Open Lorvex on your iPhone to sync, then retry.",
        table: "Localizable", bundle: WatchL10n.bundle)
      : String(
        localized: "watch.error.load.remedy", defaultValue: "Retry, or open Lorvex on your iPhone if this persists.",
        table: "Localizable", bundle: WatchL10n.bundle)
  }

}
