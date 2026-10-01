import SwiftUI
import WidgetKit

/// The always-available widgets vended by the Lorvex `@main WidgetBundle`
/// host, in display order.
///
/// `LorvexWidgetBundle` (the bundle the app embeds and ships as the widget
/// extension) composes this set plus the availability-gated
/// `LorvexTodayControlWidget`.
///
/// The `if #available(iOS 18.0, macOS 26.0, *)` branch adding
/// `LorvexTodayControlWidget` must live in the `@main` host module, never
/// here: `WidgetBundleBuilder.buildOptional` is `@_alwaysEmitIntoClient` and
/// its opaque return type stays runtime-conditional (its own body branches on
/// `#available`), so the opaque type descriptor is emitted only as a hidden
/// symbol in the module that instantiates it. If the branch lived in this
/// framework, a Release-optimized client seeing through this function's opaque
/// return would reference that hidden descriptor across the framework boundary
/// and the widget appex would fail to link.
///
/// `@MainActor` because every caller composes this inside a `WidgetBundle.body`,
/// which is itself main-actor-isolated, and `Widget`'s inferred main-actor
/// isolation extends to its conforming types' initializers.
@MainActor
@WidgetBundleBuilder
public func lorvexWidgets() -> some Widget {
  LorvexTodayWidget()
  LorvexProgressWidget()
  LorvexHabitsWidget()
}
