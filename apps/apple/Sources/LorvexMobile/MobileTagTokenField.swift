import LorvexCore
import SwiftUI

/// Token-style tag entry: existing tags render as removable chips, a text field
/// adds new tags on return, and matching `suggestions` surface below the field.
/// Binds to an ordered, de-duplicated tag list (case-insensitive uniqueness).
///
/// The text typed but not yet added lives in `entry`, which the caller owns, so
/// a Save or Done that arrives before Return keeps it: the caller folds it into
/// the tags with ``merging(_:into:)`` before saving.
struct MobileTagTokenField: View {
  @Binding var tags: [String]
  let suggestions: [String]
  @Binding var entry: String

  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !tags.isEmpty {
        LorvexFlowLayout(spacing: LorvexDesign.Spacing.sm, lineSpacing: LorvexDesign.Spacing.sm, fillsWidth: true) {
          ForEach(tags, id: \.self) { tag in
            tagChip(tag)
          }
        }
      }

      TextField(
        String(
          localized: "tags.add_placeholder", defaultValue: "Add tag", table: "Localizable",
          bundle: MobileL10n.bundle), text: $entry
      )
      .focused($fieldFocused)
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
        .submitLabel(.done)
      #endif
      .onSubmit { commitEntry() }
      .onChange(of: entry) { _, newValue in
        if newValue.contains(",") {
          commitEntry()
        }
      }

      if !filteredSuggestions.isEmpty {
        LorvexFlowLayout(spacing: LorvexDesign.Spacing.sm, lineSpacing: LorvexDesign.Spacing.sm, fillsWidth: true) {
          ForEach(filteredSuggestions, id: \.self) { suggestion in
            Button {
              add(suggestion)
            } label: {
              // An explicit HStack, not a `Label`: inside a form row a `Label`
              // sets its glyph in a wide icon column, far from the tag name.
              HStack(spacing: LorvexDesign.Spacing.xs) {
                Image(systemName: "plus").imageScale(.small)
                Text(suggestion)
              }
              .font(LorvexDesign.Typography.tertiaryText)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
          }
        }
      }
    }
  }

  private func tagChip(_ tag: String) -> some View {
    HStack(spacing: 4) {
      Text(tag)
        .font(LorvexDesign.Typography.primaryText)
      Button {
        remove(tag)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(LorvexDesign.Typography.tertiaryText)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel(
        String(
          format: String(
            localized: "tags.remove.a11y", defaultValue: "Remove tag %@", table: "Localizable",
            bundle: MobileL10n.bundle), tag))
    }
    .padding(.leading, 10)
    .padding(.trailing, 6)
    .padding(.vertical, 5)
    .background(.tint.opacity(0.15), in: Capsule())
  }

  private var filteredSuggestions: [String] {
    let existing = Set(tags.map { $0.lowercased() })
    let query = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return suggestions.filter { suggestion in
      guard !existing.contains(suggestion.lowercased()) else { return false }
      guard !query.isEmpty else { return true }
      return suggestion.lowercased().contains(query)
    }
  }

  /// `tags` with each comma-separated tag of `entry` appended, trimmed, and
  /// skipped when blank or already present in any letter case.
  nonisolated static func merging(_ entry: String, into tags: [String]) -> [String] {
    var merged = tags
    for part in entry.split(separator: ",") {
      let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty,
        !merged.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
      else { continue }
      merged.append(value)
    }
    return merged
  }

  private func commitEntry() {
    tags = Self.merging(entry, into: tags)
    entry = ""
    fieldFocused = true
  }

  private func add(_ suggestion: String) {
    tags = Self.merging(suggestion, into: tags)
  }

  private func remove(_ tag: String) {
    tags.removeAll { $0 == tag }
  }
}
