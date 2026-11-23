import AppIntents
import GeoToolbox
import LorvexCore

// The system's reminder shape names a location trigger and a list section on
// its create and update actions and on the reminder itself. Lorvex has
// neither. The build's App Intents metadata step requires every field of a
// shape to be declared, and every entity an action takes to be one Siri can
// look up by name, so the types in this file exist to declare them. Their
// queries find nothing, so Siri can never hand one to an action and the fields
// stay empty.

/// When a location trigger fires. Declared for the reminder shape; Lorvex has
/// no location triggers, so no action ever receives one.
@available(macOS 27.0, iOS 27.0, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
enum LorvexSiriLocationTriggerEvent: String {
  case arrive
  case depart

  static let caseDisplayRepresentations: [LorvexSiriLocationTriggerEvent: DisplayRepresentation] = [
    .arrive: DisplayRepresentation(
      title: LocalizedStringResource(
        "system.option.location_trigger.arrive", defaultValue: "Arriving", table: "Localizable",
        bundle: SystemL10n.bundle)),
    .depart: DisplayRepresentation(
      title: LocalizedStringResource(
        "system.option.location_trigger.depart", defaultValue: "Leaving", table: "Localizable",
        bundle: SystemL10n.bundle)),
  ]
}

/// A reminder's location trigger. Declared for the reminder shape; Lorvex has
/// no location triggers and its query finds none.
@available(macOS 27.0, iOS 27.0, *)
@AppEntity(schema: .reminders.locationTrigger)
struct LorvexSiriLocationTriggerEntity {
  static let defaultQuery = LorvexSiriLocationTriggerEntityQuery()

  let id: String
  var place: PlaceDescriptor
  var event: LorvexSiriLocationTriggerEvent

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(place.commonName ?? id)")
  }

  init(id: String, place: PlaceDescriptor, event: LorvexSiriLocationTriggerEvent) {
    self.id = id
    self.place = place
    self.event = event
  }
}

@available(macOS 27.0, iOS 27.0, *)
struct LorvexSiriLocationTriggerEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [LorvexSiriLocationTriggerEntity] { [] }
  func entities(matching string: String) async throws -> [LorvexSiriLocationTriggerEntity] { [] }
  func suggestedEntities() async throws -> [LorvexSiriLocationTriggerEntity] { [] }
}

/// A section of a reminder list. Declared for the reminder shape; a Lorvex
/// list has no sections and its query finds none.
@available(macOS 27.0, iOS 27.0, *)
@AppEntity(schema: .reminders.section)
struct LorvexSiriSectionEntity {
  static let defaultQuery = LorvexSiriSectionEntityQuery()

  let id: String
  var name: String
  var list: LorvexSiriListEntity

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }

  init(id: String, name: String, list: LorvexSiriListEntity) {
    self.id = id
    self.name = name
    self.list = list
  }
}

@available(macOS 27.0, iOS 27.0, *)
struct LorvexSiriSectionEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [LorvexSiriSectionEntity] { [] }
  func entities(matching string: String) async throws -> [LorvexSiriSectionEntity] { [] }
  func suggestedEntities() async throws -> [LorvexSiriSectionEntity] { [] }
}
