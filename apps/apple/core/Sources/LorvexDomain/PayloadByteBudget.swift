/// Escaped-byte budgets that make every locally-authored sync payload provably
/// fit ``StorageSchema/maxPayloadBytes``.
///
/// The codepoint caps in ``ValidationLimits`` are UX-facing limits; they do not
/// bound wire size, because canonical JSON escaping inflates content: `"`,
/// `\`, and the C0 short-form escapes (`\n \r \t \b \f`) occupy 2 bytes per
/// codepoint, every other scalar below U+0020 occupies 6 (`\uXXXX`), and a
/// 4-byte emoji passes through as 4 UTF-8 bytes. Two individually-legal fields
/// (50,000-codepoint emoji body + 50,000-codepoint emoji ai_notes) therefore
/// composed past the 256 KiB whole-payload cap and failed at outbound
/// canonicalization — attributed to whichever write happened second.
///
/// The fix is write-time enforcement measured in CANONICAL-ESCAPED bytes via
/// ``canonicalEscapedUTF8Count(_:)``, plus count caps on the unbounded payload
/// collections. Inbound envelopes need no budget of their own: the wire and
/// shadow layers already reject any payload above the cap before an applier
/// runs, and an accepted inbound row re-canonicalizes to the size it arrived
/// at. Aggregate merges compose fields by participant maximum, never by sum,
/// so merged rows also stay within the per-field bounds.
///
/// Worst-case whole-payload arithmetic per entity (cap 262,144 bytes; fixed
/// keys/scalars/structure generously over-counted):
///
///   tasks            title 6,000 + body 120,000 + ai_notes 80,000
///                    + raw_input 12,000 + last_defer_reason 12,000
///                    + recurrence_exceptions 400×13 = 5,200 + recurrence 2,000
///                    + misc 4,000                              = 241,200
///   lists            name 6,000 + description 120,000 + ai_notes 80,000
///                    + misc 2,000                              = 208,000
///   calendar_events  title 6,000 + description 120,000
///                    + location/person/url 3×12,000
///                    + attendees 15×2×1,536 = 46,080 + misc 8,000 = 216,080
///   daily_reviews    4 text fields ×40,000 + links 200×39 = 7,800
///                    + misc 2,000                              = 169,800
///   current_focus    briefing 20,000 + task_ids 100×39 + misc 2,000 = 25,900
///   focus_schedule   rationale 20,000 + blocks 50×(2,048 title + 300)
///                    + misc 2,000                              = 139,400
///   memories         content ≤100,000 sanitized bytes → ≤200,000 escaped
///                    + key ≤1,200 + misc 1,000                 = 202,200
///   preferences      value ≤32,768 raw bytes → ≤196,608 escaped (all-C0
///                    worst case) + key ≤1,200 + misc 1,000     = 198,808
///   habits/tags/edges/children: every field is short-capped; worst cases
///                    are below 40,000.
public enum PayloadByteBudget {
  /// Long-form user text riding an entity payload beside other long fields:
  /// task `body`, list `description`, calendar event `description`.
  public static let longTextEscapedBytes = 120_000

  /// AI-authored notes fields (`ai_notes` on tasks and lists).
  public static let aiNotesEscapedBytes = 80_000

  /// Daily-review text fields (`summary`, `wins`, `blockers`, `learnings`) —
  /// four of them ride one payload.
  public static let reviewTextEscapedBytes = 40_000

  /// Day-plan prose (`current_focus.briefing`, `focus_schedule.rationale`).
  public static let dayPlanTextEscapedBytes = 20_000

  /// Freeform focus-schedule block title.
  public static let scheduleBlockTitleEscapedBytes = 2_048

  /// Collection count caps for the unbounded payload collections.
  public static let maxCalendarAttendees = 15
  public static let maxReviewLinkedTasks = 100
  public static let maxReviewLinkedLists = 100
  public static let maxFocusTasks = 100
  public static let maxScheduleBlocks = 50
  public static let maxRecurrenceExceptions = 400

  /// Attendee `email` / `name` codepoint cap. Tighter than
  /// ``ValidationLimits/maxShortTextLength`` because up to
  /// ``maxCalendarAttendees`` × 2 of these fields ride one event payload.
  public static let maxAttendeeFieldLength = 256

  /// Byte length of `value` after canonical JSON string escaping, excluding
  /// the surrounding quotes — a single pass mirroring the fixed escape table
  /// in `canonicalizeJSON`. `PayloadByteBudgetTests` pins byte-equality
  /// against the real serializer over an adversarial corpus so the two can
  /// never drift.
  public static func canonicalEscapedUTF8Count(_ value: String) -> Int {
    var count = 0
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x22, 0x5C, 0x0A, 0x0D, 0x09, 0x08, 0x0C:
        count += 2
      case 0x00...0x1F:
        count += 6
      default:
        count += UTF8.width(scalar)
      }
    }
    return count
  }

  /// Validate that `value` occupies at most `budget` canonical-escaped bytes
  /// inside its payload. Surfaces ``ValidationError/tooLong(field:max:actual:)``
  /// with byte units, matching the memory-content byte cap's convention.
  public static func validateEscapedBudget(
    _ value: String, field: String, budget: Int
  ) -> Result<Void, ValidationError> {
    let bytes = canonicalEscapedUTF8Count(value)
    if bytes > budget {
      return .failure(.tooLong(field: field, max: budget, actual: bytes))
    }
    return .success(())
  }

  /// Optional-value variant of ``validateEscapedBudget(_:field:budget:)``.
  public static func validateOptionalEscapedBudget(
    _ value: String?, field: String, budget: Int
  ) -> Result<Void, ValidationError> {
    guard let value else { return .success(()) }
    return validateEscapedBudget(value, field: field, budget: budget)
  }
}
