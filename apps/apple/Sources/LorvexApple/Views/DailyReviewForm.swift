import LorvexCore
import SwiftUI

/// A dated journal entry with the day's records close at hand. AnyLayout keeps
/// the text editor and its selection alive when the context moves below it.
struct DailyReviewForm: View {
  @Bindable var store: AppStore
  let date: String
  var isReadOnly = false
  var onEditorFocusChange: @MainActor @Sendable (Bool) -> Void = { _ in }
  @Environment(\.undoManager) private var undoManager
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var focusedField: String?
  @State private var expandedPrompts: Bool?
  @State private var habits: [LorvexHabit] = []
  @State private var calendar: CalendarTimelineSnapshot?
  @State private var tomorrow: LorvexAgendaDay?
  @State private var planningTomorrow = false
  @State private var loadingTomorrow = true
  private typealias Copy = ReviewCalmCopy

  var body: some View {
    GeometryReader { geometry in
      let dayEvents = events
      let wide = geometry.size.width >= 860 && dynamicTypeSize < .xxLarge
      let layout = wide
        ? AnyLayout(HStackLayout(alignment: .top, spacing: LorvexDesign.Spacing.xl))
        : AnyLayout(VStackLayout(alignment: .leading, spacing: LorvexDesign.Spacing.xl))
      ScrollView {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
          header
          Divider()
          layout {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
              if isReadOnly {
                DailyReviewReadOnlyView(review: store.dailyReview?.date == date ? store.dailyReview : nil)
              } else {
                notes
                ratings
              }
              moved
              stillOpen
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !habits.isEmpty || !dayEvents.isEmpty || (isReviewingToday && tomorrow != nil) {
              VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
                if !dayEvents.isEmpty {
                  agenda(LorvexAgendaDay(key: date, events: dayEvents, tasks: []),
                    label: String(localized: SidebarSelection.calendar.macOSLocalizedTitle),
                    identifier: "reviews.daily.calendar")
                }
                habitList
                tomorrowSection
              }
              .frame(width: wide ? min(338, geometry.size.width * 0.31) : nil, alignment: .leading)
              .frame(maxWidth: wide ? nil : .infinity, alignment: .leading)
            }
          }
        }
        .frame(maxWidth: wide ? 1020 : 660, alignment: .leading)
        .padding(LorvexDesign.Spacing.xl)
        .frame(maxWidth: .infinity)
      }
    }
    .sheet(isPresented: $planningTomorrow) {
      if let key = tomorrowKey {
        ReviewTomorrowPlanSheet(dayKey: key,
          tasks: (evidence?.unfinishedTasks ?? []).filter { $0.canMoveToTomorrow(key) },
          agenda: groupedTomorrow, loading: loadingTomorrow,
          workday: store.workdayWindow, retry: {
            await store.loadWorkdayWindow()
            await loadTomorrow()
          }
        ) { tasks in
          planningTomorrow = false
          Task { await store.arrangeReviewTasks(tasks, reviewedOn: date, destination: .day(key), undoManager: undoManager) }
        }
      }
    }
    .onChange(of: tomorrowKey) { planningTomorrow = false }
    .background(alignment: .top) {
      LinearGradient(colors: [LorvexDesign.Palette.Destination.review.opacity(0.065), .clear],
        startPoint: .top, endPoint: .bottom)
        .frame(height: 250).ignoresSafeArea(edges: .top)
    }
    .background(.background)
    .onChange(of: focusedField != nil) { _, focused in onEditorFocusChange(focused) }
    .task(id: store.dayReviewReadKey) {
      if let loaded = await store.loadReviewHabits(date: date), !Task.isCancelled { habits = loaded }
    }
    .task(id: TomorrowReadKey(review: store.dayReviewReadKey, calendarToken: store.calendarTimelineLoadToken)) {
      if isReviewingToday || !isReadOnly { await loadTomorrow() }
    }
    .task { await store.loadWorkdayWindow() }
    .task(id: [UInt64(store.calendarTimelineLoadToken), store.reviewReadGeneration]) {
      if let loaded = try? await store.core.loadCalendarTimeline(from: date, to: date), !Task.isCancelled {
        calendar = loaded
      }
    }
  }

  private struct TomorrowReadKey: Equatable {
    let review: DayReviewReadKey
    let calendarToken: Int
  }

  private var groupedTomorrow: LorvexAgendaDay? {
    guard let tomorrow, tomorrow.key == tomorrowKey else { return nil }
    return LorvexAgendaDay(key: tomorrow.key,
      events: store.calendarDuplicateGrouping.events(tomorrow.events), tasks: tomorrow.tasks)
  }

  private var isReviewingToday: Bool { date == store.logicalTodayDateString }

  private var tomorrowKey: String? {
    LorvexDateFormatters.ymdUTCAddingDays(store.logicalTodayDateString, days: 1)
  }

  private var evidence: DayReviewSummary? {
    store.dayReviewEvidence.flatMap { $0.date == date ? $0 : nil }
  }

  private var events: [CalendarTimelineEvent] {
    calendar?.groupingDuplicates(store.calendarDuplicateGrouping).eventsOccurring(on: date) ?? []
  }

  private func loadTomorrow() async {
    loadingTomorrow = true
    let loaded = await store.loadTomorrowAgenda()
    guard !Task.isCancelled else { return }
    tomorrow = loaded
    loadingTomorrow = false
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Label {
        Text(String(localized: SidebarSelection.reviews.macOSLocalizedTitle))
      } icon: {
        Image(systemName: "book.pages").foregroundStyle(LorvexDesign.Palette.Destination.review)
      }
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(.secondary)
      Text(TodayCalmCopy.dateLine(logicalDay: date), serifVoice: .pageSentence)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("reviews.daily.date")
    }
  }

  @ViewBuilder
  private var moved: some View {
    if let summary = evidence, !summary.topCompleted.isEmpty {
      LorvexReviewMovedList(
        label: Copy.movedLabel, tasks: summary.topCompleted,
        hiddenCount: summary.hiddenCompletedCount, moreLine: Copy.moreCount,
        identifier: "reviews.daily.moved")
    }
  }

  /// The tasks due that day that are not done yet; each row's circle
  /// completes the task, and its title opens it in All Tasks.
  @ViewBuilder
  private var stillOpen: some View {
    if let summary = evidence, !summary.unfinishedTasks.isEmpty {
      LorvexReviewTaskList(
        label: Copy.stillOpenLabel, tasks: summary.unfinishedTasks,
        hiddenCount: 0, previewLimit: 5,
        moreLine: Copy.moreCount, identifier: "reviews.daily.stillOpen",
        detail: { task in
          let deadline = task.reviewDeadline(relativeTo: store.logicalTodayDateString)
          guard let planned = task.plannedDate, let tomorrowKey, planned >= tomorrowKey else { return deadline }
          return [deadline, Copy.plannedFact(planned, tomorrowKey: tomorrowKey)].compactMap { $0 }
            .joined(separator: " · ")
        },
        completion: isReadOnly ? nil : .init(label: TaskDisplayText.completionToggle(isDone: false)) { id in
          await store.completeTask(id: id, undoManager: undoManager)
        },
        deferral: isReadOnly ? nil : tomorrowKey.map { key in
          .init(tomorrowKey: key, sectionLabel: { _ in ReviewTomorrowPlanSheet.title + "…" }, rowLabel: Copy.moveRow,
            preview: { planningTomorrow = true }) { tasks, destination in
            await store.arrangeReviewTasks(tasks, reviewedOn: date, destination: destination, undoManager: undoManager)
          }
        }
      ) { id in
        store.selection = .tasks
        store.selectedTaskID = id
      }
    }
  }

  /// The habits as they stood on the reviewed day; each row checks the habit
  /// in on that day, so a forgotten check-in can be made up from the review.
  @ViewBuilder
  private var habitList: some View {
    if !habits.isEmpty {
      LorvexReviewHabitList(
        label: Copy.habitsLabel, habits: habits, checkInLabel: Copy.checkIn,
        identifier: "reviews.daily.habits", isEnabled: !isReadOnly, layout: .checklist
      ) { habit in
        guard date == store.selectedReviewDate else { return }
        await store.checkInHabit(habit, on: date)
        if let loaded = await store.loadReviewHabits(date: date), date == store.selectedReviewDate {
          lorvexAnimated(.snappy(duration: 0.18)) { habits = loaded }
        }
      }
    }
  }

  /// What tomorrow already holds, shown while the review is of today, so the
  /// day closes on what comes next.
  @ViewBuilder
  private var tomorrowSection: some View {
    if isReviewingToday, let day = groupedTomorrow {
      agenda(day, label: Copy.tomorrowLabel, identifier: "reviews.daily.tomorrow")
    }
  }

  private func agenda(_ day: LorvexAgendaDay, label: String, identifier: String) -> some View {
    DailyReviewAgenda(day: day, title: label, identifier: identifier) { event in
      store.showEventInCalendar(event, onDayKey: day.key)
    } openTask: { id in
      store.selection = .tasks
      store.selectedTaskID = id
    }
  }

  private var notes: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HStack {
        Label(Copy.reflection, systemImage: "pencil.line")
          .font(LorvexDesign.Typography.detailTitle)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if store.dailyReview?.date == date, store.dailyReviewDraftMatchesLoaded {
          Label(Copy.saved, systemImage: "checkmark")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
        }
      }
      editor(Copy.notePrompt, label: Copy.reflection, text: $store.dailyReviewSummaryDraft,
        minHeight: 96, id: "review.summary")
      Divider()
      DisclosureGroup(isExpanded: Binding(
        get: { expandedPrompts ?? hasMoreText },
        set: { expandedPrompts = $0 }
      )) {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
          labeled(Copy.winsLabel) {
            editor(Copy.winsPrompt, label: Copy.winsLabel, text: $store.dailyReviewWinsDraft,
              minHeight: 40, id: "review.wins")
          }
          labeled(Copy.blockersLabel) {
            editor(Copy.blockersPrompt, label: Copy.blockersLabel, text: $store.dailyReviewBlockersDraft,
              minHeight: 40, id: "review.blockers")
          }
          labeled(Copy.learningsLabel) {
            editor(Copy.learningsPrompt, label: Copy.learningsLabel, text: $store.dailyReviewLearningsDraft,
              minHeight: 40, id: "review.learnings")
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.s)
      } label: {
        Text(Copy.moreFields).font(LorvexDesign.Typography.secondaryText)
      }
      .accessibilityIdentifier("reviews.daily.more")
    }
    .padding(LorvexDesign.Spacing.l)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.card)
        .strokeBorder(focusedField == nil ? LorvexDesign.Palette.separator : LorvexDesign.Palette.accent,
          lineWidth: focusedField == nil ? 1 : 1.5)
        .allowsHitTesting(false)
    }
  }

  private var ratings: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      scale(Copy.feelLabel, symbol: "face.smiling", value: $store.dailyReviewMood,
        dotLabel: Copy.feelDot, word: Copy.feelWord, identifier: "review.mood")
      scale(Copy.energyLabel, symbol: "bolt", value: $store.dailyReviewEnergy,
        dotLabel: Copy.energyDot, word: Copy.energyWord, identifier: "review.energy")
    }
  }

  private var hasMoreText: Bool {
    [store.dailyReviewWinsDraft, store.dailyReviewBlockersDraft, store.dailyReviewLearningsDraft]
      .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  private func scale(
    _ label: String, symbol: String, value: Binding<Int?>,
    dotLabel: @escaping (Int) -> String, word: @escaping (Int) -> String, identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Label(label, systemImage: symbol)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .accessibilityAddTraits(.isHeader)
      LorvexRatingScale(value: value, levelLabel: word, accessibilityLabel: dotLabel,
        identifierPrefix: identifier, compact: true)
    }
  }

  private func labeled(_ label: String, @ViewBuilder field: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(label).font(LorvexDesign.Typography.pageLabel)
      field()
    }
  }

  private func editor(
    _ prompt: String, label: String, text: Binding<String>, minHeight: CGFloat, id: String
  ) -> some View {
    LorvexPlainTextEditor(text: text, placeholder: prompt, minHeight: minHeight,
      fontSize: 15, growsWithContent: true, onFocusChange: { focused in
        if focused { focusedField = id }
        else if focusedField == id { focusedField = nil }
      })
      .accessibilityLabel(label)
      .accessibilityIdentifier(id)
  }
}
