import Foundation

/// Canonical `entity_id` shape validation for sync envelopes.
///
/// Stricter than the human-facing
/// trust-boundary parsers: sync payloads carry already-serialized storage
/// identities, so this rejects values that would require trimming,
/// normalization, or format repair before storage. The envelope-validate
/// path calls this so a crafted peer envelope cannot inject a malformed
/// `entity_id` into the apply pipeline.
public enum SyncEntityId {
  private static let canonicalUuidExpected = "canonical hyphenated lowercase UUID"
  private static let canonicalDateExpected = "YYYY-MM-DD"
  private static let canonicalSyncedPreferenceKeyExpected = "known synced preference key"
  private static let syncableEntityKindExpected = "syncable entity kind"
  private static let redirectIdentityExpected = "64-character lowercase SHA-256 hex"

  private static func invalid(_ expected: String, _ actual: String) -> ValidationError {
    .invalidFormat(field: "entity_id", expected: expected, actual: actual)
  }

  /// Accept a canonical hyphenated lowercase UUID of any version. The
  /// canonical-form check rejects uppercase, braces, urn prefixes,
  /// and other non-canonical renderings.
  private static func validateCanonicalUuid(_ value: String) -> Result<Void, ValidationError> {
    guard isCanonicalUuid(value) else {
      return .failure(invalid(canonicalUuidExpected, value))
    }
    return .success(())
  }

  /// True when `value` is exactly a canonical hyphenated lowercase UUID:
  /// 8-4-4-4-12 hex with lowercase a–f. Matches the byte shape that
  /// `uuid::Uuid::to_string()` produces for any version.
  public static func isCanonicalUuid(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 36 else { return false }
    for (i, b) in bytes.enumerated() {
      if i == 8 || i == 13 || i == 18 || i == 23 {
        if b != 0x2D { return false }  // '-'
      } else {
        let isLowerHex = (0x30...0x39).contains(b) || (0x61...0x66).contains(b)
        if !isLowerHex { return false }
      }
    }
    return true
  }

  private static func validateDate(_ value: String) -> Result<Void, ValidationError> {
    switch IsoDate.parseIsoDate(value) {
    case .success: return .success(())
    case .failure: return .failure(invalid(canonicalDateExpected, value))
    }
  }

  private static func validatePreference(_ value: String) -> Result<Void, ValidationError> {
    if PreferenceKeys.isKnownPreferenceKey(value)
      && !PreferenceKeys.isLocalOnlyPreference(value)
    {
      return .success(())
    }
    return .failure(invalid(canonicalSyncedPreferenceKeyExpected, value))
  }

  /// Split `left:right` requiring exactly one separator and non-empty halves.
  private static func splitComposite(
    _ value: String, _ expected: String
  ) -> Result<(String, String), ValidationError> {
    let colonCount = value.utf8.filter { $0 == 0x3A }.count
    guard let idx = value.firstIndex(of: ":") else {
      return .failure(invalid(expected, value))
    }
    let left = String(value[value.startIndex..<idx])
    let right = String(value[value.index(after: idx)...])
    if colonCount == 1 && !left.isEmpty && !right.isEmpty {
      return .success((left, right))
    }
    return .failure(invalid(expected, value))
  }

  private static func validateUuidUuidEdge(
    _ value: String, _ expected: String
  ) -> Result<Void, ValidationError> {
    switch splitComposite(value, expected) {
    case .failure(let e): return .failure(e)
    case .success(let (left, right)):
      if case .failure(let e) = validateCanonicalUuid(left) { return .failure(e) }
      if case .failure(let e) = validateCanonicalUuid(right) { return .failure(e) }
      return .success(())
    }
  }

  private static func validateHabitCompletion(_ value: String) -> Result<Void, ValidationError> {
    switch splitComposite(value, "canonical habit UUID:YYYY-MM-DD") {
    case .failure(let e): return .failure(e)
    case .success(let (habitId, completedDate)):
      if case .failure(let e) = validateCanonicalUuid(habitId) { return .failure(e) }
      return validateDate(completedDate)
    }
  }

  private static func validateRedirectIdentity(
    _ value: String
  ) -> Result<Void, ValidationError> {
    let bytes = Array(value.utf8)
    guard bytes.count == 64,
      bytes.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
    else {
      return .failure(invalid(redirectIdentityExpected, value))
    }
    return .success(())
  }

  /// Validate the canonical `entity_id` shape for a sync envelope's entity kind.
  public static func validateForKind(
    _ kind: EntityKind, _ entityId: String
  ) -> Result<Void, ValidationError> {
    switch kind {
    case .task, .habit, .tag, .calendarEvent, .calendarSeriesCutover, .memory,
      .taskReminder, .taskChecklistItem, .habitReminderPolicy, .aiChangelog:
      return validateCanonicalUuid(entityId)
    case .list:
      if entityId == ListId.inboxSentinel {
        return .success(())
      }
      return validateCanonicalUuid(entityId)
    case .preference:
      return validatePreference(entityId)
    case .dailyReview, .currentFocus, .focusSchedule:
      return validateDate(entityId)
    case .taskTag:
      return validateUuidUuidEdge(entityId, "canonical task UUID:tag UUID")
    case .taskDependency:
      return validateUuidUuidEdge(entityId, "canonical task UUID:dependency task UUID")
    case .taskCalendarEventLink:
      return validateUuidUuidEdge(entityId, "canonical task UUID:calendar event UUID")
    case .habitCompletion:
      return validateHabitCompletion(entityId)
    case .entityRedirect:
      return validateRedirectIdentity(entityId)
    case .deviceState, .importSession:
      return .failure(invalid(syncableEntityKindExpected, entityId))
    }
  }
}
