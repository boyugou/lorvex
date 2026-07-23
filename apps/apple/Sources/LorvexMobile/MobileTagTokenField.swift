import LorvexCore
import SwiftUI

/// Token-style tag entry: existing tags render as removable chips, a text field
/// adds new tags on return, and matching `suggestions` surface below the field.
/// Binds to an ordered, de-duplicated tag list (case-insensitive uniqueness).
struct MobileTagTokenField: View {
  @Binding var tags: [String]
  let suggestions: [String]

  @State private var entry: String = ""
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !tags.isEmpty {
        MobileWrapLayout {
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
      #if os(iOS) || os(visionOS)
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
        MobileWrapLayout {
          ForEach(filteredSuggestions, id: \.self) { suggestion in
            Button {
              add(suggestion)
            } label: {
              Label(suggestion, systemImage: "plus")
                .font(LorvexDesign.Typography.tertiaryText)
                .labelStyle(.titleAndIcon)
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

  private func commitEntry() {
    let parts = entry.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    for part in parts { add(part) }
    entry = ""
    fieldFocused = true
  }

  private func add(_ raw: String) {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    guard !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
      return
    }
    tags.append(value)
  }

  private func remove(_ tag: String) {
    tags.removeAll { $0 == tag }
  }
}
