import AppIntents

/// Minimal entity query for `WidgetTaskEntity` — required by the `AppEntity`
/// protocol. Widget-hosted intents construct entities directly from task IDs
/// embedded in the widget render model; interactive lookup is not needed.
public struct WidgetTaskEntityQuery: EntityQuery {
  public init() {}

  public func entities(for identifiers: [WidgetTaskEntity.ID]) async throws -> [WidgetTaskEntity] {
    identifiers.map { WidgetTaskEntity(id: $0) }
  }
}
