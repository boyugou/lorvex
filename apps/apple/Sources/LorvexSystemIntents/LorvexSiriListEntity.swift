import AppIntents
import LorvexCore

/// The kinds of list the system's reminder actions know. Lorvex has one.
@available(macOS 27.0, iOS 27.0, *)
@AppEnum(schema: .reminders.listType)
enum LorvexSiriListType: String {
  case standard

  static let caseDisplayRepresentations: [LorvexSiriListType: DisplayRepresentation] = [
    .standard: DisplayRepresentation(
      title: LocalizedStringResource(
        "system.entity.list.type", defaultValue: "Lorvex List", table: "Localizable",
        bundle: SystemL10n.bundle))
  ]
}

/// A Lorvex list in the shape of the system's reminder list, the shape Siri
/// works with on macOS 27 and iOS 27. ``LorvexListEntity`` is the list the
/// Shortcuts actions take.
@available(macOS 27.0, iOS 27.0, *)
@AppEntity(schema: .reminders.list)
struct LorvexSiriListEntity: SyncableEntity {
  static let defaultQuery = LorvexSiriListEntityQuery()

  let id: LorvexList.ID
  var name: String
  var type: LorvexSiriListType { .standard }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", image: .init(systemName: "folder"))
  }

  init(id: LorvexList.ID, name: String) {
    self.id = id
    self.name = name
  }

  /// The list under the name the interface shows for it.
  init(list: LorvexList) {
    self.init(id: list.id, name: list.displayName)
  }
}

@available(macOS 27.0, iOS 27.0, *)
struct LorvexSiriListEntityQuery: EntityStringQuery {
  func entities(for identifiers: [LorvexSiriListEntity.ID]) async throws -> [LorvexSiriListEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      let requested = Set(identifiers)
      return try await Self.entities(matching: "", core: core).filter { requested.contains($0.id) }
    }
  }

  func suggestedEntities() async throws -> [LorvexSiriListEntity] {
    try await entities(matching: "")
  }

  func entities(matching string: String) async throws -> [LorvexSiriListEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  /// The lists whose name or id contains `string`; every list for a blank
  /// string. The match is the one the Shortcuts list parameter uses.
  static func entities(
    matching string: String, core: any LorvexCoreServicing
  ) async throws -> [LorvexSiriListEntity] {
    try await LorvexListEntityQuery.entities(matching: string, core: core)
      .map { LorvexSiriListEntity(id: $0.id, name: $0.name) }
  }
}
