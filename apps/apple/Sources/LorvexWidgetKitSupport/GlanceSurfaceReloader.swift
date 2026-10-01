import LorvexCore
import WidgetKit

/// Invalidates every installed glance surface that reads the shared widget
/// snapshot.
///
/// Widget timelines and Control Center controls use separate WidgetKit reload
/// APIs. Keeping both calls here prevents a publisher from refreshing one
/// surface while leaving the other on an older snapshot.
public struct GlanceSurfaceReloader: Sendable {
  private let reloadWidgetTimelines: @Sendable () -> Void
  private let reloadTodayControl: @Sendable () -> Void

  public init(
    reloadWidgetTimelines: @escaping @Sendable () -> Void,
    reloadTodayControl: @escaping @Sendable () -> Void
  ) {
    self.reloadWidgetTimelines = reloadWidgetTimelines
    self.reloadTodayControl = reloadTodayControl
  }

  public func reloadAll() {
    reloadWidgetTimelines()
    reloadTodayControl()
  }

  /// Production WidgetKit invalidation: every widget timeline, then the Today
  /// control.
  public static let live = GlanceSurfaceReloader(
    reloadWidgetTimelines: {
      WidgetCenter.shared.reloadAllTimelines()
    },
    reloadTodayControl: {
      if #available(iOS 18.0, macOS 26.0, watchOS 26.0, *) {
        ControlCenter.shared.reloadControls(ofKind: LorvexProductMetadata.controlWidgetKind)
      }
    })
}
