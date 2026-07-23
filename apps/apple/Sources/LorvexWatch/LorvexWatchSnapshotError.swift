import Foundation
import LorvexWidgetKitSupport

public enum LorvexWatchSnapshotError: LocalizedError, Equatable, Sendable {
  case unavailable(WidgetSnapshotFallback)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let fallback):
      String(
        format: String(
          localized: "watch.error.snapshot_unavailable", defaultValue: "Focus snapshot unavailable: %@",
          table: "Localizable", bundle: WatchL10n.bundle),
        LorvexWatchStore.snapshotUnavailableStatusText(fallback))
    }
  }
}
