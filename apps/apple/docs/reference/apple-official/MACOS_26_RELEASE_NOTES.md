# macOS Tahoe 26 Release Notes

Source: [macOS Tahoe 26 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes)

Last verified: 2026-07-10

## Apple Changes Relevant to Lorvex

- SwiftUI `Text` concatenation with `+` is deprecated because concatenated
  fragments cannot be reordered reliably for localization. Apple directs apps
  to use `Text` interpolation.
- Interpolating nonlocalized values into localized Foundation strings now
  produces stronger diagnostics instead of silently falling back to an
  unlocalized string.
- Apps linked on or after the version-26 SDK generation use TLS 1.2 as the
  default minimum in URL loading and Network framework paths.
- Text, TextEditor, and TextField use the string's contents to determine
  paragraph writing direction, and several Form/Section presentation defaults
  changed.

## Lorvex Mapping

- `CommandPaletteResultRow` constructs a highlighted result from three
  `Text + Text` operations. This is a direct OS 26 deprecation hit and a
  localization correctness issue.
- Xcode 26 warnings involving localized interpolation should be treated as
  correctness failures rather than silenced globally.
- Release smoke tests should cover right-to-left layout and grouped Forms on the
  version-26 runtime because an SDK rebuild can change presentation without a
  source change.
- Lorvex's network endpoints should already satisfy TLS 1.2 or later; archive
  verification should still ensure no helper or dependency assumes the older
  default.

