import SwiftUI

/// A labeled list of tasks on a review page. Each row shows the task's title
/// and an optional quiet fact about it ("Due 3 days ago"), and opens the task
/// when tapped; under a pointer the row takes the hover fill, since a plain
/// title on the page ground does not otherwise say it can be clicked. When
/// the list is a capped slice of a count the page's sentence states,
/// `hiddenCount` is how many it leaves out, and a last line says so ("2 more")
/// so the sentence and the list never seem to disagree.
///
/// A row sets its fact at the trailing end of the title's line. On macOS the
/// title takes up to two lines beside it. On iPhone and iPad the fact keeps
/// that place only while the title fits one line beside it; otherwise it
/// stands under the title, which then has the whole width, so a long fact
/// ("Planned for Wed, Oct 7") never narrows the title to a few words a line.
/// At the accessibility text sizes the fact is always under the title, whose
/// whole text it then shows, since beside a fact that large the title would
/// hold a word a line.
///
/// With a ``Completion``, each row leads with a task circle that completes the
/// task: the circle fills at once and stays filled while the save runs, and
/// the page reloading its evidence then moves the task out of the list. The
/// circle's action is also offered to VoiceOver as a named action on the row.
///
/// Daily review can fold a long list and schedule all eligible tasks in one action.
/// Each editable row also offers tomorrow, a date picker and Someday.
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
    public var preview: (() -> Void)?
    public var rowLabel: String
    public var arrange: ([ReviewTaskSummary], ReviewTaskDestination) async -> Void

    public init(
      tomorrowKey: String, sectionLabel: @escaping (Int) -> String, rowLabel: String,
      preview: (() -> Void)? = nil,
      arrange: @escaping ([ReviewTaskSummary], ReviewTaskDestination) async -> Void
    ) {
      self.tomorrowKey = tomorrowKey
      self.sectionLabel = sectionLabel
      self.rowLabel = rowLabel
      self.preview = preview
      self.arrange = arrange
    }

    /// Whether `task` still has a move to make: it is not yet planned for
    /// tomorrow or a later day.
    public func canMove(_ task: ReviewTaskSummary) -> Bool {
      task.canMoveToTomorrow(tomorrowKey)
    }
  }

  private let label: String
  private let tasks: [ReviewTaskSummary]
  private let previewLimit: Int?
  private let hiddenCount: Int
  private let moreLine: (Int) -> String
  private let identifier: String
  private let detail: (ReviewTaskSummary) -> String?
  private let completion: Completion?
  private let deferral: Deferral?
  private let openTask: (String) -> Void

  /// The vertical padding that takes the section action's one line of text to
  /// a tap target of about 44pt.
  private static let actionTapPadding: CGFloat = 13

  @State private var expanded = false
  @State private var scheduling: ReviewTaskSummary?
  @State private var hoveredTaskID: String?
  @State private var completingTaskIDs: Set<String> = []
  @State private var movingTaskIDs: Set<String> = []
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    label: String,
    tasks: [ReviewTaskSummary],
    hiddenCount: Int,
    previewLimit: Int? = nil,
    moreLine: @escaping (Int) -> String,
    identifier: String,
    detail: @escaping (ReviewTaskSummary) -> String? = { _ in nil },
    completion: Completion? = nil,
    deferral: Deferral? = nil,
    openTask: @escaping (String) -> Void
  ) {
    self.label = label
    self.tasks = tasks
    self.previewLimit = previewLimit
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
      let visibleCount = expanded ? tasks.count : min(previewLimit ?? tasks.count, tasks.count)
      ForEach(tasks.prefix(visibleCount)) { task in
        row(task)
      }
      if let previewLimit, tasks.count > previewLimit {
        Button {
          lorvexAnimated(.snappy) { expanded.toggle() }
        } label: {
          Label(expanded ? ReviewPlanCopy.less : moreLine(tasks.count - previewLimit),
            systemImage: expanded ? "chevron.up" : "chevron.down")
            .font(LorvexDesign.Typography.secondaryText)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("\(identifier).expand")
      }
      if hiddenCount > 0 {
        Text(moreLine(hiddenCount))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("\(identifier).more")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
    #if os(macOS) || os(iOS)
    .sheet(item: $scheduling) { task in
      if let deferral {
        ReviewScheduleSheet(task: task, tomorrow: deferral.tomorrowKey) { day in
          await arrange([task], for: .day(day), with: deferral)
        }
      }
    }
    #endif
  }

  @ViewBuilder
  private var labelLine: some View {
    let movable = deferral.map { deferral in tasks.filter(deferral.canMove) } ?? []
    if let deferral, !movable.isEmpty {
      // The action sits beside the label while both fit on one line, and
      // under it when they do not: a longer translation or an accessibility
      // text size. Beside the label it keeps its ideal width: an HStack
      // offers each of two flexible children half the row, which would wrap
      // or cut the action even where the row has room.
      let action = Button {
        if let preview = deferral.preview {
          preview()
        } else {
          Task { await arrange(movable, for: .day(deferral.tomorrowKey), with: deferral) }
        }
      } label: {
        // The words are one line tall. The label's padding lifts the tap
        // target to about 44pt, and the negative padding outside the button
        // gives the layout that height back.
        HStack(spacing: LorvexDesign.Spacing.xs) {
          Text(deferral.sectionLabel(movable.count))
          if movable.count > 1 {
            Text(movable.count, format: .number).monospacedDigit()
              .padding(.horizontal, LorvexDesign.Spacing.xs)
              .background(.quaternary, in: Capsule())
          }
        }
          .padding(.vertical, Self.actionTapPadding)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.vertical, -Self.actionTapPadding)
      .font(LorvexDesign.Typography.pageLabel)
      .foregroundStyle(LorvexDesign.Palette.accent)
      .disabled(!movingTaskIDs.isEmpty)
      .accessibilityIdentifier("\(identifier).tomorrow")
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          LorvexPageLabel(label)
          action.fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          LorvexPageLabel(label)
          action
        }
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
      openButton(task)
        .accessibilityActions {
          if let completion {
            Button(completion.label) { Task { await complete(task, with: completion) } }
          }
        }
      #if os(macOS) || os(iOS)
      if let deferral {
        Menu {
          planningActions(task, deferral: deferral)
        } label: {
          Image(systemName: "ellipsis.circle")
            .foregroundStyle(.secondary)
            #if os(iOS)
              .frame(width: 44, height: 44)
            #else
              .padding(LorvexDesign.Spacing.xs)
            #endif
            .contentShape(Rectangle())
        }
        #if os(macOS)
          .menuStyle(.borderlessButton)
        #else
          .buttonStyle(.borderless)
        #endif
        .fixedSize()
        .disabled(movingTaskIDs.contains(task.id))
        .accessibilityLabel(ReviewPlanCopy.schedule + ", " + task.title)
        .accessibilityIdentifier("\(identifier).\(task.id).plan")
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
      if let deferral { planningActions(task, deferral: deferral) }
    }
    .transition(.opacity)
  }

  @ViewBuilder
  private func planningActions(_ task: ReviewTaskSummary, deferral: Deferral) -> some View {
    if deferral.canMove(task) {
      Button(deferral.rowLabel, systemImage: "arrow.uturn.forward") {
        Task { await arrange([task], for: .day(deferral.tomorrowKey), with: deferral) }
      }
    }
    #if os(macOS) || os(iOS)
    Button(ReviewPlanCopy.setDate, systemImage: "calendar") { scheduling = task }
    #endif
    Button(LorvexTask.Status.someday.localizedName, systemImage: "tray") {
      Task { await arrange([task], for: .someday, with: deferral) }
    }
  }

  private func arrange(_ tasks: [ReviewTaskSummary], for destination: ReviewTaskDestination,
    with deferral: Deferral) async {
    let fresh = tasks.filter { !movingTaskIDs.contains($0.id) }
    guard !fresh.isEmpty else { return }
    let ids = fresh.map(\.id)
    lorvexAnimated(.snappy(duration: 0.18)) { movingTaskIDs.formUnion(ids) }
    await deferral.arrange(fresh, destination)
    lorvexAnimated(.snappy(duration: 0.18)) { movingTaskIDs.subtract(ids) }
  }

  private func circle(_ task: ReviewTaskSummary, completion: Completion) -> some View {
    let isCompleting = completingTaskIDs.contains(task.id)
    let outset = LorvexReviewRowMetrics.circleOutset
    return Button {
      Task { await complete(task, with: completion) }
    } label: {
      Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(
          isCompleting ? AnyShapeStyle(LorvexDesign.Palette.done) : AnyShapeStyle(.secondary))
        .contentTransition(.symbolEffect(.replace))
        .padding(outset)
        .contentShape(.interaction, Circle())
    }
    .buttonStyle(.plain)
    .padding(-outset)
    .disabled(isCompleting)
    .help(completion.label)
    .accessibilityHidden(true)
    .accessibilityIdentifier("\(identifier).\(task.id).complete")
  }

  private func complete(_ task: ReviewTaskSummary, with completion: Completion) async {
    guard !completingTaskIDs.contains(task.id) else { return }
    lorvexAnimated(.snappy(duration: 0.18)) { _ = completingTaskIDs.insert(task.id) }
    await completion.complete(task.id)
    // A saved completion has already reloaded the list without this row; a
    // failed one leaves the row, whose circle empties again.
    lorvexAnimated(.snappy(duration: 0.18)) { _ = completingTaskIDs.remove(task.id) }
  }

  private func openButton(_ task: ReviewTaskSummary) -> some View {
    Button { openTask(task.id) } label: {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            title(task)
            if let fact = detail(task) {
              factText(fact)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          titleLine(task, fact: detail(task))
        }
      }
      .padding(.vertical, LorvexReviewRowMetrics.rowPadding(LorvexDesign.Spacing.xxs))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("\(identifier).\(task.id)")
  }

  /// The title with its fact, if any, at the trailing end of the line. On
  /// iOS a fact the title cannot sit beside on one line moves under it.
  @ViewBuilder
  private func titleLine(_ task: ReviewTaskSummary, fact: String?) -> some View {
    #if os(iOS)
      if let fact {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline) {
            title(task)
              .lineLimit(1)
            Spacer(minLength: LorvexDesign.Spacing.s)
            factText(fact)
          }
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            title(task)
              .lineLimit(2)
            factText(fact)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        title(task)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    #else
      HStack(alignment: .firstTextBaseline) {
        title(task)
          .lineLimit(2)
        Spacer(minLength: LorvexDesign.Spacing.s)
        if let fact {
          factText(fact)
        }
      }
    #endif
  }

  private func title(_ task: ReviewTaskSummary) -> some View {
    Text(userContent: task.title)
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
