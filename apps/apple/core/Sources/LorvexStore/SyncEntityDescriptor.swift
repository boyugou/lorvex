import LorvexDomain

/// One per-entity declaration of a syncable entity's storage/wire field roles, so
/// the three field-mapping seams that can otherwise drift apart derive from one
/// source:
///
///   * the outbound generic reader's column list
///     (``OutboxEnqueue``'s `pragma`-fallback reader),
///   * the inbound LWW upsert's column list (each applier's ``LwwUpsertSpec``), and
///   * the payload-shadow owned-key set (``PayloadShadow/ownedKeysForEntity(_:)``).
///
/// Field roles keep three independent storage/wire cases explicit:
///
///   * `.column` is a real column that crosses the wire and participates in the
///     inbound upsert;
///   * `.synthetic` is a wire-only key built / parsed by a dedicated seam; and
///   * `.derivedLocalColumn` is a real inbound column deterministically rebuilt
///     from another validated wire field. It never crosses the wire; the shadow
///     layer strips it if an older/future payload nevertheless contains it.
///
/// The descriptor declares field participation, not value transforms. Every
/// transform — display-string scrub, `lookup_key` re-derivation,
/// nullable-or-clear semantics, 0/1↔bool coercion,
/// timestamp / enum validation, recurrence normalization — stays in the
/// hand-written applier, which binds the values. The descriptor never dictates
/// HOW a value is produced.
///
/// Migration is incremental: an entity gains a descriptor in ``registry`` and
/// simultaneously drops its hand-written entry from ``PayloadShadow`` owned keys,
/// its inbound column list, and (for generic-reader entities) its outbound
/// `pragma` path. Entities without a descriptor keep their hand-written lists.
public struct SyncEntityDescriptor: Sendable, Equatable {

  /// How one declared field participates in storage and the wire contract.
  public enum FieldKind: Sendable, Equatable {
    /// A real table column shipped by the generic outbound reader and named in
    /// the inbound ``LwwUpsertSpec`` column list.
    case column
    /// An owned wire key with no 1:1 table column — a materialized child
    /// collection, a JSON-in-TEXT value, or a computed array. Present in the
    /// owned-key set but never in the plain-column projection.
    case synthetic
    /// A real table column rebuilt locally from another validated wire field.
    /// It participates in the inbound ``LwwUpsertSpec`` binding but is excluded
    /// from generic outbound SELECTs and stripped from payload shadows.
    case derivedLocalColumn
  }

  /// One declared field: its canonical JSON/storage key and role.
  public struct Field: Sendable, Equatable {
    public let key: String
    public let kind: FieldKind

    public init(_ key: String, _ kind: FieldKind = .column) {
      self.key = key
      self.kind = kind
    }
  }

  /// How the entity's payload is produced OUTBOUND.
  public enum OutboundSeam: Sendable, Equatable {
    /// The pragma/descriptor generic reader
    /// (``OutboxEnqueue/readEntityPayloadSnapshot(_:entityType:entityId:)`` →
    /// `readGenericEntityPayloadSnapshot`), which sources its SELECT column list
    /// from ``outboundColumns``. For these entities the inbound storage projection
    /// must classify every non-device-local table column, while derived-local
    /// columns stay out of the shipped projection.
    case genericReader
    /// A dedicated builder — the ``PayloadBuild`` aggregate composer (child-bearing
    /// roots), the habit loader, or the preference JSON-in-TEXT loader — that
    /// composes a wire shape the generic reader cannot see. `plainColumns` is NOT
    /// the outbound source, so it is not schema-locked against the table.
    case customBuilder
    /// A composite-edge relation whose payload is built inline by the workflow
    /// layer; the generic reader rejects the edge type before it consults a
    /// descriptor. No generic reader participates.
    case edgeInline
  }

  /// How the entity's columns are consumed INBOUND.
  public enum InboundSeam: Sendable, Equatable {
    /// The shared ``LwwUpsertSpec`` sources its column list from ``plainColumns``
    /// (a plain last-writer-wins column upsert). `plainColumns` must end with
    /// `version`.
    case lwwColumns
    /// A hand-written applier that does NOT consume ``plainColumns``; only the
    /// owned-key set derives from the descriptor. Per-column apply is bespoke
    /// (e.g. the day-scoped child-replace roots).
    case customApplier
  }

  public let entity: EntityKind

  /// Declaration order, preserved from the historical hand-written lists so the
  /// derived SQL is byte-identical. For column-based inbound the plain-column
  /// projection must end with `version` (the ``LwwUpsertSpec`` invariant).
  public let fields: [Field]

  /// How this entity's payload is produced outbound.
  public let outbound: OutboundSeam

  /// How this entity's columns are consumed inbound.
  public let inbound: InboundSeam

  public init(entity: EntityKind, fields: [Field], outbound: OutboundSeam, inbound: InboundSeam) {
    self.entity = entity
    self.fields = fields
    self.outbound = outbound
    self.inbound = inbound
  }

  /// Every locally understood upsert wire key (columns + synthetics), in
  /// declaration order. Derived-local storage columns are deliberately absent.
  public var wireKeys: [String] {
    fields.compactMap { $0.kind == .derivedLocalColumn ? nil : $0.key }
  }

  /// Every key the payload-shadow layer must strip from a forward-compat payload.
  /// This includes derived-local columns: they are not valid wire output, but an
  /// older/future peer that sends one must not trick this client into preserving
  /// and re-emitting it as an unknown field.
  public var shadowConsumedKeys: [String] { fields.map(\.key) }

  /// Real table columns emitted by the generic outbound reader. This projection
  /// is intentionally narrower than ``plainColumns`` when a descriptor contains
  /// derived-local storage.
  public var outboundColumns: [String] {
    fields.compactMap { $0.kind == .column ? $0.key : nil }
  }

  /// The inbound storage-column projection, in declaration order. Both ordinary
  /// wire columns and derived-local columns are bound by the applier; synthetics
  /// are handled separately. Kept as `plainColumns` because it is the established
  /// ``LwwUpsertSpec`` call-site name.
  public var plainColumns: [String] {
    fields.compactMap { $0.kind == .synthetic ? nil : $0.key }
  }

  /// Wire-only keys materialized outside the base table.
  public var syntheticKeys: [String] {
    fields.compactMap { $0.kind == .synthetic ? $0.key : nil }
  }

  /// Real storage columns deterministically rebuilt rather than transmitted.
  public var derivedLocalColumns: [String] {
    fields.compactMap { $0.kind == .derivedLocalColumn ? $0.key : nil }
  }
}

extension SyncEntityDescriptor {

  /// The descriptor for a migrated entity, or `nil` for entities still served by
  /// their hand-written field lists.
  public static func descriptor(for entity: EntityKind) -> SyncEntityDescriptor? {
    registry[entity]
  }

  /// String-keyed lookup for callers holding a raw `entity_type`; `nil` for an
  /// unknown type or an entity without a descriptor.
  public static func descriptor(for entityType: String) -> SyncEntityDescriptor? {
    guard let kind = EntityKind.parse(entityType) else { return nil }
    return registry[kind]
  }

  /// The descriptor for an entity known at the call site to be migrated. Traps if
  /// the entity has no descriptor — a programmer error, since an applier and its
  /// descriptor are edited together.
  public static func require(_ entity: EntityKind) -> SyncEntityDescriptor {
    guard let descriptor = registry[entity] else {
      preconditionFailure(
        "no SyncEntityDescriptor registered for \(entity.asString); it must be migrated as a unit")
    }
    return descriptor
  }

  static let registry: [EntityKind: SyncEntityDescriptor] = {
    var map: [EntityKind: SyncEntityDescriptor] = [:]
    for descriptor in all {
      precondition(
        map.updateValue(descriptor, forKey: descriptor.entity) == nil,
        "duplicate SyncEntityDescriptor for \(descriptor.entity.asString)")
    }
    return map
  }()

  /// Build a descriptor whose fields are all plain columns, in the given order.
  /// The order is preserved verbatim into the inbound upsert's column list, so
  /// `keys` must match the historical hand-written order (ending with `version`).
  static func allColumns(
    _ entity: EntityKind, _ keys: [String], outbound: OutboundSeam, inbound: InboundSeam
  ) -> SyncEntityDescriptor {
    SyncEntityDescriptor(
      entity: entity, fields: keys.map { Field($0, .column) }, outbound: outbound, inbound: inbound)
  }

  /// Build a descriptor from an ordered key list where `synthetic` names the keys
  /// that are NOT plain table columns (child collections, computed arrays). The
  /// remaining keys are plain columns.
  static func columnsWithSynthetics(
    _ entity: EntityKind, _ keys: [String], synthetic: Set<String>,
    outbound: OutboundSeam, inbound: InboundSeam
  ) -> SyncEntityDescriptor {
    SyncEntityDescriptor(
      entity: entity,
      fields: keys.map { Field($0, synthetic.contains($0) ? .synthetic : .column) },
      outbound: outbound, inbound: inbound)
  }

  /// Build a descriptor containing both synthetic wire fields and real columns
  /// that are derived locally instead of transmitted. The two role sets must be
  /// disjoint and every named field must appear in `keys`.
  static func columnsWithSpecialFields(
    _ entity: EntityKind, _ keys: [String], synthetic: Set<String> = [],
    derivedLocal: Set<String> = [], outbound: OutboundSeam, inbound: InboundSeam
  ) -> SyncEntityDescriptor {
    precondition(synthetic.isDisjoint(with: derivedLocal), "field roles must be disjoint")
    precondition(synthetic.union(derivedLocal).isSubset(of: Set(keys)), "field role names must exist")
    return SyncEntityDescriptor(
      entity: entity,
      fields: keys.map { key in
        if synthetic.contains(key) { return Field(key, .synthetic) }
        if derivedLocal.contains(key) { return Field(key, .derivedLocalColumn) }
        return Field(key, .column)
      },
      outbound: outbound, inbound: inbound)
  }

  /// Every registered descriptor. An entity is appended here once at least one of
  /// its three seams (outbound generic reader, inbound upsert column list,
  /// payload-shadow owned keys) is cut over to derive from it; which seams a given
  /// entity drives is noted on each descriptor below.
  static let all: [SyncEntityDescriptor] = [
    list,
    tag,
    taskReminder,
    taskChecklistItem,
    habitReminderPolicy,
    memory,
    calendarSeriesCutover,
    preference,
    taskTag,
    taskDependency,
    taskCalendarEventLink,
    habitCompletion,
    // Child-bearing aggregates. Their OUTBOUND stays on the dedicated builders
    // (the ``PayloadBuild`` aggregate composer / the habit loader) because their
    // wire shape embeds child collections the generic reader cannot see. habit
    // and calendar_event additionally derive their inbound base-row column set
    // from `plainColumns` (the synthetic child fields are excluded); the
    // day-scoped roots keep their hand-written child-replace appliers, so for them
    // only the owned keys derive from the descriptor.
    habit,
    calendarEvent,
    dailyReview,
    currentFocus,
    focusSchedule,
  ]

  // BLOCKER — `task` and `ai_changelog` are deliberately NOT registered here; they
  // stay on the hand-written path (their owned keys / inbound column lists live in
  // the `switch` arms of ``PayloadShadow/ownedKeysForEntity(_:)`` and their
  // dedicated appliers). They MUST NOT be migrated under the current
  // field-role model, which cannot express either entity's complete contract:
  //
  //   * `task` needs a richer field model, on two
  //     independent axes:
  //       - Partial-patch inbound. ``ApplyTask`` applies each field with tri-state
  //         (unset / clear / set) partial-patch semantics; a `.column` field means
  //         the shared ``LwwUpsertSpec`` overwrites that column unconditionally on
  //         every apply. So `plainColumns` cannot drive `task`'s inbound the way it
  //         drives `list`.
  //       - The GENERATED column `tasks.priority_effective`
  //         (`INTEGER GENERATED ALWAYS AS (COALESCE(priority, 4)) VIRTUAL`) is a
  //         REAL table column that must be absent from ALL THREE seams: it is not a
  //         payload-shadow owned key (a documented schema-only exception in
  //         `PayloadShadowTests.testPayloadShadowSchemaParity`), it is never applied
  //         inbound, and it never ships outbound (the generic reader enumerates
  //         `pragma_table_info`, which omits generated columns). Neither `.column`
  //         (ships + owned + inbound) nor `.synthetic` (an owned wire key) can
  //         represent "a real column deliberately excluded from wire, owned keys,
  //         and inbound"; `.derivedLocalColumn` is not appropriate because a
  //         generated column is not bound inbound. A faithful task descriptor
  //         would need a separate `.generated` role.
  //   * `ai_changelog` is an append-only audit stream with an id-dedup
  //     `INSERT OR IGNORE` contract (covered by `ChangelogSyncOutboundTests`), not
  //     the bidirectional upsert lane the descriptor's seams describe.
  //
  // This is a risk/reward decision, not a hard impossibility: migrating the
  // crown-jewel `task` entity immediately before schema freeze — for a modest gain,
  // since its outbound field parity is already guarded by
  // `SyncFieldRoundTripProbeTests` and `PayloadShadowTests.testPayloadShadowSchemaParity`
  // — would require extending the field model on the highest-blast-radius entity,
  // which is not worth the risk here.

  /// `list` — a plain-column aggregate root. Outbound via the generic reader,
  /// inbound via ``ApplyList`` (name/description/ai_notes scrub, description body
  /// validation, position preserve-on-absent), shadow owned keys all from here.
  static let list = allColumns(
    .list,
    [
      "id", "name", "color", "icon", "description", "ai_notes", "archived_at", "created_at",
      "updated_at", "position", "version",
    ],
    outbound: .genericReader, inbound: .lwwColumns)

  /// `tag` — a plain-column independent child. `lookup_key` is derived-local:
  /// it never crosses the wire, is stripped from forward-compat shadows, and is
  /// rebuilt from the scrubbed `display_name` on inbound apply. The min-id-winner duplicate
  /// merge and `color` nullable-or-clear semantics stay in ``ApplyTagMerge``.
  static let tag = columnsWithSpecialFields(
    .tag,
    ["id", "display_name", "lookup_key", "color", "created_at", "updated_at", "version"],
    derivedLocal: ["lookup_key"],
    outbound: .genericReader, inbound: .lwwColumns)

  /// `task_reminder` — plain-column independent child. `reminder_at` is
  /// re-canonicalized as an RFC 3339 instant on apply and a changed time clears
  /// the delivery-state row; both stay in ``ApplyChild``.
  static let taskReminder = allColumns(
    .taskReminder,
    [
      "id", "task_id", "reminder_at", "dismissed_at", "cancelled_at", "created_at",
      "original_local_time", "original_tz", "version",
    ],
    outbound: .genericReader, inbound: .lwwColumns)

  /// `task_checklist_item` — plain-column independent child (`text` scrubbed on
  /// apply, in ``ApplyChild``).
  static let taskChecklistItem = allColumns(
    .taskChecklistItem,
    ["id", "task_id", "position", "text", "completed_at", "created_at", "updated_at", "version"],
    outbound: .genericReader, inbound: .lwwColumns)

  /// `habit_reminder_policy` — plain-column independent child. `reminder_time`
  /// HH:MM validation, the `UNIQUE(habit_id, reminder_time)` collision merge, and
  /// the `enabled` bool coercion all stay in ``ApplyChild``.
  static let habitReminderPolicy = allColumns(
    .habitReminderPolicy,
    ["id", "habit_id", "reminder_time", "enabled", "created_at", "updated_at", "version"],
    outbound: .genericReader, inbound: .lwwColumns)

  /// `memory` — KV aggregate root (PK = opaque `id`). Content scrub + byte-clamp,
  /// the `UNIQUE(key)` collision merge, and truncation conflict logging stay in
  /// ``ApplyKVAggregate``.
  static let memory = allColumns(
    .memory, ["id", "key", "content", "updated_at", "version"],
    outbound: .genericReader, inbound: .lwwColumns)

  /// `calendar_series_cutover` — an upsert-only, remove-wins boundary. Outbound
  /// uses the generic descriptor projection; the custom applier joins `deleted`
  /// as an absorbing state instead of applying ordinary whole-row LWW.
  static let calendarSeriesCutover = allColumns(
    .calendarSeriesCutover,
    ["id", "lineage_root_id", "cutover_date", "state", "created_at", "updated_at", "version"],
    outbound: .genericReader, inbound: .customApplier)

  /// `preference` — KV aggregate root (PK = `key`). Outbound uses the dedicated
  /// JSON-in-TEXT loader (`PayloadLoaders.loadPreferenceSyncPayload`), NOT the
  /// generic reader, so only the owned-key set and the inbound upsert column list
  /// derive from here; the `value` canonicalization and local-only-key filtering
  /// stay in ``ApplyKVAggregate``.
  static let preference = allColumns(
    .preference, ["key", "value", "updated_at", "version"],
    outbound: .customBuilder, inbound: .lwwColumns)

  // Composite-edge relations. Each has no generic outbound reader (edge payloads
  // are built inline by the workflow layer, and the generic reader rejects an
  // edge type before it ever consults a descriptor), so only the inbound
  // LwwUpsertSpec column list and the owned keys derive from here. Every payload
  // transform — the FK-match preflight, the habit_completion `value > 0` gate, the
  // task_dependency cycle-break — stays in ``ApplyEdge`` / ``ApplyFk``.

  /// `task_tag` edge.
  static let taskTag = allColumns(
    .taskTag, ["task_id", "tag_id", "created_at", "version"],
    outbound: .edgeInline, inbound: .lwwColumns)

  /// `task_dependency` edge (cycle-break tiebreak stays in ``ApplyEdge``).
  static let taskDependency = allColumns(
    .taskDependency, ["task_id", "depends_on_task_id", "created_at", "version"],
    outbound: .edgeInline, inbound: .lwwColumns)

  /// `task_calendar_event_link` edge.
  static let taskCalendarEventLink = allColumns(
    .taskCalendarEventLink,
    ["task_id", "calendar_event_id", "created_at", "updated_at", "version"],
    outbound: .edgeInline, inbound: .lwwColumns)

  /// `habit_completion` edge (`value > 0` gate stays in ``ApplyEdge``).
  static let habitCompletion = allColumns(
    .habitCompletion,
    ["habit_id", "completed_date", "value", "note", "created_at", "updated_at", "version"],
    outbound: .edgeInline, inbound: .lwwColumns)

  /// `habit` — aggregate root whose weekly `weekdays` set lives in the
  /// `habit_weekdays` child (synthetic), not a `habits` column. Outbound uses the
  /// dedicated habit loader (which also omits the re-derived local `lookup_key`
  /// from the wire); inbound derives its base-row column set from `plainColumns`
  /// while ``ApplyHabit`` keeps the value transforms (cadence normalization,
  /// lookup_key re-derivation, position preserve-on-absent) and the weekday child.
  static let habit = columnsWithSpecialFields(
    .habit,
    [
      "id", "name", "icon", "color", "cue", "frequency_type", "weekdays", "per_period_target",
      "day_of_month", "target_count", "milestone_target", "archived", "lookup_key", "created_at",
      "updated_at", "position", "version",
    ],
    synthetic: ["weekdays"], derivedLocal: ["lookup_key"],
    outbound: .customBuilder, inbound: .lwwColumns)

  /// `calendar_event` — aggregate root with a dedicated JSON-in-TEXT attendees
  /// projection outbound and a two-register merge inbound. Base-event content
  /// follows `content_version`; recurrence topology follows
  /// `recurrence_topology_version`. Occurrence decisions are whole-row LWW
  /// registers with deterministic ids. The descriptor remains the single owner
  /// of the wire/shadow field inventory while the applier owns those semantics.
  static let calendarEvent = allColumns(
    .calendarEvent,
    [
      "id", "title", "description", "start_date", "start_time", "end_date", "end_time", "all_day",
      "location", "url", "color", "recurrence", "timezone", "event_type", "person_name",
      "series_cutover_id", "series_id", "recurrence_instance_date", "occurrence_state", "recurrence_generation",
      "content_version", "recurrence_topology_version", "created_at", "updated_at", "attendees",
      "version",
    ],
    outbound: .customBuilder, inbound: .customApplier)

  /// `daily_review` — aggregate root with embedded `linked_task_ids` /
  /// `linked_list_ids` link collections (synthetic). Outbound via ``PayloadBuild``,
  /// inbound via ``ApplyDayScoped``; only the owned keys derive here.
  static let dailyReview = columnsWithSynthetics(
    .dailyReview,
    [
      "date", "summary", "mood", "energy_level", "wins", "blockers", "learnings",
      "timezone", "created_at", "updated_at", "linked_task_ids", "linked_list_ids", "version",
    ],
    synthetic: ["linked_task_ids", "linked_list_ids"],
    outbound: .customBuilder, inbound: .customApplier)

  /// `current_focus` — aggregate root with an embedded `task_ids` collection
  /// (synthetic). Outbound via ``PayloadBuild``, inbound via ``ApplyDayScoped``;
  /// only the owned keys derive here.
  static let currentFocus = columnsWithSynthetics(
    .currentFocus,
    ["date", "briefing", "timezone", "created_at", "updated_at", "task_ids", "version"],
    synthetic: ["task_ids"],
    outbound: .customBuilder, inbound: .customApplier)

  /// `focus_schedule` — aggregate root with an embedded `blocks` collection
  /// (synthetic). Outbound via ``PayloadBuild``, inbound via ``ApplyDayScoped``;
  /// only the owned keys derive here.
  static let focusSchedule = columnsWithSynthetics(
    .focusSchedule,
    ["date", "rationale", "timezone", "created_at", "updated_at", "blocks", "version"],
    synthetic: ["blocks"],
    outbound: .customBuilder, inbound: .customApplier)
}
