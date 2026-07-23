import LorvexWidgetExtension
import SwiftUI
import WidgetKit

/// Standalone `@main` widget host for the `LorvexFocusWidget` executable product.
///
/// It vends the same widgets as `LorvexWidgetBundle`: the shared
/// `lorvexWidgets()` set plus the availability-gated control widget, so
/// building this product yields a working widget extension rather than an
/// empty appex. The shipped macOS/iOS extension is built from
/// `LorvexWidgetBundle`; keeping this product correct means a packaging step
/// that builds the widget by its `LorvexFocusWidget` product name cannot
/// accidentally ship a widgetless bundle.
@main
struct LorvexFocusWidgetBundle: WidgetBundle {
  var body: some Widget {
    lorvexWidgets()
    // The control widget is composed here, in the @main module, rather than
    // inside lorvexWidgets(): the #available branch instantiates
    // WidgetBundleBuilder.buildOptional, whose opaque type descriptor is a
    // hidden @_alwaysEmitIntoClient symbol that must not cross a framework
    // boundary (see the lorvexWidgets() docstring). Keep this block identical
    // to LorvexWidgetBundle's so both hosts vend the same widget set.
    if #available(iOS 18.0, macOS 26.0, *) {
      LorvexFocusControlWidget()
    }
  }
}
