import Foundation
import MCP

/// Wraps user-supplied string values in prompt-injection fence sentinels before they
/// are embedded in MCP tool responses.
///
/// The sentinels ⟦user⟧…⟦/user⟧ (U+27E6 / U+27E7) mark the boundary between
/// system-structured content and user-controlled text so AI clients can
/// distinguish user content from system content in the same JSON payload.
/// This prevents a malicious task title or note from injecting instructions
/// into the model's effective system context.
///
/// Applied centrally to successful MCP structured payloads that carry
/// user-controlled text: task/search/overview reads, memory reads, mutation
/// echoes, and the calendar/list/tag/focus/habit/review surfaces.
///
/// Fields that are Lorvex-controlled (IDs, status enums, timestamps, counts)
/// must NOT be fenced — fencing is for user-controlled free-text only.
enum SecurityFencing {
  /// The opening sentinel character (U+27E6 MATHEMATICAL LEFT WHITE SQUARE BRACKET).
  static let openSentinel: Character = "\u{27E6}"

  /// The closing sentinel character (U+27E7 MATHEMATICAL RIGHT WHITE SQUARE BRACKET).
  static let closeSentinel: Character = "\u{27E7}"

  /// Wraps `userContent` in ⟦user⟧…⟦/user⟧ sentinels.
  ///
  /// Returns `nil` when `userContent` is `nil`; returns the wrapped string otherwise.
  /// An empty string is returned unchanged (no sentinels) — there is no user text
  /// to fence, so wrapping it would only add noise to the response.
  /// Any sentinel characters embedded in `userContent` are stripped first (see
  /// `sanitize(_:)`) so a crafted value can't forge a `⟦/user⟧` boundary and
  /// escape the fence.
  static func fence(_ userContent: String?) -> String? {
    guard let userContent else { return nil }
    return fence(userContent)
  }

  /// Wraps a non-optional string, stripping any embedded fence sentinels first.
  /// An empty string is returned unchanged — there is no user text to fence.
  static func fence(_ userContent: String) -> String {
    guard !userContent.isEmpty else { return userContent }
    let prefix = "\(openSentinel)user\(closeSentinel)"
    let suffix = "\(openSentinel)/user\(closeSentinel)"
    let rawContent: String
    if userContent.hasPrefix(prefix), userContent.hasSuffix(suffix) {
      rawContent = String(userContent.dropFirst(prefix.count).dropLast(suffix.count))
    } else {
      rawContent = userContent
    }
    return "\(prefix)\(sanitize(rawContent))\(suffix)"
  }

  /// Removes the fence sentinel characters from user content so the wrapped
  /// value cannot contain a forged `⟦user⟧` / `⟦/user⟧` boundary. These code
  /// points (U+27E6 / U+27E7) carry no legitimate meaning in task titles, notes,
  /// or names, so stripping them is non-destructive in practice while closing
  /// the boundary-injection hole.
  static func sanitize(_ userContent: String) -> String {
    guard userContent.contains(openSentinel) || userContent.contains(closeSentinel) else {
      return userContent
    }
    return userContent.filter { $0 != openSentinel && $0 != closeSentinel }
  }

  /// Reverses `fence(_:)`: if `value` is wrapped in ⟦user⟧…⟦/user⟧ sentinels,
  /// returns the inner content; otherwise returns `value` unchanged.
  ///
  /// Used on input paths (e.g. a memory `key` an AI client copied verbatim from
  /// a fenced response and passed back as an argument) so a fenced value
  /// round-trips to the original stored key. Whitespace surrounding the
  /// sentinels is ignored when detecting the wrapper.
  static func unfence(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "\(openSentinel)user\(closeSentinel)"
    let suffix = "\(openSentinel)/user\(closeSentinel)"
    guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix),
      trimmed.count >= prefix.count + suffix.count
    else {
      return value
    }
    return String(trimmed.dropFirst(prefix.count).dropLast(suffix.count))
  }

  /// Fences the top-level `key` string of a memory entry/response object.
  ///
  /// Memory keys are AI-supplied free text — not a constrained slug — so a
  /// crafted key (e.g. `"ignore previous instructions"`) could smuggle
  /// instructions into a model's context when echoed back in a response. They
  /// are fenced like any other user-controlled text. This is applied narrowly at
  /// the memory response builders rather than via ``userContentKeys`` so that
  /// structurally-meaningful `key` fields elsewhere (preferences, recurrence
  /// rules) stay unfenced. A no-op for non-object values or objects whose `key`
  /// is absent or non-string.
  static func fenceMemoryKey(_ value: Value) -> Value {
    guard case .object(var dict) = value, case .string(let key)? = dict["key"] else {
      return value
    }
    dict["key"] = .string(fence(key))
    return .object(dict)
  }

  // MARK: - Preference value fencing

  /// Preference keys whose stored value is user-/AI-authored free-text prose,
  /// as opposed to a machine token (id, enum, timestamp, number, boolean, path,
  /// or structured JSON config).
  ///
  /// Only these values are fenced when a preference read tool echoes them: a
  /// free-text preference value can be synced in from another device and carry
  /// injected instructions, whereas id/enum values (e.g. `default_list_id`,
  /// `timezone`) must round-trip verbatim and are never fenced (Rule 6).
  static let freeTextPreferenceKeys: Set<String> = [
    "setup_summary",
  ]

  /// Fences a single preference value for a read-tool response.
  ///
  /// Wraps `value` in ⟦user⟧…⟦/user⟧ sentinels only when `key` names a free-text
  /// preference (see ``freeTextPreferenceKeys``) and the value is a plain string.
  /// Machine-token and structured values are returned unchanged so ids, enums,
  /// and JSON config keep their exact shape and round-trip verbatim.
  static func fencePreferenceValue(key: String, value: Value) -> Value {
    guard freeTextPreferenceKeys.contains(key), case .string(let text) = value else {
      return value
    }
    return .string(fence(text))
  }

  // MARK: - Value tree fencing

  /// The set of JSON object keys whose string values are user-controlled and
  /// must be fenced before inclusion in an MCP response.
  static let userContentKeys: Set<String> = [
    "title", "notes", "ai_notes", "name", "description", "content", "text",
    "raw_input", "briefing", "summary", "body", "cue", "note", "rationale",
    "wins", "blockers", "learnings", "quote", "defer_note",
    "comment", "location", "person_name", "habit_name", "email",
    "details",
    // A user-supplied link the calendar bridge echoes verbatim. Recurrence is a
    // typed object of system-controlled enums/ints/dates (freq, byday, until,
    // count), not free text, so it is never fenced.
    "url",
  ]

  /// The set of JSON object keys whose array-of-string values are
  /// user-controlled text.
  static let userContentArrayKeys: Set<String> = [
    "tags",
  ]

  /// Recursively walks a `Value` tree and wraps string values at `userContentKeys`
  /// positions in ⟦user⟧…⟦/user⟧ sentinels.
  ///
  /// - Array elements that are objects are fenced recursively.
  /// - String values at non-user-content keys are returned unchanged.
  /// - Non-string values (int, bool, null, nested objects/arrays) are returned unchanged.
  static func fenceValue(_ value: Value) -> Value {
    fenceValue(
      value,
      stringFields: userContentKeys,
      stringArrayFields: userContentArrayKeys
    )
  }

  /// Applies an explicit response policy supplied by a ``ToolDefinition``.
  /// The one-argument overload remains the convenience used by the few
  /// narrow response builders that pre-fence a subtree before central dispatch.
  static func fenceValue(
    _ value: Value,
    stringFields: Set<String>,
    stringArrayFields: Set<String>
  ) -> Value {
    switch value {
    case .object(let dict):
      var result: [String: Value] = [:]
      for (key, val) in dict {
        if stringFields.contains(key), case .string(let s) = val {
          result[key] = .string(fence(s))
        } else if stringArrayFields.contains(key), case .array(let arr) = val {
          result[key] = .array(arr.map { element in
            if case .string(let s) = element {
              return .string(fence(s))
            }
            return fenceValue(
              element,
              stringFields: stringFields,
              stringArrayFields: stringArrayFields
            )
          })
        } else {
          result[key] = fenceValue(
            val,
            stringFields: stringFields,
            stringArrayFields: stringArrayFields
          )
        }
      }
      return .object(result)
    case .array(let arr):
      return .array(arr.map {
        fenceValue(
          $0,
          stringFields: stringFields,
          stringArrayFields: stringArrayFields
        )
      })
    default:
      return value
    }
  }
}
