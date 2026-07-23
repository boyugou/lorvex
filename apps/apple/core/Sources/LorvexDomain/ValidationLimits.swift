/// Validation limit constants.
///
/// Every write surface (MCP host, app commands, sync apply, client-side
/// pre-checks) references these names, so a change to a bound is a single-file
/// edit. Codepoint-counted caps are surfaced as `Int`; numeric range bounds
/// that flow into ``ValidationError/outOfRange(field:min:max:actual:)`` are
/// `Int64` to match that case's payload.
public enum ValidationLimits {
  /// Maximum title length for tasks and lists, in Unicode codepoints.
  public static let maxTitleLength = 1_000

  /// Maximum body length for tasks / list descriptions / calendar event
  /// descriptions, in Unicode codepoints. Capped at 50 KB.
  public static let maxBodyLength = 50_000

  /// Valid priority range (1-3, importance-first).
  public static let priorityMin: Int64 = 1
  public static let priorityMax: Int64 = 3

  /// Maximum estimated_minutes (24 hours).
  public static let maxEstimatedMinutes: Int64 = 1440

  /// Maximum short-text field length (location, person_name, etc.).
  public static let maxShortTextLength = 2_000

  /// Maximum `ai_notes` length (tasks and lists), in Unicode codepoints.
  /// Single source of truth for every ai_notes write path; the wire-size
  /// bound is `PayloadByteBudget.aiNotesEscapedBytes`.
  public static let maxAiNotesLength = 50_000

  /// Maximum tag display_name length.
  public static let maxTagNameLength = 100

  /// Maximum length of an `icon` token (an SF Symbol name), in Unicode
  /// codepoints. A single emoji grapheme is also accepted as an icon regardless
  /// of this cap. Icons are machine tokens rendered as glyphs, never free text.
  public static let maxIconLength = 64

  /// Maximum reminder window in seconds (1 year).
  public static let maxReminderWindowSeconds: Int64 = 365 * 24 * 3600

  /// Mood / energy_level scale bounds (daily reviews).
  public static let moodMin: Int64 = 1
  public static let moodMax: Int64 = 5

  /// Maximum number of tags attached to a single task.
  public static let maxTaskTags = 30

  /// Maximum number of `depends_on` edges per task.
  public static let maxTaskDependencies = 50

  /// Maximum length of the optional habit `cue` field, in Unicode codepoints.
  public static let maxHabitCueLength = 200

  /// Maximum length of a preference / device_state / memory key, in Unicode
  /// codepoints. Single source of truth for every key-shaped KV column.
  public static let kvKeyMaxChars = 200

  /// Maximum recurrence `INTERVAL` ("every N days/weeks/months/years").
  ///
  /// 10,000 is far beyond any real cadence — 10,000 days (~27 years) is the
  /// tightest unit — and keeps every INTERVAL-derived term of recurrence
  /// expansion (weekly `interval × 7`, `steps × interval` across the bounded
  /// expansion loops, and month/year advances) well inside `Int64` and the
  /// calendar's representable date range, so no expansion arithmetic can
  /// overflow. Enforced on write by the recurrence normalizer and defensively
  /// by the expansion engine's interval parser.
  public static let maxRecurrenceInterval: Int64 = 10_000
}
