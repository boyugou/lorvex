import Foundation
import LorvexCore
import LorvexDomain

/// The text in one of the habit inspector's in-place fields, the name or the
/// encouragement, as typed for `habit`.
struct HabitFieldDraft: Equatable {
  enum Field: Equatable { case name, cue }

  /// The habit as stored when the text was typed; the text is a change only
  /// against this.
  let habit: LorvexHabit
  let field: Field
  let text: String

  /// The write the text calls for, or nil when it calls for none: a name that
  /// is empty once trimmed (a habit cannot have one; the field reverts) or
  /// either field trimmed to what is stored.
  var update: (name: String?, cue: Patch<String>)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch field {
    case .name:
      guard !trimmed.isEmpty, trimmed != habit.name else { return nil }
      return (trimmed, .unset)
    case .cue:
      guard trimmed != (habit.cue ?? "") else { return nil }
      return (nil, trimmed.isEmpty ? .clear : .set(trimmed))
    }
  }
}

/// The habit inspector's name and encouragement save when their field loses
/// focus or on Return. ⌘Q with the cursor in one asks the app whether to quit
/// before the field loses focus, so the field reports its text as it is typed
/// (``noteHabitFieldDraft(_:)``) and saves through ``commitHabitField(_:)``,
/// and Quit writes the text and waits for the writes
/// (``flushHabitFieldDraftForTermination()``).
extension AppStore {
  /// Records the text a focused field holds; nil when no field is being typed
  /// in.
  func noteHabitFieldDraft(_ draft: HabitFieldDraft?) {
    habitFieldDraft = draft
  }

  /// Saves `draft` when it changes the habit, and stops counting it as typed
  /// text. Quit waits for the write; one that fails shows its error and puts
  /// the text back as the draft, so Quit does not go ahead without it.
  func commitHabitField(_ draft: HabitFieldDraft) {
    if habitFieldDraft?.habit.id == draft.habit.id, habitFieldDraft?.field == draft.field {
      habitFieldDraft = nil
    }
    guard let update = draft.update else { return }
    let writeID = UUID()
    habitFieldWrites[writeID] = Task { [weak self] in
      guard let self else { return }
      let saved = await self.updateHabitFields(draft.habit, name: update.name, cue: update.cue)
      if !saved, self.habitFieldDraft == nil {
        self.habitFieldDraft = draft
      }
      self.habitFieldWrites[writeID] = nil
    }
  }

  /// Whether Quit must write a habit field's text or wait for its write.
  var hasHabitFieldDraftPendingForTermination: Bool {
    !habitFieldWrites.isEmpty || habitFieldDraft?.update != nil
  }

  /// Writes the text a habit field holds, and waits for every habit field
  /// write already running.
  func flushHabitFieldDraftForTermination() async {
    if let draft = habitFieldDraft { commitHabitField(draft) }
    while let write = habitFieldWrites.values.first {
      await write.value
    }
  }
}
