import LorvexCore
import SwiftUI

/// Choosing rows changes only this preview. The Review action receives the
/// current selection once, so the entire move can be undone together.
struct ReviewTomorrowPlanSheet: View {
  let dayKey: String
  let tasks: [ReviewTaskSummary]
  let agenda: LorvexAgendaDay?
  let loading: Bool
  let workday: Range<Int>?
  let todayRemaining: Int?
  let retry: () async -> Void
  let move: ([ReviewTaskSummary]) -> Void

  @State private var selectedIDs: Set<String>
  @State private var showAgenda = false
  @Environment(\.dismiss) private var dismiss

  init(dayKey: String, tasks: [ReviewTaskSummary], agenda: LorvexAgendaDay?, loading: Bool, workday: Range<Int>?,
    todayRemaining: Int? = nil, suggestedIDs: Set<String>? = nil, retry: @escaping () async -> Void, move: @escaping ([ReviewTaskSummary]) -> Void) {
    self.dayKey = dayKey
    self.tasks = tasks
    self.agenda = agenda
    self.loading = loading
    self.workday = workday
    self.todayRemaining = todayRemaining
    self.retry = retry
    self.move = move
    _selectedIDs = State(initialValue: suggestedIDs ?? Set(tasks.map(\.id)))
  }

  static var title: String {
    String(localized: "review.plan.tomorrow", defaultValue: "Plan Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  private var selected: [ReviewTaskSummary] { tasks.filter { selectedIDs.contains($0.id) } }
  private var noEstimate: String {
    String(localized: "task_detail.picker.no_length", defaultValue: "No Estimate", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  private var selectedLabel: String {
    String(localized: "common.selected", defaultValue: "Selected", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text(ReviewCalmCopy.dayLabel(dayKey)).font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
        Text(Self.title, serifVoice: .pageSentence).accessibilityAddTraits(.isHeader)
      }
      .padding([.horizontal, .top], 24)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let agenda, let workday {
            forecast(agenda, window: workday)
          } else if loading {
            ProgressView().controlSize(.small)
          } else {
            HStack {
              Label(String(localized: "task_detail.dependencies.unavailable", defaultValue: "Unavailable", table: "Localizable", bundle: LorvexL10n.bundle),
                systemImage: "calendar.badge.exclamationmark")
              Button(String(localized: "common.try_again", defaultValue: "Try Again", table: "Localizable", bundle: LorvexL10n.bundle)) {
                Task { await retry() }
              }
            }
          }
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            LorvexPageLabel(ReviewCalmCopy.stillOpenLabel)
            ForEach(tasks) { task in
              Toggle(isOn: Binding(
                get: { selectedIDs.contains(task.id) },
                set: { on in
                  if on { selectedIDs.insert(task.id) } else { selectedIDs.remove(task.id) }
                }
              )) {
                HStack(alignment: .firstTextBaseline) {
                  Text(userContent: task.title).fixedSize(horizontal: false, vertical: true)
                  Spacer(minLength: 8)
                  Text(task.estimatedMinutes.map(duration) ?? noEstimate)
                    .font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
              }
              .toggleStyle(.checkbox)
              .accessibilityIdentifier("reviews.plan.task.\(task.id)")
            }
          }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      HStack {
        Spacer()
        Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle)) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(ReviewCalmCopy.moveRow) { move(selected) }
          .disabled(selected.isEmpty || (todayRemaining != nil && (agenda == nil || workday == nil)))
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("reviews.plan.move")
      }
      .padding(.horizontal, 24).padding(.vertical, 14)
    }
    .frame(width: 500, height: todayRemaining == nil ? 500 : 550)
    .background(.background)
  }

  private func forecast(_ agenda: LorvexAgendaDay, window: Range<Int>) -> some View {
    let load = ReviewTomorrowLoad(agenda: agenda, window: window, selected: selected)
    let caption = load.plannedMinutes > window.count
      ? CalendarWeekDayLoadCaption.over(minutes: load.plannedMinutes - window.count)
      : CalendarWeekDayLoadCaption.busy(minutes: load.plannedMinutes, freeMinutes: window.count - load.plannedMinutes)
    return VStack(alignment: .leading, spacing: 9) {
      HStack {
        LorvexPageLabel(String(localized: "settings.working_hours.title", defaultValue: "Day Hours", table: "Localizable", bundle: LorvexL10n.bundle))
        Spacer()
        Text(TodayCalmCopy.timeRange(start: window.lowerBound, end: window.upperBound)).foregroundStyle(.secondary)
      }
      if let todayRemaining {
        LorvexDayTransferForecast(todayRemaining: todayRemaining, tomorrow: load, window: window)
          .accessibilityIdentifier("today.transfer.forecast")
      } else {
        Text(caption.visibleText ?? caption.sentence).accessibilityLabel(caption.sentence).font(LorvexDesign.Typography.sectionHeader).fixedSize(horizontal: false, vertical: true)
        GeometryReader { geometry in
          let unit = geometry.size.width / CGFloat(max(window.count, load.plannedMinutes))
          HStack(spacing: 0) {
            Rectangle().fill(.secondary.opacity(0.6)).frame(width: CGFloat(load.meetingMinutes) * unit)
            Rectangle().fill(.secondary).frame(width: CGFloat(load.existingMinutes) * unit)
            Rectangle().fill(LorvexDesign.Palette.Destination.review).frame(width: CGFloat(load.selectedMinutes) * unit)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary)
          .clipShape(Capsule())
        }
        .frame(height: 6).accessibilityHidden(true)
      }
      if load.unknownCount > 0 {
        HStack(spacing: LorvexDesign.Spacing.xs) {
          Text(String(localized: "review.plan.excluded", defaultValue: "Excluded from time estimate",
            table: "Localizable", bundle: LorvexL10n.bundle))
          Text(load.unknownCount, format: .number).monospacedDigit()
            .padding(.horizontal, LorvexDesign.Spacing.xs).background(.quaternary, in: Capsule())
        }
        .font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
      }
      Divider()
      HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
        metric(String(localized: "command_palette.group.events", defaultValue: "Events",
          table: "Localizable", bundle: LorvexL10n.bundle), count: agenda.events.count, minutes: load.meetingMinutes, color: .secondary.opacity(0.6))
        metric(String(localized: "command_palette.group.tasks", defaultValue: "Tasks",
          table: "Localizable", bundle: LorvexL10n.bundle), count: agenda.tasks.count, minutes: load.existingMinutes, color: .secondary)
        metric(selectedLabel, count: selected.count, minutes: load.selectedMinutes, color: LorvexDesign.Palette.Destination.review)
      }
      DisclosureGroup(isExpanded: $showAgenda) {
        ForEach(agenda.reviewItems) { item in
          switch item.kind {
          case .event(let event):
            fact(event.title, event.listTimeLabel(on: dayKey, range: TodayCalmCopy.timeRange(start:end:)) ?? TodayCalmCopy.allDay)
          case .task(let task):
            fact(task.title, (task.time(on: dayKey)?.count ?? task.estimatedMinutes).map(duration) ?? noEstimate)
          case .now: EmptyView()
          }
        }
        if agenda.tasks.isEmpty && agenda.events.isEmpty { Text(ReviewCalmCopy.tomorrowEmpty) }
      } label: {
        Text(String(localized: "review.plan.already", defaultValue: "Already planned", table: "Localizable", bundle: LorvexL10n.bundle))
          .foregroundStyle(.secondary)
      }
      .disclosureGroupStyle(AgendaDisclosure())
      .accessibilityIdentifier("reviews.plan.agenda")
    }
    .padding(14)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    .accessibilityIdentifier("reviews.plan.forecast")
  }

  /// Give the entire disclosure label the same native button and keyboard action.
  private struct AgendaDisclosure: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Button {
          lorvexAnimated(LorvexDesign.Motion.quick) { configuration.isExpanded.toggle() }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.xs) {
            Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.forward")
              .font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
            configuration.label
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if configuration.isExpanded { configuration.content }
      }
    }
  }

  private func metric(_ label: String, count: Int, minutes: Int, color: Color) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
        Text(label)
        Text(count, format: .number).monospacedDigit()
      }
      .font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
      Text(duration(minutes)).font(LorvexDesign.Typography.primaryEmphasis)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func duration(_ minutes: Int) -> String {
    LorvexDurationFormat.hoursAndMinutes(minutes)
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(userContent: label)
      Spacer(minLength: 8)
      Text(value).monospacedDigit().foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
