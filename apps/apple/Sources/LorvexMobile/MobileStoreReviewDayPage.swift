import LorvexCore
import SwiftUI

/// A dated entry followed by the day's work, habits and tomorrow's plans.
struct MobileStoreReviewDayPage: View {
  @Bindable var store: MobileStore
  @FocusState private var focusedField: Field?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var expandedFields: Bool?
  private var showsMoreFields: Bool {
    expandedFields ?? (!isReviewingToday && [store.dailyReviewDraft.wins, store.dailyReviewDraft.blockers,
      store.dailyReviewDraft.learnings].contains { !$0.isEmpty })
  }
  /// The active habits as they stood on the reviewed day.
  @State private var dayHabits: (date: String, habits: [LorvexHabit])?
  /// Tomorrow's agenda, loaded only while the review is of today.
  @State private var tomorrow: LorvexAgendaDay?
  @State private var planningDay: String?

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
        } else if store.reviewDraftDate != store.selectedReviewDate {
          Button(String(localized: "mobileCommand.refresh", defaultValue: "Refresh", table: "Localizable",
            bundle: MobileL10n.bundle)) { Task { await store.loadDailyReviewDraft() } }
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
    .task(id: store.dailyReviewDraft) {
      let date = store.selectedReviewDate
      guard store.reviewDraftDate == date, store.selectedReviewDayIsEditable,
        !store.dailyReviewDraftMatchesLoaded else { return }
      try? await Task.sleep(for: .milliseconds(1200))
      guard !Task.isCancelled, store.selectedReviewDate == date else { return }
      await store.flushDailyReviewDraftIfNeeded()
    }
    .onChange(of: store.dailyReviewDraft.mood) { flush() }
    .onChange(of: store.dailyReviewDraft.energy) { flush() }
    .onChange(of: focusedField) { old, _ in if old != nil { flush() } }
    .onDisappear { flush() }
    .onChange(of: store.selectedReviewDate) {
      planningDay = nil
      expandedFields = nil
      focusedField = nil
    }
    .task(id: store.dayReviewReadKey) { await loadPageReads() }
    .sheet(isPresented: Binding(get: { planningDay != nil }, set: { if !$0 { planningDay = nil } })) {
      if let day = planningDay, let key = tomorrowKey, let evidence = store.dayReviewEvidence, evidence.date == day {
        MobileReviewTomorrowPlan(store: store, dayKey: key,
          tasks: evidence.unfinishedTasks.filter { $0.canMoveToTomorrow(key) }) { chosen in
          planningDay = nil
          Task { await store.arrangeReviewTasks(chosen, reviewedOn: day, destination: .day(key), tomorrow: key) }
        }
      }
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
      Menu {
        ForEach(store.recentReviewDates, id: \.self) { date in
          Button {
            Task { await store.selectReviewDay(date, forEditing: true) }
          } label: {
            let title = dayChoice(date)
            if date == store.selectedReviewDate {
              Label(title, systemImage: "checkmark")
            } else {
              Text(verbatim: title)
            }
          }
          .accessibilityIdentifier("review.day.choice.\(date)")
        }
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Text(MobileTodayCalmCopy.dateLine(logicalDay: store.selectedReviewDate), serifVoice: .pageSentence)
          Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44, alignment: .leading)
      }
      .buttonStyle(.plain)
      .menuOrder(.fixed)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("review.day.date")
      if !isReviewingToday {
        HStack(spacing: LorvexDesign.Spacing.l) {
          if !store.selectedReviewDayIsEditable, store.recentReviewDates.contains(store.selectedReviewDate) {
            Button(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle)) {
              let date = store.selectedReviewDate
              Task { await store.selectReviewDay(date, forEditing: true) }
            }
            .accessibilityIdentifier("review.day.edit")
          }
          Button(Copy.returnToToday) { Task { await store.returnReviewToToday() } }
            .accessibilityIdentifier("review.day.returnToday")
        }
        .font(LorvexDesign.Typography.secondaryText.weight(.medium))
        .controlSize(.large)
      }
    }
  }

  private func dayChoice(_ date: String) -> String {
    let today = store.logicalTodayString
    if date == today { return MobileTab.today.title }
    if date == LorvexDateFormatters.ymdUTCAddingDays(today, days: -1) {
      return LorvexDateFormatters.relativeDays(-1).localizedCapitalized
    }
    return Copy.dayLabel(date)
  }

  @ViewBuilder
  private var dailyReviewFields: some View {
    let editable = store.selectedReviewDayIsEditable
    if editable {
      journalEditor
      ratingEditor
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
        completion: !isReviewingToday ? nil : .init(label: MobileTaskActionCopy.completionToggle(isDone: false)) { id in
          await store.completeTask(id)
        },
        deferral: !isReviewingToday ? nil : tomorrowKey.map { key in
          .init(tomorrowKey: key, sectionLabel: { _ in MobileReviewTomorrowPlan.title + "…" }, rowLabel: Copy.moveRow,
            preview: {
              focusedField = nil
              planningDay = summary.date
            }) { tasks, destination in
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
        identifier: "review.day.habits", isEnabled: isReviewingToday
      ) { habit in
        let date = store.selectedReviewDate
        await store.checkInHabit(habit, on: date)
        if let loaded = await store.loadReviewHabits(date: date), date == store.selectedReviewDate {
          lorvexAnimated(LorvexDesign.Motion.quick) { self.dayHabits = (date, loaded) }
        }
      }
    }

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
      HStack {
        LorvexPageLabel(Copy.noteLabel)
        Spacer()
        if store.dailyReview?.date == store.selectedReviewDate, store.dailyReviewDraftMatchesLoaded {
          Label(String(localized: "reviews.daily.saved", defaultValue: "Saved", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "checkmark")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("review.daily.saved")
        }
      }
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
        lorvexAnimated(LorvexDesign.Motion.quick) { expandedFields = !showsMoreFields }
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
    let layout = dynamicTypeSize >= .xxLarge
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: LorvexDesign.Spacing.s))
      : AnyLayout(HStackLayout(alignment: .top, spacing: LorvexDesign.Spacing.s))
    return layout {
      ratingMenu(Copy.feelLabel, symbol: "face.smiling", value: $store.dailyReviewDraft.mood,
        dotLabel: Copy.feelDot, word: Copy.feelWord, identifier: "review.daily.mood")
      ratingMenu(Copy.energyLabel, symbol: "bolt", value: $store.dailyReviewDraft.energy,
        dotLabel: Copy.energyDot, word: Copy.energyWord, identifier: "review.daily.energy")
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func ratingMenu(
    _ label: String, symbol: String, value: Binding<Int?>,
    dotLabel: @escaping (Int) -> String, word: @escaping (Int) -> String, identifier: String
  ) -> some View {
    let add = String(localized: "common.add", defaultValue: "Add", table: "Localizable", bundle: MobileL10n.bundle)
    let selected = value.wrappedValue
    return Menu {
      ForEach(1...5, id: \.self) { level in
        Button {
          value.wrappedValue = level
        } label: {
          if selected == level {
            Label(word(level), systemImage: "checkmark")
          } else {
            Text(word(level))
          }
        }
        .accessibilityValue(dotLabel(level))
        .accessibilityAddTraits(selected == level ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(level)")
      }
      if selected != nil {
        Divider()
        Button {
          value.wrappedValue = nil
        } label: {
          Label(String(localized: "common.clear", defaultValue: "Clear", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "xmark")
        }
        .accessibilityIdentifier("\(identifier).clear")
      }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: symbol).foregroundStyle(LorvexDesign.Palette.Destination.review)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(label).font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
          HStack(spacing: LorvexDesign.Spacing.xs) {
            Text(selected.map(word) ?? add)
              .font(LorvexDesign.Typography.primaryEmphasis)
              .foregroundStyle(selected == nil ? Color.accentColor : .primary)
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .padding(.vertical, LorvexDesign.Spacing.s)
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
      .background(LorvexDesign.Palette.insetFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
      .contentShape(Rectangle())
    }
    .menuOrder(.fixed)
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityValue(selected.map { [word($0), dotLabel($0)].joined(separator: ", ") } ?? add)
    .accessibilityIdentifier(identifier)
    .sensoryFeedback(.selection, trigger: selected)
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
