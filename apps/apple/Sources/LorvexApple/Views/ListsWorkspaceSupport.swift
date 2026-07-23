import LorvexCore
import SwiftUI

enum ListsWorkspaceScope: String, CaseIterable, Identifiable {
  case all
  case active
  case complete

  var id: Self { self }

  func includes(_ list: LorvexList) -> Bool {
    switch self {
    case .all:
      true
    case .active:
      list.openCount > 0
    case .complete:
      list.totalCount > 0 && list.openCount == 0
    }
  }

  var title: String {
    switch self {
    case .all:
      String(localized: "lists.scope.all", defaultValue: "All", table: "Localizable", bundle: LorvexL10n.bundle)
    case .active:
      String(localized: "lists.scope.active", defaultValue: "Open", table: "Localizable", bundle: LorvexL10n.bundle)
    case .complete:
      String(localized: "lists.scope.complete", defaultValue: "Done", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var systemImage: String {
    switch self {
    case .all:
      return "folder"
    case .active:
      return "circle"
    case .complete:
      return "checkmark.circle.fill"
    }
  }

  var emptyTitle: String {
    switch self {
    case .all:
      String(localized: "lists.empty.no_lists_title", defaultValue: "No Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case .active:
      String(localized: "lists.empty.no_active_title", defaultValue: "No Open Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case .complete:
      String(localized: "lists.empty.no_complete_title", defaultValue: "No Finished Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var emptyDescription: String {
    switch self {
    case .all:
      String(
        localized: "lists.empty.no_lists_description",
        defaultValue: "Lists will appear here once they're created.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .active:
      String(
        localized: "lists.empty.no_active_description",
        defaultValue: "Lists with open tasks will appear here.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .complete:
      String(
        localized: "lists.empty.no_complete_description",
        defaultValue: "Lists with every task complete will appear here.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }
}
