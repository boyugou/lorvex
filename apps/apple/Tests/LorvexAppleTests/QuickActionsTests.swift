import LorvexCore
import Testing

@testable import LorvexApple

// MARK: - Catalog stability

@Test
func quickActionCatalogIdentifiersAreStable() {
  // Type identifiers are embedded in Info.plist and must never change without
  // a coordinated plist update.
  #expect(LorvexQuickAction.quickCapture.typeIdentifier == "com.lorvex.apple.quickCapture")
  #expect(LorvexQuickAction.openToday.typeIdentifier == "com.lorvex.apple.openToday")
}

@Test
func quickActionCatalogOrderIsStable() {
  // Order determines the sequence shown in the Dock menu and Home Screen
  // long-press list. Changes here require a coordinated UX review.
  #expect(
    LorvexQuickAction.allCases == [.quickCapture, .openToday]
  )
}

@Test
func quickActionCatalogTitlesMatchDesignSpec() {
  #expect(LorvexQuickAction.quickCapture.localizedTitle == "Quick Capture")
  #expect(LorvexQuickAction.openToday.localizedTitle == "Open Today")
}

@Test
func quickActionCatalogSymbolNamesAreNonEmpty() {
  for action in LorvexQuickAction.allCases {
    #expect(!action.systemImageName.isEmpty, "systemImageName must not be empty for \(action)")
  }
}

@Test
func quickActionInitFromTypeIdentifierRoundTrips() {
  for action in LorvexQuickAction.allCases {
    let reconstructed = LorvexQuickAction(typeIdentifier: action.typeIdentifier)
    #expect(reconstructed == action)
  }
  #expect(LorvexQuickAction(typeIdentifier: "invalid.unknown") == nil)
}

@Test
func quickActionDeepLinkURLsAreValidLorvexSchemeURLs() {
  for action in LorvexQuickAction.allCases {
    let url = action.deepLinkURL
    #expect(url.scheme == "lorvex", "Expected lorvex scheme for \(action)")
    #expect(url.host() != nil, "Deep-link URL must have a host for \(action)")
  }
}

@Test
func quickActionsMapToStableAppleCommandActions() {
  #expect(LorvexQuickAction.quickCapture.commandAction == .appCommand(.focusQuickAdd))
  #expect(LorvexQuickAction.openToday.commandAction == .openWindow(.today))
}

@Test
func quickActionDockFallbackDeepLinksAreValidLorvexURLs() {
  for action in LorvexQuickAction.allCases {
    let url = action.dockFallbackDeepLink
    #expect(url.scheme == "lorvex", "Expected lorvex scheme for \(action)")
    #expect(LorvexDeepLinkRoute(url: url) != nil, "Expected routable fallback URL for \(action)")
  }
}

// MARK: - macOS Dock menu builder

#if os(macOS)
  import AppKit

  @Test @MainActor
  func dockMenuBuilderReturnsItemsInCatalogOrder() {
    var received: [LorvexQuickAction] = []
    let menu = LorvexDockMenuBuilder.build { action in
      received.append(action)
    }
    #expect(menu.items.count == LorvexQuickAction.allCases.count)
    #expect(menu.items.map(\.title) == LorvexQuickAction.allCases.map(\.localizedTitle))
  }

  @Test @MainActor
  func dockMenuBuilderItemsHaveSymbolImages() {
    let menu = LorvexDockMenuBuilder.build { _ in }
    for item in menu.items {
      #expect(item.image != nil, "Each Dock menu item must carry an SF Symbol image")
    }
  }

  @Test @MainActor
  func dockMenuBuilderDispatchesCorrectActionPerItem() {
    var dispatched: [LorvexQuickAction] = []
    let menu = LorvexDockMenuBuilder.build { action in
      dispatched.append(action)
    }
    // Fire each item's action by messaging its target directly.
    for item in menu.items {
      if let target = item.target, let sel = item.action {
        _ = target.perform(sel)
      }
    }
    #expect(dispatched == LorvexQuickAction.allCases)
  }
#endif
