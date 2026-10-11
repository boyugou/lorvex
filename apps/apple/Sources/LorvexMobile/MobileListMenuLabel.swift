import LorvexCore
import SwiftUI

/// A list as a menu item: its symbol beside its name, or its emoji before the
/// name, since a menu item draws only an image as its icon.
struct MobileListMenuLabel: View {
  let list: LorvexList

  var body: some View {
    if let emoji = list.icon, !emoji.isEmpty, !emoji.unicodeScalars.allSatisfy(\.isASCII) {
      Text(userContent: "\(emoji) \(list.displayName)")
    } else {
      Label {
        Text(userContent: list.displayName)
      } icon: {
        Image(systemName: LorvexSymbol.name(for: list.icon, fallback: "tray.fill"))
      }
    }
  }
}
