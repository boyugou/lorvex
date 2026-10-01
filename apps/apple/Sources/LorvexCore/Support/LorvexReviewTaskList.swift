import SwiftUI

/// A labeled list of tasks on a review page. Each row shows the task's title
/// and an optional quiet fact about it ("Due 3 days ago"), and opens the task
/// when tapped; under a pointer the row takes the hover fill, since a plain
/// title on the page ground does not otherwise say it can be clicked. When
/// the list is a capped slice of a count the page's sentence states,
/// `hiddenCount` is how many it leaves out, and a last line says so ("2 more")
/// so the sentence and the list never seem to disagree.
///
/// A row sets its fact at the trailing edge of the title's first line, and at
/// the accessibility text sizes under the title, whose whole text it then
/// shows, since beside a fact that large the title would hold a word a line.
///
/// With a ``Completion``, each row leads with a task circle that completes the
/// task: the circle fills at once and stays filled while the save runs, and
/// the page reloading its evidence then moves the task out of the list. The
/// circle's action is also offered to VoiceOver as a named action on the row.
///
/// With a ``Deferral``, the label line carries the section's action at its
/// trailing end as plain accent text ("Move All to Tomorrow", or "Move to
/// Tomorrow" over a single task), which plans every listed task that is not
/// yet planned for tomorrow or later for tomorrow. Each such row offers its
/// own move in its context menu and as a VoiceOver action, and on macOS also
/// as a button that takes the place of the row's fact while the pointer is
/// over the row. A moving row dims until the page reloads its evidence; a
/// moved task stays listed, since moving its plan does not change its due day,
/// and its fact then says when it is planned.
///
/// The list's identifier names the section; each row's identifier appends the
/// task id ("review.week.overdue.<id>"), the circle's appends ".complete", the
/// row's move button ".tomorrow", the section action "tomorrow", and the count
/// line "more".
public struct LorvexReviewTaskList: View {
  /// What a row's circle does: the platform's "Complete" wording, for its
  /// tooltip and VoiceOver action, and the completion itself.
  public struct Completion {
    public var label: String
    public var complete: (String) async -> Void

    public init(label: String, complete: @escaping (String) async -> Void) {
      self.label = label
      self.complete = complete
    }
  }

  /// What moving to tomorrow does: tomorrow's day key (`YYYY-MM-DD`), which
  /// tells a task already planned for tomorrow or later from one still to
  /// move; the section action's wording for the count of tasks it moves; a
  /// row's own wording; and the move itself, given the ids.
  public struct Deferral {
    public var tomorrowKey: String
    public var sectionLabel: (Int) -> String
    public var rowLabel: String
    public var move: ([String]) async -> Void

    public init(
      tomorrowKey: String, sectionLabel: @escaping (Int) -> String, rowLabel: String,
      move: @escaping ([String]) async -> Void
    ) {
      self.tomorrowKey = tomorrowKey
      self.sectionLabel = sectionLabel
      self.rowLabel = rowLabel
      self.move = move
    }

    /// Whether `task` still has a move to make: it is not yet planned for
    /// tomorrow or a later day.
    public func canMove(_ task: ReviewTaskSummary) -> Bool {
      guard let planned = task.plannedDate else { return true }
      return planned < tomorrowKey
    }
  }

  private let label: String
  private let tasks: [ReviewTaskSummary]
  private let hiddenCount: Int
  private let moreLine: (Int) -> String
  private let identifier: String
  private let detail: (ReviewTaskSummary) -> String?
  private let completion: Completion?
  private let deferral: Deferral?
  private let openTask: (String) -> Void

  @State private var hoveredTaskID: String?
  @State private var completingTaskIDs: Set<String> = []
  @State private var movingTaskIDs: Set<String> = []
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    label: String,
    tasks: [ReviewTaskSummary],
    hiddenCount: Int,
    moreLine: @escaping (Int) -> String,
    identifier: String,
    detail: @escaping (ReviewTaskSummary) -> String? = { _ in nil },
    completion: Completion? = nil,
    deferral: Deferral? = nil,
    openTask: @escaping (String) -> Void
  ) {
    self.label = label
    self.tasks = tasks
    self.hiddenCount = hiddenCount
    self.moreLine = moreLine
    self.identifier = identifier
    self.detail = detail
    self.completion = completion
    self.deferral = deferral
    self.openTask = openTask
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      labelLine
      ForEach(tasks) { task in
        row(task)
      }
      if hiddenCount > 0 {
        Text(moreLine(hiddenCount))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("\(identifier).more")
      }
    }
    .accessibilityIdentifier(identifier)
  }

  @ViewBuilder
  private var labelLine: some View {
    let movable = deferral.map { deferral in tasks.filter(deferral.canMove) } ?? []
    if let deferral, !movable.isEmpty {
      // The action sits beside the label, and under it at accessibility
      // sizes, where the two no longer fit one line.
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: LorvexDesign.Spacing.xxs))
        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
      layout {
        LorvexPageLabel(label)
        Button(deferral.sectionLabel(movable.count)) {
          Task { await move(movable.map(\.id), with: deferral) }
        }
        .buttonStyle(.plain)
        .font(LorvexDesign.Typography.pageLabel)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .disabled(!movingTaskIDs.isEmpty)
        .accessibilityIdentifier("\(identifier).tomorrow")
      }
    } else {
      LorvexPageLabel(label)
    }
  }

  private func row(_ task: ReviewTaskSummary) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      if let completion {
        circle(task, completion: completion)
      }
      openButton(task, showsFact: !showsMoveButton(task))
        .accessibilityActions {
          if let completion {
            Button(completion.label) { Task { await complete(task, with: completion) } }
          }
          if let deferral, deferral.canMove(task) {
            Button(deferral.rowLabel) { Task { await move([task.id], with: deferral) } }
          }
        }
      #if os(macOS)
        if showsMoveButton(task), let deferral {
          moveButton(task, deferral: deferral)
        }
      #endif
    }
    // The fill reaches past the row on both sides, and the negative padding
    // gives that reach back, so the row stays aligned with the label above.
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .background {
      if hoveredTaskID == task.id {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(LorvexDesign.Palette.hoverFill)
      }
    }
    .padding(.horizontal, -LorvexDesign.Spacing.s)
    .opacity(movingTaskIDs.contains(task.id) ? 0.4 : 1)
    #if os(macOS) || os(iOS)
      .onHover { inside in
        if inside {
          hoveredTaskID = task.id
        } else if hoveredTaskID == task.id {
          hoveredTaskID = nil
        }
      }
    #endif
    .contextMenu {
      if let completion {
        Button(completion.label, systemImage: "checkmark.circle") {
          Task { await complete(task, with: completion) }
        }
      }
      if let deferral, deferral.canMove(task) {
        Button(deferral.rowLabel, systemImage: "arrow.turn.up.right") {
          Task { await move([task.id], with: deferral) }
        }
      }
    }
    .transition(.opacity)
  }

  /// Whether the row shows its move button in place of its fact: on macOS,
  /// while the pointer is over a row that can move and is not moving yet.
  private func showsMoveButton(_ task: ReviewTaskSummary) -> Bool {
    #if os(macOS)
      guard let deferral, hoveredTaskID == task.id else { return false }
      return deferral.canMove(task) && !movingTaskIDs.contains(task.id)
    #else
      false
    #endif
  }

  private func moveButton(_ task: ReviewTaskSummary, deferral: Deferral) -> some View {
    Button {
      Task { await move([task.id], with: deferral) }
    } label: {
      Label(deferral.rowLabel, systemImage: "arrow.turn.up.right")
        .labelStyle(.titleAndIcon)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityHidden(true)
    .accessibilityIdentifier("\(identifier).\(task.id).tomorrow")
  }

  private func move(_ ids: [String], with deferral: Deferral) async {
    let fresh = ids.filter { !movingTaskIDs.contains($0) }
    guard !fresh.isEmpty else { return }
    withAnimation(.snappy(duration: 0.18)) { movingTaskIDs.formUnion(fresh) }
    await deferral.move(fresh)
    // A saved move has already reloaded the list without these rows; a failed
    // one leaves them, back at full strength.
    withAnimation(.snappy(duration: 0.18)) { movingTaskIDs.subtract(fresh) }
  }

  private func circle(_ task: ReviewTaskSummary, completion: Completion) -> some View {
    let isCompleting = completingTaskIDs.contains(task.id)
    return Button {
      Task { await complete(task, with: completion) }
    } label: {
      Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(
          isCompleting ? AnyShapeStyle(LorvexDesign.Palette.done) : AnyShapeStyle(.secondary))
        .contentTransition(.symbolEffect(.replace))
        .contentShape(.interaction, Circle().inset(by: -6))
    }
    .buttonStyle(.plain)
    .disabled(isCompleting)
    .help(completion.label)
    .accessibilityHidden(true)
    .accessibilityIdentifier("\(identifier).\(task.id).complete")
  }

  private func complete(_ task: ReviewTaskSummary, with completion: Completion) async {
    guard !completingTaskIDs.contains(task.id) else { return }
    withAnimation(.snappy(duration: 0.18)) { _ = completingTaskIDs.insert(task.id) }
    await completion.complete(task.id)
    // A saved completion has already reloaded the list without this row; a
    // failed one leaves the row, whose circle empties again.
    withAnimation(.snappy(duration: 0.18)) { _ = completingTaskIDs.remove(task.id) }
  }

  private func openButton(_ task: ReviewTaskSummary, showsFact: Bool) -> some View {
    Button { openTask(task.id) } label: {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            title(task)
            if showsFact, let fact = detail(task) {
              factText(fact)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          HStack(alignment: .firstTextBaseline) {
            title(task)
              .lineLimit(2)
            Spacer(minLength: LorvexDesign.Spacing.s)
            if showsFact, let fact = detail(task) {
              factText(fact)
            }
          }
        }
      }
      .padding(.vertical, LorvexDesign.Spacing.xxs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("\(identifier).\(task.id)")
  }

  private func title(_ task: ReviewTaskSummary) -> some View {
    Text(task.title)
      .font(LorvexDesign.Typography.primaryText)
      .foregroundStyle(.primary)
      .multilineTextAlignment(.leading)
  }

  private func factText(_ fact: String) -> some View {
    Text(fact)
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .monospacedDigit()
  }
}
