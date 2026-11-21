import LorvexCore
import SwiftUI

/// A dated entry followed by the day's work, habits and tomorrow's plans.
struct MobileStoreReviewDayPage: View {
  @Bindable var store: MobileStore
  @FocusState private var focusedField: Field?
  @State private var showsMoreFields = false
  /// The active habits as they stood on the reviewed day.
  @State private var dayHabits: (date: String, habits: [LorvexHabit])?
  /// Tomorrow's agenda, loaded only while the review is of today.
  @State private var tomorrow: LorvexAgendaDay?

  private enum Field { case summary, wins, blockers, learnings }

  private typealias Copy = MobileReviewCalmCopy

  /// The vertical padding that takes the "more fields" line of text to a tap
  /// target of about 44pt.
  private static let moreTapPadding: CGFloat = 13

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
    .onChange(of: store.selectedReviewDate) { showsMoreFields = false }
    .task(id: store.dayReviewReadKey) { await loadPageReads() }
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
      dayHabits = (date, loaded)
    }
    if date == store.logicalTodayString {
      if let loaded = await store.loadTomorrowAgenda() { tomorrow = loaded }
    } else {
      tomorrow = nil
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(MobileTodayCalmCopy.dateLine(logicalDay: store.selectedReviewDate), serifVoice: .pageSentence)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("review.day.date")
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
    if editable {
      journalEditor
    } else if let review = store.dailyReview, review.date == store.selectedReviewDate, review.hasJournalContent {
      LorvexJournalEntryBody(review: review, feeling: Copy.feelWord, energy: Copy.energyWord)
    } else if store.reviewDraftDate == store.selectedReviewDate {
      Text(String(localized: "reviews.daily.readonly_empty", defaultValue: "No review was written on this day.",
        table: "Localizable", bundle: MobileL10n.bundle))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("review.day.empty")
    }

    if let summary = store.dayReviewEvidence, summary.date == store.selectedReviewDate, !summary.topCompleted.isEmpty {
      LorvexReviewMovedList(
        label: Copy.movedLabel, tasks: summary.topCompleted,
        hiddenCount: summary.hiddenCompletedCount, moreLine: Copy.moreCount,
        identifier: "review.day.moved")
    }

    if let summary = store.dayReviewEvidence, summary.date == store.selectedReviewDate, !summary.unfinishedTasks.isEmpty {
      LorvexReviewTaskList(
        label: Copy.stillOpenLabel, tasks: summary.unfinishedTasks,
        hiddenCount: 0, previewLimit: 5,
        moreLine: Copy.moreCount, identifier: "review.day.stillOpen",
        detail: { task in
          let deadline = task.reviewDeadline(relativeTo: store.logicalTodayString)
          guard let planned = task.plannedDate, let tomorrowKey, planned >= tomorrowKey else { return deadline }
          return [deadline, Copy.plannedFact(planned, tomorrowKey: tomorrowKey)].compactMap { $0 }
            .joined(separator: " · ")
        },
        completion: !editable ? nil : .init(label: MobileTaskActionCopy.completionToggle(isDone: false)) { id in
          await store.completeTask(id)
        },
        deferral: !editable ? nil : tomorrowKey.map { key in
          .init(tomorrowKey: key, sectionLabel: Copy.moveSection, rowLabel: Copy.moveRow) { tasks, destination in
            await store.arrangeReviewTasks(tasks, reviewedOn: summary.date, destination: destination, tomorrow: key)
          }
        }
      ) { id in
        store.openTaskRouteOnCurrentStack(id)
      }
    }

    if let dayHabits, dayHabits.date == store.selectedReviewDate, !dayHabits.habits.isEmpty {
      LorvexReviewHabitList(
        label: Copy.habitsLabel, habits: dayHabits.habits, checkInLabel: Copy.checkIn,
        identifier: "review.day.habits", isEnabled: editable
      ) { habit in
        let date = store.selectedReviewDate
        await store.checkInHabit(habit, on: date)
        if let loaded = await store.loadReviewHabits(date: date), date == store.selectedReviewDate {
          lorvexAnimated(.snappy(duration: 0.18)) { self.dayHabits = (date, loaded) }
        }
      }
    }

    if editable { ratingEditor }

    if isReviewingToday, let tomorrow, tomorrow.key == tomorrowKey {
      LorvexReviewTomorrow(
        label: Copy.tomorrowLabel, day: tomorrow, emptyLine: Copy.tomorrowEmpty,
        allDay: Copy.allDay, timeRange: MobileTodayCalmCopy.timeRange(start:end:),
        identifier: "review.day.tomorrow"
      ) { id in
        store.openTaskRouteOnCurrentStack(id)
      }
    }
  }

  private var journalEditor: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(Copy.noteLabel)
      note(
        Copy.notePrompt, label: Copy.noteLabel, text: $store.dailyReviewDraft.summary, field: .summary,
        id: "review.daily.summary")
      if showsMoreFields {
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
      }
      Button {
        lorvexAnimated(.snappy) { showsMoreFields.toggle() }
      } label: {
        // The words are one line tall. The label's padding lifts the tap
        // target to about 44pt, and the negative padding outside the button
        // gives the page that height back.
        HStack(spacing: LorvexDesign.Spacing.xxs) {
          Text(Copy.moreFields)
          Image(systemName: showsMoreFields ? "chevron.up" : "chevron.down").imageScale(.small)
        }
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .padding(.vertical, Self.moreTapPadding)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.vertical, -Self.moreTapPadding)
      .accessibilityIdentifier("review.daily.more")
    }
  }

  private var ratingEditor: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      scale(Copy.feelLabel, value: $store.dailyReviewDraft.mood,
        dotLabel: Copy.feelDot, word: Copy.feelWord, identifier: "review.daily.mood")
      scale(Copy.energyLabel, value: $store.dailyReviewDraft.energy,
        dotLabel: Copy.energyDot, word: Copy.energyWord, identifier: "review.daily.energy")
    }
  }

  private func scale(
    _ label: String, value: Binding<Int?>,
    dotLabel: @escaping (Int) -> String, word: @escaping (Int) -> String, identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      LorvexPageLabel(label)
      LorvexRatingScale(
        value: value, levelLabel: word, accessibilityLabel: dotLabel,
        identifierPrefix: identifier, isEnabled: true)
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
      .lineLimit(field == .summary ? 3...12 : 1...8)
      .frame(minHeight: field == .summary ? 60 : nil, alignment: .topLeading)
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
