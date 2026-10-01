import LorvexCore
import SwiftUI

/// The iPhone day review on the calm page grammar, read top to bottom as the
/// day's close: the day and one serif sentence reading what happened, what
/// moved forward, the due tasks still open (each completes, opens on the
/// Review stack, or moves to tomorrow from its context menu, and the section
/// moves them all), the habits as they stood that day (each checks in on that
/// day), two one-tap scales for how it felt, a look at tomorrow while the
/// review is of today, and one note. The rarer wins / blockers / learnings
/// fields fold behind one line. Everything saves as it changes; there is no
/// Save button.
struct MobileStoreReviewDayPage: View {
  @Bindable var store: MobileStore
  @FocusState private var focusedField: Field?
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

  private enum Field { case summary, wins, blockers, learnings }

  private typealias Copy = MobileReviewCalmCopy

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
        header
        if store.isLoadingDailyReviewDraft {
          MobileSkeletonRows(count: 4)
            .accessibilityIdentifier("mobileReview.loadingDaily")
        } else {
          dailyReviewFields
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.l)
      .padding(.top, LorvexDesign.Spacing.s)
      .padding(.bottom, LorvexDesign.Spacing.xl)
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .mobileReviewScrollAnchor()
    .onChange(of: store.dailyReviewDraft.mood) { flush() }
    .onChange(of: store.dailyReviewDraft.energy) { flush() }
    .onChange(of: focusedField) { old, _ in if old != nil { flush() } }
    .onDisappear { flush() }
    .task(id: ReadKey(date: store.selectedReviewDate, evidence: store.dayReviewEvidence)) {
      await loadPageReads()
    }
    .accessibilityIdentifier("review.day")
  }

  private var isReviewingToday: Bool {
    store.selectedReviewDate == store.logicalTodayString
  }

  private var tomorrowKey: String? {
    LorvexDateFormatters.ymdUTCAddingDays(store.logicalTodayString, days: 1)
  }

  private func loadPageReads() async {
    let date = store.selectedReviewDate
    if let loaded = await store.loadReviewHabits(date: date), date == store.selectedReviewDate {
      habits = loaded
    }
    if date == store.logicalTodayString {
      if let loaded = await store.loadTomorrowAgenda() { tomorrow = loaded }
    } else {
      tomorrow = nil
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(MobileTodayCalmCopy.dateLine(logicalDay: store.selectedReviewDate))
        .font(LorvexDesign.Typography.pageLabel)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("review.day.date")
      if let summary = store.dayReviewEvidence {
        Text(Copy.sentence(LorvexReviewSentence.parts(summary)), serifVoice: .pageSentence)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("review.day.headline")
      }
      if !store.selectedReviewDayIsEditable {
        Button(Copy.returnToToday) { Task { await store.returnReviewToToday() } }
          .font(LorvexDesign.Typography.secondaryText.weight(.medium))
          .padding(.top, LorvexDesign.Spacing.xs)
          .accessibilityIdentifier("review.day.returnToday")
      }
    }
  }

  @ViewBuilder
  private var dailyReviewFields: some View {
    let editable = store.selectedReviewDayIsEditable
    if let moved = store.dayReviewEvidence?.topCompleted, !moved.isEmpty {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        LorvexPageLabel(Copy.movedLabel)
        ForEach(moved) { task in
          HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(LorvexDesign.Palette.done)
            Text(task.title)
              .lineLimitUnlessAccessibilitySize(2)
          }
          .font(LorvexDesign.Typography.primaryText)
        }
      }
      .accessibilityIdentifier("review.day.moved")
    }

    if let summary = store.dayReviewEvidence, !summary.dueOpenTasks.isEmpty {
      LorvexReviewTaskList(
        label: Copy.stillOpenLabel, tasks: summary.dueOpenTasks,
        hiddenCount: max(0, summary.dueOpenCount - summary.dueOpenTasks.count),
        moreLine: Copy.moreCount, identifier: "review.day.stillOpen",
        detail: { task in
          guard let planned = task.plannedDate, let tomorrowKey, planned >= tomorrowKey else {
            return nil
          }
          return Copy.plannedFact(planned, tomorrowKey: tomorrowKey)
        },
        completion: .init(label: MobileTaskActionCopy.completionToggle(isDone: false)) { id in
          await store.completeTask(id)
        },
        deferral: tomorrowKey.map { key in
          .init(tomorrowKey: key, sectionLabel: Copy.moveSection, rowLabel: Copy.moveRow) { ids in
            _ = await store.deferTasksToTomorrow(ids)
          }
        }
      ) { id in
        store.openTaskRouteOnCurrentStack(id)
      }
    }

    if !habits.isEmpty {
      LorvexReviewHabitList(
        label: Copy.habitsLabel, habits: habits, checkInLabel: Copy.checkIn,
        identifier: "review.day.habits", isEnabled: editable
      ) { habit in
        let date = store.selectedReviewDate
        await store.checkInHabit(habit, on: date)
        if let loaded = await store.loadReviewHabits(date: date), date == store.selectedReviewDate {
          withAnimation(.snappy(duration: 0.18)) { habits = loaded }
        }
      }
    }

    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      scale(
        Copy.feelLabel, value: $store.dailyReviewDraft.mood, low: Copy.feelLow, high: Copy.feelHigh,
        dotLabel: Copy.feelDot, word: Copy.feelWord, identifier: "review.daily.mood",
        editable: editable)
      scale(
        Copy.energyLabel, value: $store.dailyReviewDraft.energy, low: Copy.energyLow,
        high: Copy.energyHigh, dotLabel: Copy.energyDot, word: Copy.energyWord,
        identifier: "review.daily.energy", editable: editable)
    }

    if isReviewingToday, let tomorrow {
      LorvexReviewTomorrow(
        label: Copy.tomorrowLabel, day: tomorrow, emptyLine: Copy.tomorrowEmpty,
        allDay: Copy.allDay, timeRange: MobileTodayCalmCopy.timeRange(start:end:),
        identifier: "review.day.tomorrow"
      ) { id in
        store.openTaskRouteOnCurrentStack(id)
      }
    }

    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(Copy.noteLabel)
      note(
        Copy.notePrompt, label: Copy.noteLabel, text: $store.dailyReviewDraft.summary, field: .summary,
        id: "review.daily.summary")
      if showsMoreFields || hasMoreText {
        labeled(Copy.winsLabel) {
          note(
            Copy.winsPrompt, label: Copy.winsLabel, text: $store.dailyReviewDraft.wins, field: .wins,
            id: "review.daily.wins")
        }
        labeled(Copy.blockersLabel) {
          note(
            Copy.blockersPrompt, label: Copy.blockersLabel, text: $store.dailyReviewDraft.blockers,
            field: .blockers, id: "review.daily.blockers")
        }
        labeled(Copy.learningsLabel) {
          note(
            Copy.learningsPrompt, label: Copy.learningsLabel, text: $store.dailyReviewDraft.learnings,
            field: .learnings, id: "review.daily.learnings")
        }
      } else if editable {
        Button {
          withAnimation(.snappy) { showsMoreFields = true }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.xxs) {
            Text(Copy.moreFields)
            Image(systemName: "chevron.down").imageScale(.small)
          }
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review.daily.more")
      }
    }
  }

  private var hasMoreText: Bool {
    let draft = store.dailyReviewDraft
    return draft.trimmedWins != nil || draft.trimmedBlockers != nil || draft.trimmedLearnings != nil
  }

  private func scale(
    _ label: String, value: Binding<Int?>, low: String, high: String,
    dotLabel: @escaping (Int) -> String, word: @escaping (Int) -> String, identifier: String,
    editable: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      LorvexPageLabel(label)
      LorvexDotScale(
        value: value, lowLabel: low, highLabel: high, dotLabel: dotLabel, levelWord: word,
        identifierPrefix: identifier, isEnabled: editable)
    }
  }

  /// A written field keeps its name above it, since its placeholder is gone.
  private func labeled(_ label: String, @ViewBuilder field: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(label)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .padding(.leading, LorvexDesign.Spacing.m)
        .accessibilityHidden(true)
      field()
    }
    .padding(.top, LorvexDesign.Spacing.xs)
  }

  /// A note on a quiet inset fill; `prompt` asks the field's question as its
  /// placeholder, and `label` names the field for VoiceOver.
  private func note(
    _ prompt: String, label: String, text: Binding<String>, field: Field, id: String
  ) -> some View {
    TextField(prompt, text: text, axis: .vertical)
      .font(LorvexDesign.Typography.primaryText)
      .lineLimit(1...8)
      .focused($focusedField, equals: field)
      .disabled(!store.selectedReviewDayIsEditable)
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .padding(.vertical, LorvexDesign.Spacing.sm)
      .background(
        LorvexDesign.Palette.insetFill,
        in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous)
      )
      .accessibilityLabel(label)
      .accessibilityIdentifier(id)
  }

  private func flush() {
    Task { await store.flushDailyReviewDraftIfNeeded() }
  }
}
