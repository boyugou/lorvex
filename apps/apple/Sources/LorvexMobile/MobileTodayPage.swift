import LorvexCore
import SwiftUI

/// iPhone and iPad Today: every task the day holds, in one list.
///
/// The date and one line of facts open it, then the assistant's briefing, the
/// day drawn to scale, and, when the day holds more estimated work than free
/// working time, one decision that offers to move the least urgent work to
/// tomorrow. Then the list: started tasks first, then the rest in the
/// canonical order, with no section headers, because each row says what a
/// header would (an overdue due date in red, a Started badge, the time of a
/// timed task). The habits still open today (``LorvexHabit/isListed(on:)``)
/// as rings and what is already done close the page; Done folds on request,
/// since it is a record rather than work. Every
/// task row swipes and long-presses the way a task row does
/// anywhere in the app: Start or Pause on the leading edge, Complete and Defer
/// on the trailing edge.
///
/// Every heading on the page starts at the cards' leading edge: the date and
/// the strip's Schedule label as ground rows, Habits and Done as section
/// headers with no horizontal inset, so the page reads down one edge rather
/// than an inset-grouped list's indented headers. Schedule, Habits, and Done
/// share the quiet page-label face. Schedule and Habits lead elsewhere (the
/// schedule sheet, the Habits page), so a chevron follows their names; Done's
/// chevron at the trailing edge folds it.
///
/// The words come from ``MobileTodayCalmCopy`` and the structure from
/// ``LorvexCalmToday``, so the facts line never disagrees with the rows
/// beneath it.
struct MobileTodayPage: View {
  @Bindable var store: MobileStore
  let page: LorvexCalmToday
  let nowMinutes: Int?
  let editHabit: (LorvexHabit) -> Void
  /// Opens the day's schedule from the strip; `nil` when the schedule already
  /// stands beside the page (iPad), so the strip is a plain picture.
  let openSchedule: (() -> Void)?

  @State private var showsFullBriefing = false
  @AppStorage("today.done.collapsed") private var doneCollapsed = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Briefings longer than this open on four lines with a "Show more" toggle.
  private static let briefingFoldLength = 150

  /// Insets for the rows drawn on the page ground rather than in a card: the
  /// header, the strip, and the well line up with the cards' edges.
  private static let groundInsets = EdgeInsets(
    top: LorvexDesign.Spacing.xs, leading: 0, bottom: LorvexDesign.Spacing.xs, trailing: 0)

  var body: some View {
    List {
      Section {
        groundEdge
        Group {
          header
          if showsStrip {
            stripRow
          }
          if let overbooked = page.overbooked {
            overbookedWell(overbooked)
          }
        }
        .listRowInsets(Self.groundInsets)
        groundEdge
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      // The header, strip, and well introduce the list under them, so the
      // list follows closer than the gap between two cards.
      .mobileListSectionSpacing(LorvexDesign.Spacing.m)

      if !page.items.isEmpty {
        taskSection
      } else {
        emptyDaySection
      }
      if let habits = store.habits?.habits.listed(on: store.logicalTodayString), !habits.isEmpty {
        habitsSection(habits)
      }
      if !store.doneTodayTasks.isEmpty {
        doneSection
      }
    }
    // The page opens with its own date rather than a header, so it sits just
    // under the bar instead of an inset-grouped list's opening gap below it.
    .contentMargins(.top, LorvexDesign.Spacing.s, for: .scrollContent)
    // Every row sizes to its content, so the ground section's edge rows take
    // no height. The list reads this for all its rows, not per row.
    .environment(\.defaultMinListRowHeight, 0)
    .animation(.snappy(duration: 0.25), value: page)
    .sensoryFeedback(.success, trigger: store.doneTodayCount)
  }

  /// An empty row that opens or closes the ground section. An inset-grouped
  /// list rounds a section's first and last rows to its corner radius and
  /// clips their content, which would shave ground rows drawn edge to edge:
  /// the title's first letter, the facts line on a day with nothing under it,
  /// the ends of the day strip, the well's lower corners. These rows take the
  /// corners instead, at no height: the page's list sets no minimum row
  /// height.
  private var groundEdge: some View {
    Color.clear
      .frame(height: 0)
      .listRowInsets(EdgeInsets())
      .accessibilityHidden(true)
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(MobileTodayCalmCopy.dateLine(logicalDay: store.logicalTodayString))
        .font(LorvexDesign.Typography.pageTitle)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.date")
      LorvexFactsLine(
        MobileTodayCalmCopy.facts(page.facts, workIsStated: page.overbooked != nil))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("today.headline")
      if let briefing = LorvexCalmToday.briefing(from: store.snapshot.today.briefing) {
        briefingView(briefing)
          .padding(.top, LorvexDesign.Spacing.s)
      }
    }
    .padding(.top, LorvexDesign.Spacing.xs)
  }

  /// The assistant's briefing in the system face, marked by the sparkles
  /// glyph rather than italics. A long one opens on four lines.
  private func briefingView(_ text: String) -> some View {
    let folds = text.count > Self.briefingFoldLength
    return HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "sparkles")
        .foregroundStyle(LorvexDesign.Palette.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(userContent: text)
          .font(LorvexDesign.Typography.briefing)
          .foregroundStyle(.primary)
          .lineLimit(folds && !showsFullBriefing ? 4 : nil)
          .fixedSize(horizontal: false, vertical: true)
        if folds {
          Button(
            showsFullBriefing ? MobileTodayCalmCopy.briefingLess : MobileTodayCalmCopy.briefingMore
          ) {
            withAnimation(.snappy(duration: 0.2)) { showsFullBriefing.toggle() }
          }
          .buttonStyle(.borderless)
          .font(LorvexDesign.Typography.secondaryText)
          .accessibilityIdentifier("today.briefing.toggle")
        }
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LorvexDesign.Palette.card,
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(MobileTodayCalmCopy.briefingLabel)
    .accessibilityIdentifier("today.briefing")
  }

  // MARK: The day at a glance

  /// iPhone keeps the strip whenever the day holds tasks, even with nothing
  /// timed yet, because it is the way into the schedule where times are
  /// suggested. iPad stands the schedule beside the page, so there the strip
  /// appears only when it has something to draw.
  private var showsStrip: Bool {
    if openSchedule != nil, !page.items.isEmpty { return true }
    return !store.todayStripSegments.isEmpty
  }

  /// The day drawn to scale: meetings, and tasks at their times. On iPhone it
  /// is labelled and opens the schedule sheet; on iPad it is a picture.
  @ViewBuilder
  private var stripRow: some View {
    let strip = LorvexDayStrip(
      segments: store.todayStripSegments, nowMinutes: nowMinutes, range: store.todayStripRange)
    if let openSchedule {
      Button(action: openSchedule) {
        // The clock's mark overhangs the strip by 5pt, so the label stands
        // further off than a tight caption would, clear of the mark.
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          HStack(spacing: LorvexDesign.Spacing.xxs) {
            Text(MobileTodayCalmCopy.scheduleTitle)
            Image(systemName: "chevron.forward")
              .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          }
          .font(LorvexDesign.Typography.pageLabel)
          .foregroundStyle(.secondary)
          strip
        }
        .padding(.vertical, LorvexDesign.Spacing.xs)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(MobileTodayCalmCopy.scheduleTitle)
      .accessibilityIdentifier("today.strip")
    } else {
      strip
        .padding(.vertical, LorvexDesign.Spacing.s)
        .accessibilityIdentifier("today.strip")
    }
  }

  /// Today holds more estimated work than free working time: one well says so
  /// and offers to move the named tasks to tomorrow. With nothing that can move
  /// on its own, it states the fact alone.
  @ViewBuilder
  private func overbookedWell(_ overbooked: LorvexCalmToday.Overbooked) -> some View {
    let title = MobileTodayCalmCopy.overbookedTitle(overbooked)
    let message = MobileTodayCalmCopy.overbookedMessage(overbooked)
    Group {
      if overbooked.candidates.isEmpty {
        LorvexDecisionWell(title: title, message: message)
      } else {
        LorvexDecisionWell(
          title: title, message: message, actionTitle: MobileTodayCalmCopy.overbookedAction,
          actionIdentifier: "today.overbooked.action"
        ) {
          let ids = overbooked.candidates.map(\.id)
          Task { await store.deferTasksToTomorrow(ids) }
        }
      }
    }
    .transition(.opacity)
    .accessibilityIdentifier("today.overbooked")
  }

  // MARK: The list

  /// Today's list, started tasks first. A running time shows as the row's
  /// "Until" chip in place of its time, since the end is the part that matters
  /// while it runs.
  private var taskSection: some View {
    Section {
      ForEach(page.items) { item in
        MobileActionTaskRow(
          task: item.task,
          isBlocked: store.snapshot.blockedTaskIDs.contains(item.task.id),
          isMutating: store.taskIsMutating(item.task.id),
          actions: store.rowActions(for: item.task.id),
          timeLabel: item.time.map {
            item.isRunning
              ? MobileTodayCalmCopy.untilLabel(end: $0.upperBound)
              : MobileTodayCalmCopy.timeRange(start: $0.lowerBound, end: $0.upperBound)
          },
          timeIsRunning: item.isRunning && item.time != nil,
          chips: chips(for: item))
      }
    }
    .accessibilityIdentifier("today.list")
  }

  private func chips(for item: LorvexCalmToday.Item) -> [LorvexTaskRowChip] {
    var chips: [LorvexTaskRowChip] = []
    if item.task.deferCount >= LorvexCalmToday.deferredOftenThreshold {
      chips.append(
        LorvexTaskRowChip(
          id: "pushed", title: MobileTodayCalmCopy.pushedChip(item.task.deferCount),
          systemImage: "arrow.uturn.forward", tint: LorvexDesign.Palette.neutral))
    }
    return chips
  }

  /// A day with nothing open: the sun's arc, and, when no list holds an open
  /// task and nothing was done today, the invitation to capture some work. A
  /// free day with work waiting in the lists shows the arc alone: the facts
  /// line already says the day is free, and "No Open Tasks" would be untrue.
  private var emptyDaySection: some View {
    Section {
      if let nowMinutes {
        LorvexSunArc(
          nowMinutes: nowMinutes, startLabel: MobileTodayCalmCopy.sunStart,
          endLabel: MobileTodayCalmCopy.sunEnd
        )
        .frame(height: 140)
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .accessibilityIdentifier("today.sun")
      }
      if store.doneTodayTasks.isEmpty && store.hasNoOpenTasks {
        MobileStoreTaskEmptyState(store: store)
      }
    }
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(Self.groundInsets)
  }

  // MARK: Habits

  private func habitsSection(_ habits: [LorvexHabit]) -> some View {
    Section {
      if dynamicTypeSize.isAccessibilitySize {
        // A strip column holds a word a line at these sizes, so each habit
        // takes a row of its own: its ring, then its whole name.
        ForEach(habits) { habit in
          HStack(spacing: LorvexDesign.Spacing.m) {
            // As wide as a task row's circle, so the names line up with the
            // task titles above.
            habitRing(habit)
              .mobileTaskCircleFrame(isSquare: false)
            habitName(habit)
            Spacer(minLength: 0)
          }
          .contextMenu { habitMenu(habit) }
        }
      } else {
        habitGrid(habits)
      }
    } header: {
      // Habits has no place in the iPhone tab bar, so it opens on Today's own
      // stack with a back button to the day.
      Button { store.routePath.append(.workspace(.habits)) } label: {
        HStack(spacing: LorvexDesign.Spacing.xxs) {
          Text(MobileTodayCalmCopy.habitsLabel)
          Image(systemName: "chevron.forward")
            .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        }
        .font(LorvexDesign.Typography.pageLabel)
        .textCase(nil)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("today.habits.all")
      .listRowInsets(.horizontal, 0)
    }
    .accessibilityIdentifier("today.habits")
  }

  /// The habits in a grid, each a ring over its name: as many columns as the
  /// row holds, with the habits spread evenly over the rows so none is left
  /// alone on the last (``LorvexBalancedGrid``), so every habit is on the page
  /// without a sideways scroll and keeps its place from day to day. A row's
  /// habits share the card's width, so a few habits spread across a wide iPad
  /// card as they do on a phone rather than gathering at its leading edge.
  private func habitGrid(_ habits: [LorvexHabit]) -> some View {
    LorvexBalancedGrid(
      minimumColumnWidth: Self.habitColumnWidth, maximumColumnWidth: .infinity,
      columnSpacing: Self.habitSpacing, rowSpacing: LorvexDesign.Spacing.m
    ) {
      ForEach(habits) { habit in
        VStack(spacing: LorvexDesign.Spacing.xs) {
          habitRing(habit)
          habitName(habit)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .contextMenu { habitMenu(habit) }
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }

  /// A habit's ring, which completes the habit, or resets it once complete.
  private func habitRing(_ habit: LorvexHabit) -> some View {
    MobileHabitCompletionRing(
      habit: habit,
      isMutating: store.isMutatingHabit,
      showsSymbol: true,
      size: Self.habitRingSize,
      complete: { await store.completeHabit(habit) },
      reset: { await store.uncompleteHabit(habit) })
  }

  /// A habit's name, which quiets to secondary once the day's count is met,
  /// as a habit's name does on the reviews (``LorvexHabitRingTile``), so what
  /// is still to do reads first.
  private func habitName(_ habit: LorvexHabit) -> some View {
    let isMet = habit.completionsToday >= max(habit.targetCount, 1)
    return Text(userContent: habit.name)
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(isMet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      .fixedSize(horizontal: false, vertical: true)
      // The ring's label already names the habit.
      .accessibilityHidden(true)
  }

  private func habitMenu(_ habit: LorvexHabit) -> some View {
    Button(MobileTodayCalmCopy.openDetails, systemImage: "pencil") { editHabit(habit) }
  }

  private static let habitSpacing = LorvexDesign.Spacing.s
  /// Larger than a habit row's ring: here the ring is the habit's only mark and
  /// carries its symbol, and the size keeps the tap target near 44 pt.
  private static let habitRingSize: CGFloat = 40
  private static let habitColumnWidth: CGFloat = 76

  // MARK: Done

  /// What is already done today, newest first; the header folds it away and
  /// counts the rows only while they are folded, since open rows are their own
  /// count.
  private var doneSection: some View {
    Section {
      if !doneCollapsed {
        ForEach(store.doneTodayTasks) { task in
          MobileTodayDoneRow(
            task: task, isMutating: store.taskIsMutating(task.id),
            reopen: { await store.reopenTask(task.id) })
        }
      }
    } header: {
      Button {
        withAnimation(.snappy(duration: 0.2)) { doneCollapsed.toggle() }
      } label: {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(MobileTodayCalmCopy.doneTitle)
          if doneCollapsed {
            Text("\(store.doneTodayTasks.count)")
              .monospacedDigit()
              .transition(.opacity)
          }
          Spacer(minLength: 0)
          MobileFoldChevron(isExpanded: !doneCollapsed)
        }
        .font(LorvexDesign.Typography.pageLabel)
        .textCase(nil)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("today.done.toggle")
      .listRowInsets(.horizontal, 0)
    }
    .accessibilityIdentifier("today.done")
  }
}

/// A task finished today: its green check reopens it, and the rest of the row
/// opens it.
struct MobileTodayDoneRow: View {
  let task: LorvexTask
  let isMutating: Bool
  let reopen: () async -> Void
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      Button {
        Task { await reopen() }
      } label: {
        Image(systemName: "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(LorvexDesign.Palette.done)
          .mobileTaskCircleFrame()
          .contentShape(Circle())
          .padding(.top, LorvexDesign.Spacing.xs)
      }
      .buttonStyle(.borderless)
      .disabled(isMutating)
      .accessibilityLabel(MobileTodayCalmCopy.reopen)
      MobileTaskRow(task: task, showsLeadingCircle: false, timeZone: productTimeZone)
        .equatable()
    }
    .accessibilityIdentifier("today.done.row")
  }
}
