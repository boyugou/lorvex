import SwiftUI

/// The header of the New Habit and Edit Habit sheets: the habit's icon tile and
/// name (``MobileCreationHeader``), with its encouragement typed on the lines
/// under the name. The name's Next key moves to the encouragement and the
/// encouragement's Done key closes the keyboard, leaving the sheet's other
/// fields to taps. `focusesNameOnAppear` puts the cursor in the name as the
/// sheet opens, for a sheet that starts a new habit; identifiers are
/// `<idPrefix>.name`, `<idPrefix>.cue`, and the tile's
/// `<idPrefix>.appearance`.
struct MobileHabitSheetHeader: View {
  @Bindable var store: MobileStore
  let idPrefix: String
  var focusesNameOnAppear = false
  @FocusState private var focusedField: Field?

  private enum Field {
    case name
    case cue
  }

  var body: some View {
    MobileCreationHeader(
      icon: $store.habitDraft.icon,
      color: $store.habitDraft.color,
      fallbackIcon: "repeat",
      iconChoices: MobileIconChoices.habit,
      idPrefix: idPrefix,
      willChooseAppearance: { focusedField = nil }
    ) {
      TextField(
        String(
          localized: "habits.sheet.field.name_prompt", defaultValue: "Habit name",
          table: "Localizable", bundle: MobileL10n.bundle),
        text: $store.habitDraft.name,
        axis: .vertical
      )
      .lineLimit(1...)
      .textContentType(.none)
      .focused($focusedField, equals: .name)
      .submitLabel(.next)
      .onSubmit { focusedField = .cue }
      .accessibilityIdentifier("\(idPrefix).name")
    } subtitle: {
      // "Encouragement", not "Cue": a motivating line shown on the habit, not a
      // when-to-do trigger. The storage column stays `cue`.
      TextField(
        String(
          localized: "habits.sheet.field.encouragement_prompt",
          defaultValue: "Add an encouraging line", table: "Localizable", bundle: MobileL10n.bundle),
        text: $store.habitDraft.cue,
        axis: .vertical
      )
      .lineLimit(1...)
      .focused($focusedField, equals: .cue)
      .submitLabel(.done)
      .onSubmit { focusedField = nil }
      .accessibilityLabel(
        String(
          localized: "habits.sheet.field.encouragement_a11y",
          defaultValue: "Habit encouragement", table: "Localizable", bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("\(idPrefix).cue")
    }
    .onAppear { if focusesNameOnAppear { focusedField = .name } }
  }
}
