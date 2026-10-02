import LorvexCore
import SwiftUI

/// The picker behind the task detail's Tags row: a field that finds a tag or
/// names a new one, over every tag in use, each a row that puts the tag on the
/// task or takes it off. The task's own tags are checked and lead the list.
///
/// Typing narrows the rows to the tags containing the text, an exact match
/// first; when no tag matches exactly, a "New Tag" row for the text leads.
/// ↑/↓ move the highlight and Return activates it, as in the dependency
/// picker; with nothing highlighted, Return adds the typed text. A typed comma
/// commits what precedes it, so a pasted "a, b" adds both. A typed tag that
/// differs only in case from a tag in use takes that tag's spelling.
///
/// The rows keep the order they opened in, so a row does not move from under
/// the pointer when it is toggled; a tag created here joins the top.
///
/// The picker edits `tagsText`, the detail draft's comma-separated tags,
/// which the detail saves as it does every field.
struct TaskDetailTagsPicker: View {
  @Binding var tagsText: String
  let loadKnownTags: () async -> [String]

  @State private var query = ""
  /// The tags the rows list, in their order: the task's tags when the picker
  /// opened, then the other tags in use by name, then any created here at the top.
  @State private var order: [String] = []
  @State private var highlighted: Int?
  @FocusState private var isFieldFocused: Bool

  private enum Row: Hashable {
    case create(String)
    case tag(String)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      InspectorEditorHeader(title: Copy.title, hint: Copy.hint)
      field
      let rows = rows
      if rows.isEmpty {
        Text(Copy.empty)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("task.detail.tags.empty")
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: 0) {
              ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                rowView(row, index: index)
                  .id(row)
              }
            }
          }
          .scrollBounceBehavior(.basedOnSize)
          .frame(maxHeight: 240)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, -LorvexDesign.Spacing.s)
          .onChange(of: highlighted) { _, index in
            guard let index, rows.indices.contains(index) else { return }
            proxy.scrollTo(rows[index])
          }
        }
      }
    }
    .frame(width: 280, alignment: .leading)
    // A single-line field leaves the vertical arrows to the picker.
    .onKeyPress(.upArrow) {
      moveHighlight(-1)
      return .handled
    }
    .onKeyPress(.downArrow) {
      moveHighlight(1)
      return .handled
    }
    .accessibilityIdentifier("task.detail.tags.picker")
    .task {
      let known = await loadKnownTags()
      let tags = applied
      order = tags + known.filter { tag in !tags.contains { Self.same($0, tag) } }
      isFieldFocused = true
    }
  }

  private var field: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: "number")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField(Copy.fieldPrompt, text: $query)
        .textFieldStyle(.plain)
        .focused($isFieldFocused)
        .onSubmit(submit)
        .onChange(of: query) { _, newValue in
          if newValue.contains(",") {
            for piece in newValue.split(separator: ",") { add(String(piece)) }
            query = ""
          }
          highlighted = query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : 0
        }
        .accessibilityLabel(Copy.title)
        .accessibilityIdentifier("task.detail.tags.field")
    }
    .font(LorvexDesign.Typography.primaryText)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous))
  }

  @ViewBuilder
  private func rowView(_ row: Row, index: Int) -> some View {
    switch row {
    case .create(let name):
      TaskDetailChoiceRow(
        title: Copy.newTag(name), systemImage: "plus", isHighlighted: highlighted == index,
        accessibilityIdentifier: "task.detail.tags.create"
      ) { activate(row) }
      .onHover { if $0 { highlighted = index } }
    case .tag(let name):
      TaskDetailChoiceRow(
        title: name, isOn: isApplied(name), isHighlighted: highlighted == index,
        accessibilityIdentifier: "task.detail.tags.row"
      ) { activate(row) }
      .onHover { if $0 { highlighted = index } }
    }
  }

  // MARK: - Rows

  /// The task's tags, trimmed and in order.
  private var applied: [String] {
    tagsText
      .split(separator: ",", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private var rows: [Row] {
    let typed = query.trimmingCharacters(in: .whitespaces)
    // A tag put on the task from elsewhere while the picker is open still lists.
    var tags = applied.filter { tag in !order.contains { Self.same($0, tag) } } + order
    guard !typed.isEmpty else { return tags.map(Row.tag) }
    tags = tags.filter { $0.localizedStandardContains(typed) }
    if let exact = tags.firstIndex(where: { Self.same($0, typed) }) {
      tags.insert(tags.remove(at: exact), at: 0)
      return tags.map(Row.tag)
    }
    return [.create(typed)] + tags.map(Row.tag)
  }

  private func isApplied(_ tag: String) -> Bool {
    applied.contains { Self.same($0, tag) }
  }

  private static func same(_ a: String, _ b: String) -> Bool {
    a.caseInsensitiveCompare(b) == .orderedSame
  }

  // MARK: - Actions

  private func moveHighlight(_ delta: Int) {
    let count = rows.count
    guard count > 0 else { return }
    guard let current = highlighted else {
      highlighted = delta > 0 ? 0 : count - 1
      return
    }
    highlighted = (current + delta + count) % count
  }

  private func submit() {
    let rows = rows
    if let index = highlighted, rows.indices.contains(index) {
      // Return on the tag just typed in full leaves it on the task rather
      // than taking it off.
      if case .tag(let name) = rows[index], isApplied(name),
        Self.same(name, query.trimmingCharacters(in: .whitespaces))
      {
        query = ""
        return
      }
      activate(rows[index])
    } else {
      add(query)
      query = ""
    }
  }

  private func activate(_ row: Row) {
    switch row {
    case .create(let name):
      add(name)
    case .tag(let name):
      if isApplied(name) { remove(name) } else { add(name) }
    }
    query = ""
  }

  private func add(_ raw: String) {
    let typed = raw.trimmingCharacters(in: .whitespaces)
    guard !typed.isEmpty, !isApplied(typed) else { return }
    let tag = order.first { Self.same($0, typed) } ?? typed
    if !order.contains(where: { Self.same($0, tag) }) {
      order.insert(tag, at: 0)
    }
    tagsText = (applied + [tag]).joined(separator: ", ")
  }

  private func remove(_ tag: String) {
    tagsText = applied.filter { !Self.same($0, tag) }.joined(separator: ", ")
  }

  private enum Copy {
    static var title: String { TaskDetailSentenceCopy.addTag }
    static var hint: String {
      String(
        localized: "task_detail.tags.hint", defaultValue: "Words that group tasks across lists.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    static var fieldPrompt: String {
      String(
        localized: "task_detail.tags.field", defaultValue: "Find or add a tag", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    static var empty: String {
      String(
        localized: "task_detail.tags.empty", defaultValue: "No tags yet. Type one and press Return.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    static func newTag(_ name: String) -> String {
      String(
        format: String(
          localized: "task_detail.tags.new", defaultValue: "New Tag “%@”", table: "Localizable",
          bundle: LorvexL10n.bundle),
        name)
    }
  }
}
