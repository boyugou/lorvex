import LorvexCore
import LorvexSystemIntents
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func appShortcutsExposeStableSystemImages() {
  #expect(
    LorvexShortcutDescriptor.allCases.map(\.systemImageName) == [
      "plus",
      "sun.max",
      "rectangle.3.group",
      "checkmark.circle",
      "calendar.badge.clock",
      "scope",
      "list.bullet.rectangle",
      "text.magnifyingglass",
      "repeat.circle",
      "calendar.badge.checkmark",
    ])
}
