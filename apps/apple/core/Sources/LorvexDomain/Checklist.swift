import Foundation

/// Task checklist domain helpers.
///
/// Checklist items are first-class operational state.

public let maxTaskChecklistItems: Int = 200
public let maxTaskChecklistItemTextLength: Int = 1_000

/// Validate a single checklist item's text. Length is measured in Unicode
/// scalars (codepoints) — matching the sister
/// title / body / tag validators — so a multibyte CJK / emoji string is not
/// rejected at ~1/3 of the documented MAX.
public func validateTaskChecklistItemText(_ text: String) throws {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty {
    throw ValidationError.empty("task_checklist_item.text")
  }
  let charCount = text.unicodeScalars.count
  if charCount > maxTaskChecklistItemTextLength {
    throw ValidationError.tooLong(
      field: "task_checklist_item.text",
      max: maxTaskChecklistItemTextLength,
      actual: charCount
    )
  }
}

/// Validate that the checklist item count is within the per-task cap.
public func validateTaskChecklistItemCount(_ count: Int) throws {
  if count > maxTaskChecklistItems {
    throw ValidationError.outOfRange(
      field: "task_checklist_items",
      min: 0,
      max: Int64(maxTaskChecklistItems),
      actual: Int64(count)
    )
  }
}
