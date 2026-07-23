import Foundation

/// Typed value contract for every ordinary row in the `preferences` table.
///
/// Preference values travel as JSON nodes, not untyped strings. This validator
/// is shared by local writes, imports, and sync apply so no ingress can persist
/// a value that a later workflow read cannot decode. It also normalizes the two
/// accepted working-hours input shapes and timezone whitespace before storage,
/// making the canonical JSON bytes independent of the calling surface.
public enum PreferenceValueContract {
  /// Validate and normalize one JSON preference value.
  ///
  /// Virtual control-plane values (currently AI-changelog retention) and
  /// device-state values (calendar AI access) have dedicated stores and must be
  /// handled before this ordinary-row contract.
  public static func normalize(
    key: String,
    value: JSONValue
  ) -> Result<JSONValue, ValidationError> {
    guard PreferenceKeys.isKnownPreferenceKey(key) else {
      return .failure(.message("unknown preference key '\(key)'"))
    }
    guard !PreferenceKeys.isControlPlanePreference(key) else {
      return .failure(
        .message("control-plane preference '\(key)' cannot be stored as a preference row"))
    }

    switch key {
    case PreferenceKeys.prefWorkingHours:
      return normalizeWorkingHours(value)

    case PreferenceKeys.prefTimezone:
      guard case .string(let raw) = value,
        let timezone = Timezone.normalizeProductTimezoneName(raw)
      else {
        return .failure(
          .message("timezone preference must be a canonical region timezone or UTC"))
      }
      return .success(.string(timezone))

    case PreferenceKeys.prefDefaultListId:
      guard case .string(let raw) = value else {
        return .failure(.message("default_list_id preference must be a string"))
      }
      switch ListId.parse(raw) {
      case .success(let id): return .success(.string(id.asString))
      case .failure(let error): return .failure(error)
      }

    case PreferenceKeys.prefSetupCompleted,
      PreferenceKeys.prefRecordRawInput,
      PreferenceKeys.prefNotificationShowTaskNotes:
      guard case .bool = value else {
        return .failure(.message("\(key) preference must be a JSON boolean"))
      }
      return .success(value)

    case PreferenceKeys.prefSetupSummary,
      PreferenceKeys.prefSetupState,
      PreferenceKeys.prefLanguage,
      PreferenceKeys.prefTheme:
      guard case .string = value else {
        return .failure(.message("\(key) preference must be a string"))
      }
      return .success(value)

    default:
      // The exhaustive allowlist guard above makes reaching this branch mean a
      // newly-added preference forgot to define its value semantics here.
      return .failure(.message("preference '\(key)' has no value contract"))
    }
  }

  private static func normalizeWorkingHours(
    _ value: JSONValue
  ) -> Result<JSONValue, ValidationError> {
    let rawStart: String
    let rawEnd: String
    switch value {
    case .object(let object):
      guard Set(object.keys) == ["start", "end"],
        case .string(let start)? = object["start"],
        case .string(let end)? = object["end"]
      else {
        return .failure(
          .message(
            "working_hours preference must be an object with only string start/end fields"))
      }
      rawStart = start
      rawEnd = end

    case .string(let shorthand):
      let parts = shorthand.split(separator: "-", omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        return .failure(
          .message("working_hours preference must be HH:MM-HH:MM or a start/end object"))
      }
      rawStart = String(parts[0])
      rawEnd = String(parts[1])

    default:
      return .failure(
        .message("working_hours preference must be HH:MM-HH:MM or a start/end object"))
    }

    let start: TimeOfDay
    switch TimeOfDay.parse(rawStart) {
    case .success(let parsed): start = parsed
    case .failure:
      return .failure(
        .invalidFormat(field: "working_hours.start", expected: "HH:MM", actual: rawStart))
    }
    let end: TimeOfDay
    switch TimeOfDay.parse(rawEnd) {
    case .success(let parsed): end = parsed
    case .failure:
      return .failure(
        .invalidFormat(field: "working_hours.end", expected: "HH:MM", actual: rawEnd))
    }
    guard end > start else {
      return .failure(.message("working_hours.end must be after working_hours.start"))
    }
    return .success(
      .object([
        "start": .string(start.asString),
        "end": .string(end.asString),
      ]))
  }
}
