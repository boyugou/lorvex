import Foundation
import LorvexWidgetViews
import SwiftUI
import WidgetKit

public struct LorvexFocusWidgetEntryView: View {
  private let entry: LorvexWidgetEntry

  public init(entry: LorvexWidgetEntry) {
    self.entry = entry
  }

  public var body: some View {
    LorvexWidgetView(model: entry.model)
      .redacted(reason: entry.isPlaceholder ? .placeholder : [])
      .widgetURL(widgetURL)
      .containerBackground(.background, for: .widget)
  }

  private var widgetURL: URL? {
    guard let urlString = entry.model.urlString else { return nil }
    return URL(string: urlString)
  }
}
