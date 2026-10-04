import LorvexCore
import SwiftUI

/// One tap-to-choose capsule in a field editor, such as "Tomorrow" or "45 min".
/// It is a neutral capsule with primary text until it names the field's current
/// value, then fills with the accent, so the current choice reads at a glance
/// and every label keeps full contrast. Both states are system button styles
/// of the same size, so choosing a chip never moves its neighbours, and the
/// current choice carries the selected trait for VoiceOver.
struct MobileFieldChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    let button = Button(title, action: action)
      .buttonBorderShape(.capsule)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    if isSelected {
      button.buttonStyle(.borderedProminent).tint(LorvexDesign.Palette.accent)
    } else {
      button.buttonStyle(.bordered).tint(.primary)
    }
  }
}
