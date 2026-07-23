import Foundation

public enum LorvexWatchQueueSelection {
  public static func clampedIndex(for crownPosition: Double, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let rounded = Int(crownPosition.rounded())
    return min(max(rounded, 0), count - 1)
  }

  public static func clampedPosition(_ crownPosition: Double, count: Int) -> Double {
    Double(clampedIndex(for: crownPosition, count: count))
  }

  public static func accessibilityLabel(title: String, selectedIndex: Int, count: Int) -> String {
    String(
      format: String(
        localized: "watch.task.next.position_a11y", defaultValue: "Next focus task %lld of %lld: %@",
        table: "Localizable", bundle: WatchL10n.bundle),
      selectedIndex + 1,
      count,
      title
    )
  }
}
