import SwiftUI
import WidgetKit
import LorvexWatch

/// Entry point for the Lorvex watch face complication extension.
///
/// Ships as a separate watchOS extension bundle so `LorvexWatchApp`'s `@main`
/// and this `@main WidgetBundle` do not collide.
@main
struct LorvexWatchComplicationBundle: WidgetBundle {
  var body: some Widget {
    LorvexWatchComplicationWidget()
  }
}
