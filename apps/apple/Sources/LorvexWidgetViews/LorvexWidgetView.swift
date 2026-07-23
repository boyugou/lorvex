import LorvexWidgetKitSupport
import SwiftUI

public struct LorvexWidgetView: View {
  private let model: WidgetRenderModel

  public init(model: WidgetRenderModel) {
    self.model = model
  }

  public var body: some View {
    switch model.family {
    case .accessoryInline:
      AccessoryInlineWidgetView(model: model)
    case .accessoryRectangular:
      AccessoryRectangularWidgetView(model: model)
    case .accessoryCircular:
      AccessoryCircularWidgetView(model: model)
    case .systemSmall:
      SmallSystemWidgetView(model: model)
    case .systemMedium:
      SystemWidgetView(model: model, layout: .medium)
    case .systemLarge:
      SystemWidgetView(model: model, layout: .large)
    }
  }
}
