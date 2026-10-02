import AppIntents
import Foundation
import LorvexCore

struct ReadLorvexListHealthIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.health.read.title", defaultValue: "Find Lorvex Lists with Overdue Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.health.read.description", defaultValue: "Find the Lorvex lists that have overdue tasks, and how many each has.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  /// Returns the lists with overdue tasks, most overdue first; Siri names
  /// each with its count of overdue tasks.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexListEntity]> & ProvidesDialog {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let health = try await LorvexTaskIntentRunner.readListHealth(core: core)
    let catalog = try await LorvexTaskIntentRunner.readLists(core: core).lists
    let overdue = Self.listsWithOverdueTasks(health: health.lists, catalog: catalog)
    guard !overdue.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.list.health.read.none_dialog",
            defaultValue: "No list has overdue tasks.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let items = overdue.map { entry in
      String(
        localized: "system.list.health.read.item",
        defaultValue: "\(entry.list.displayName) (\(entry.overdueCount))",
        table: "Localizable", bundle: SystemL10n.bundle)
    }
    let names = SystemIntentListSummary.names(items, total: items.count)
    return .result(
      value: overdue.map { LorvexListEntity(list: $0.list) },
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.health.read.overdue_dialog",
          defaultValue: "Overdue tasks in \(overdue.count) lists: \(names)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }

  /// Each list in `catalog` that `health` counts overdue tasks for, with that
  /// count: most overdue first, then by name.
  static func listsWithOverdueTasks(
    health: [ListHealthEntry], catalog: [LorvexList]
  ) -> [(list: LorvexList, overdueCount: Int)] {
    let overdueByID = Dictionary(
      health.filter { $0.overdueOpenCount > 0 }.map { ($0.id, $0.overdueOpenCount) },
      uniquingKeysWith: max)
    return catalog.compactMap { list in overdueByID[list.id].map { (list, $0) } }
      .sorted { lhs, rhs in
        if lhs.overdueCount != rhs.overdueCount { return lhs.overdueCount > rhs.overdueCount }
        return lhs.list.displayName.localizedStandardCompare(rhs.list.displayName) == .orderedAscending
      }
  }
}
