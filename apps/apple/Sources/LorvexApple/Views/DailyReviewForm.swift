import LorvexCore
import SwiftUI

/// The macOS day review on the calm page grammar, read top to bottom as the
/// day's close: the day and one serif sentence reading what happened, what
/// moved forward, the due tasks still open (each completes, opens, or moves to
/// tomorrow, and the section moves them all), the habits as they stood that
/// day (each checks in on that day), two one-click scales for how it felt,
/// a look at tomorrow while the review is of today, and one note. Wins,
/// blockers, and learnings fold behind one line until asked for or already
/// written. The workspace autosaves every edit, so the page has no Save
/// button. A past day outside the write window shows the saved review
/// read-only under the same sentence and lists, its habits without check-in.
struct DailyReviewForm: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager
  /// Past day (`YYYY-MM-DD`) the editor is anchored to; `nil` = today.
  var editingDate: String? = nil
  var onReturnToToday: () -> Void = {}
  var isReadOnly = false
  var onEditorFocusChange: @MainActor @Sendable (Bool) -> Void = { _ in }

  @State private var showsMoreFields = false
  /// The active habits as they stood on the reviewed day.
  @State private var habits: [LorvexHabit] = []
  /// Tomorrow's agenda, loaded only while the review is of today.
  @State private var tomorrow: LorvexAgendaDay?

  /// What the page's own reads follow: the reviewed day, and its evidence,
  /// which every task or habit change reloads.
  private struct ReadKey: Equatable {
    var date: String
    var evidence: DayReviewSummary?
  }

  private typealias Copy = ReviewCalmCopy

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
        header
        moved
        stillOpen
        habitList
        if isReadOnly {
          DailyReviewReadOnlyView(review: store.dailyReview)
        } else {
          HStack(alignment: .top, spacing: LorvexDesign.Spacing.xl) {
            scale(
              Copy.feelLabel, value: $store.dailyReviewMood, low: Copy.feelLow, high: Copy.feelHigh,
              dotLabel: Copy.feelDot, word: Copy.feelWord, identifier: "review.mood")
            scale(
              Copy.energyLabel, value: $store.dailyReviewEnergy, low: Copy.energyLow,
              high: Copy.energyHigh, dotLabel: Copy.energyDot, word: Copy.energyWord,
              identifier: "review.energy")
          }
          tomorrowSection
          notes
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.xl)
      .padding(.vertical, LorvexDesign.Spacing.l)
      .frame(maxWidth: 680, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(.background)
    .task(id: ReadKey(date: store.selectedReviewDate, evidence: store.dayReviewEvidence)) {
      await loadPageReads()
    }
  }

  private var isReviewingToday: Bool {
    store.selectedReviewDate == store.logicalTodayDateString
  }

  private var tomorrowKey: String? {
    LorvexDateFormatters.ymdUTCAddingDays(store.logicalTodayDateString, days: 1)
  }

  private func loadPageReads() async {
    let date = store.selectedReviewDate
    if let loaded = await store.loadReviewHabits(date: date), date == store.selectedReviewDate {
      habits = loaded
    }
    if date == store.logicalTodayDateString {
      if let loaded = await store.loadTomorrowAgenda() { tomorrow = loaded }
    } else {
      tomorrow = nil
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(TodayCalmCopy.dateLine(logicalDay: store.selectedReviewDate))
        .font(LorvexDesign.Typography.pageLabel)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("reviews.daily.date")
      if let summary = store.dayReviewEvidence {
        Text(Copy.sentence(LorvexReviewSentence.parts(summary)), serifVoice: .pageSentence)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("reviews.daily.headline")
      }
      if editingDate != nil {
        Button(action: onReturnToToday) {
          Text(LocalizedStringResource("reviews.daily.back_to_today", defaultValue: "Back to Today", table: "Localizable", bundle: LorvexL10n.bundle))
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("reviews.daily.backToToday")
      }
    }
  }

  @ViewBuilder
  private var moved: some View {
    if let summary = store.dayReviewEvidence, !summary.topCompleted.isEmpty {
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
    if let summary = store.dayReviewEvidence, !summary.dueOpenTasks.isEmpty {
      LorvexReviewTaskList(
        label: Copy.stillOpenLabel, tasks: summary.dueOpenTasks,
        hiddenCount: max(0, summary.dueOpenCount - summary.dueOpenTasks.count),
        moreLine: Copy.moreCount, identifier: "reviews.daily.stillOpen",
        detail: { task in
          guard let planned = task.plannedDate, let tomorrowKey, planned >= tomorrowKey else {
            return nil
          }
          return Copy.plannedFact(planned, tomorrowKey: tomorrowKey)
        },
        completion: .init(label: TaskDisplayText.completionToggle(isDone: false)) { id in
          await store.completeTask(id: id, undoManager: undoManager)
        },
        deferral: tomorrowKey.map { key in
          .init(tomorrowKey: key, sectionLabel: Copy.moveSection, rowLabel: Copy.moveRow) { ids in
            await store.moveReviewTasksToTomorrow(ids: ids)
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
        identifier: "reviews.daily.habits", isEnabled: !isReadOnly
      ) { habit in
        let date = store.selectedReviewDate
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
    if isReviewingToday, let tomorrow {
      LorvexReviewTomorrow(
        label: Copy.tomorrowLabel, day: tomorrow, emptyLine: Copy.tomorrowEmpty,
        allDay: TodayCalmCopy.allDay, timeRange: TodayCalmCopy.timeRange(start:end:),
        identifier: "reviews.daily.tomorrow"
      ) { id in
        store.selection = .tasks
        store.selectedTaskID = id
      }
    }
  }

  private var notes: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(Copy.noteLabel)
      editor(
        Copy.notePrompt, label: Copy.noteLabel, text: $store.dailyReviewSummaryDraft,
        minHeight: 90, id: "review.summary")
      if showsMoreFields || hasMoreText {
        labeled(Copy.winsLabel) {
          editor(
            Copy.winsPrompt, label: Copy.winsLabel, text: $store.dailyReviewWinsDraft, minHeight: 60,
            id: "review.wins")
        }
        labeled(Copy.blockersLabel) {
          editor(
            Copy.blockersPrompt, label: Copy.blockersLabel, text: $store.dailyReviewBlockersDraft,
            minHeight: 60, id: "review.blockers")
        }
        labeled(Copy.learningsLabel) {
          editor(
            Copy.learningsPrompt, label: Copy.learningsLabel, text: $store.dailyReviewLearningsDraft,
            minHeight: 60, id: "review.learnings")
        }
      } else {
        Button {
          lorvexAnimated(.snappy) { showsMoreFields = true }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.xxs) {
            Text(Copy.moreFields)
            Image(systemName: "chevron.down").imageScale(.small)
          }
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reviews.daily.more")
      }
    }
  }

  private var hasMoreText: Bool {
    [store.dailyReviewWinsDraft, store.dailyReviewBlockersDraft, store.dailyReviewLearningsDraft]
      .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  private func scale(
    _ label: String, value: Binding<Int?>, low: String, high: String,
    dotLabel: @escaping (Int) -> String, word: @escaping (Int) -> String, identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      LorvexPageLabel(label)
      LorvexDotScale(
        value: value, lowLabel: low, highLabel: high, dotLabel: dotLabel, levelWord: word,
        identifierPrefix: identifier)
    }
    .frame(maxWidth: .infinity)
  }

  /// A written field keeps its name above it, since its placeholder is gone.
  private func labeled(_ label: String, @ViewBuilder field: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(label)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      field()
    }
    .padding(.top, LorvexDesign.Spacing.xs)
  }

  /// `prompt` asks the question the field wants answered; `label` names the
  /// field for VoiceOver.
  private func editor(
    _ prompt: String, label: String, text: Binding<String>, minHeight: CGFloat, id: String
  ) -> some View {
    LorvexPlainTextEditor(
      text: text,
      placeholder: prompt,
      minHeight: minHeight,
      fontSize: 14,
      onFocusChange: onEditorFocusChange
    )
    .padding(LorvexDesign.Spacing.s)
    .background(
      LorvexDesign.Palette.insetFill,
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous)
    )
    .accessibilityLabel(label)
    .accessibilityIdentifier(id)
  }
}
