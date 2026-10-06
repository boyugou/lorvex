import LorvexWidgetExtension
import SwiftUI
import WidgetKit

@main
struct LorvexWidgetBundle: WidgetBundle {
  var body: some Widget {
    lorvexWidgets()
    // The control widget is composed here, in the @main module, rather than
    // inside lorvexWidgets(): the #available branch instantiates
    // WidgetBundleBuilder.buildOptional, whose opaque type descriptor is a
    // hidden @_alwaysEmitIntoClient symbol that must not cross a framework
    // boundary (see the lorvexWidgets() docstring).
    if #available(iOS 18.0, macOS 26.0, *) {
      LorvexTodayControlWidget()
      #if os(iOS)
        LorvexCaptureControlWidget()
      #endif
    }
  }
}
