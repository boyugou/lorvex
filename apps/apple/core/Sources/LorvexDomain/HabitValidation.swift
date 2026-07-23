import Foundation

// MARK: - Habit draft validation

/// Sanitize + length-cap + token-validate a habit create/update draft into the
/// validated shape the store persists. Free text (name, cue) is run through
/// `UnicodeHygiene` and the `ValidationLimits` caps; `icon` is validated as a
/// machine token (SF Symbol name or single emoji, never sanitized); `color` is
/// hex-validated. Kept in its own file so `Habits.swift` stays under the
/// god-file guardrail.

// MARK: - Validated outputs

/// Validated, ready-to-persist habit-create payload. Constructed only via
/// ``validateHabitCreateDraft(_:)`` so the cadence consistency / length /
/// color / lookup_key invariants cannot be bypassed by direct field
/// assignment.
public struct ValidatedHabitCreate: Sendable, Equatable {
  public let name: String
  public let icon: String?
  public let color: String?
  public let cue: String?
  public let frequency: HabitCadence
  public let targetCount: Int64
  public let lookupKey: String

  fileprivate init(
    name: String,
    icon: String?,
    color: String?,
    cue: String?,
    frequency: HabitCadence,
    targetCount: Int64,
    lookupKey: String
  ) {
    self.name = name
    self.icon = icon
    self.color = color
    self.cue = cue
    self.frequency = frequency
    self.targetCount = targetCount
    self.lookupKey = lookupKey
  }
}

/// Validated habit-update patch. Constructed only via
/// ``validateHabitUpdateDraft(_:)``.
public struct ValidatedHabitUpdate: Sendable, Equatable {
  public let name: String?
  public let icon: Patch<String>
  public let color: Patch<String>
  public let cue: Patch<String>
  public let frequency: HabitCadence?
  public let targetCount: Int64?
  public let archived: ArchiveAction
  public let lookupKey: String?

  fileprivate init(
    name: String?,
    icon: Patch<String>,
    color: Patch<String>,
    cue: Patch<String>,
    frequency: HabitCadence?,
    targetCount: Int64?,
    archived: ArchiveAction,
    lookupKey: String?
  ) {
    self.name = name
    self.icon = icon
    self.color = color
    self.cue = cue
    self.frequency = frequency
    self.targetCount = targetCount
    self.archived = archived
    self.lookupKey = lookupKey
  }
}

// MARK: - Draft validation

public func validateHabitCreateDraft(
  _ draft: HabitCreateDraft
) throws -> ValidatedHabitCreate {
  let name = try normalizeHabitName(draft.name)
  let icon = try normalizeOptionalHabitIcon(draft.icon)
  let color = try normalizeOptionalHabitColor(draft.color)
  let cue = try normalizeOptionalHabitText(
    draft.cue, field: "cue", max: ValidationLimits.maxHabitCueLength)
  let frequency = draft.frequency ?? .daily
  let targetCount = normalizeHabitTargetCount(draft.targetCount)
  let lookupKey = normalizeLookupKey(name)
  return ValidatedHabitCreate(
    name: name, icon: icon, color: color, cue: cue,
    frequency: frequency, targetCount: targetCount, lookupKey: lookupKey)
}

public func validateHabitUpdateDraft(
  _ draft: HabitUpdateDraft
) throws -> ValidatedHabitUpdate {
  let name = try draft.name.map(normalizeHabitName)
  let icon = try normalizeOptionalPatchIcon(draft.icon)
  let color = try normalizeOptionalPatchColor(draft.color)
  let cue = try normalizeOptionalPatchText(
    draft.cue, field: "cue", max: ValidationLimits.maxHabitCueLength)
  let targetCount = draft.targetCount.map { max($0, 1) }
  let lookupKey = name.map { normalizeLookupKey($0) }
  return ValidatedHabitUpdate(
    name: name, icon: icon, color: color, cue: cue,
    frequency: draft.frequency, targetCount: targetCount,
    archived: draft.archived, lookupKey: lookupKey)
}

private func normalizeHabitName(_ value: String) throws -> String {
  let sanitized = UnicodeHygiene.sanitizeUserText(value)
  let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty || ValidationText.isVisuallyEmpty(trimmed) {
    throw ValidationError.empty("habit name")
  }
  if case let .failure(e) = ValidationText.validateStringLength(
    trimmed, field: "name", max: ValidationLimits.maxTitleLength)
  {
    throw e
  }
  return trimmed
}

private func normalizeOptionalHabitText(
  _ value: String?, field: String, max: Int
) throws -> String? {
  guard let value else { return nil }
  let sanitized = UnicodeHygiene.sanitizeUserText(value)
  let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return nil }
  if case let .failure(e) = ValidationText.validateStringLength(
    trimmed, field: field, max: max)
  {
    throw e
  }
  return trimmed
}

private func normalizeOptionalPatchText(
  _ value: Patch<String>, field: String, max: Int
) throws -> Patch<String> {
  switch value {
  case .unset: return .unset
  case .clear: return .clear
  case let .set(v):
    if let s = try normalizeOptionalHabitText(v, field: field, max: max) {
      return .set(s)
    } else {
      return .clear
    }
  }
}

/// Trim, drop-if-blank, and token-validate a habit `icon` (SF Symbol name or
/// single emoji). Unlike free text the icon is NOT sanitized — it is a machine
/// token, and ``ValidationIcon/validateIconToken(_:field:)`` rejects any
/// invisible / bidi / control codepoint outright.
private func normalizeOptionalHabitIcon(_ value: String?) throws -> String? {
  guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
    !trimmed.isEmpty
  else { return nil }
  if case let .failure(e) = ValidationIcon.validateIconToken(trimmed, field: "icon") {
    throw e
  }
  return trimmed
}

private func normalizeOptionalPatchIcon(
  _ value: Patch<String>
) throws -> Patch<String> {
  switch value {
  case .unset: return .unset
  case .clear: return .clear
  case let .set(v):
    if let s = try normalizeOptionalHabitIcon(v) {
      return .set(s)
    } else {
      return .clear
    }
  }
}

private func normalizeOptionalHabitColor(_ value: String?) throws -> String? {
  let color = try normalizeOptionalHabitText(
    value, field: "color", max: ValidationLimits.maxShortTextLength)
  if let color {
    if case let .failure(e) = ValidationFormat.validateHexColorField(color, field: "color") {
      throw e
    }
  }
  return color
}

private func normalizeOptionalPatchColor(
  _ value: Patch<String>
) throws -> Patch<String> {
  switch value {
  case .unset: return .unset
  case .clear: return .clear
  case let .set(v):
    if let s = try normalizeOptionalHabitColor(v) {
      return .set(s)
    } else {
      return .clear
    }
  }
}

private func normalizeHabitTargetCount(_ value: Int64?) -> Int64 {
  max(value ?? 1, 1)
}
