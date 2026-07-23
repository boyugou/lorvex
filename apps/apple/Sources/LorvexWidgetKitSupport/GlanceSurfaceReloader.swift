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
  private let reloadFocusControl: @Sendable () -> Void

  public init(
    reloadWidgetTimelines: @escaping @Sendable () -> Void,
    reloadFocusControl: @escaping @Sendable () -> Void
  ) {
    self.reloadWidgetTimelines = reloadWidgetTimelines
    self.reloadFocusControl = reloadFocusControl
  }

  public func reloadAll() {
    reloadWidgetTimelines()
    reloadFocusControl()
  }

  /// Production WidgetKit invalidation. Control widgets are unavailable on
  /// visionOS and require newer OS releases than ordinary widgets elsewhere.
  public static let live = GlanceSurfaceReloader(
    reloadWidgetTimelines: {
      #if os(visionOS)
        if #available(visionOS 26.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
      #else
        WidgetCenter.shared.reloadAllTimelines()
      #endif
    },
    reloadFocusControl: {
      #if !os(visionOS)
        if #available(iOS 18.0, macOS 26.0, watchOS 26.0, *) {
          ControlCenter.shared.reloadControls(ofKind: LorvexProductMetadata.controlWidgetKind)
        }
      #endif
    })
}
