import LorvexCore
import SwiftUI

/// A reversible selection until the user confirms it. The estimate stays in
/// sight above the scrolling tasks, including while reading the existing agenda.
struct MobileReviewTomorrowPlan: View {
  let store: MobileStore
  let dayKey: String
  let tasks: [ReviewTaskSummary]
  let move: ([ReviewTaskSummary]) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var selectedIDs: Set<String>
  @State private var showAgenda = false
  @State private var agenda: LorvexAgendaDay?
  @State private var loading = true

  init(store: MobileStore, dayKey: String, tasks: [ReviewTaskSummary], move: @escaping ([ReviewTaskSummary]) -> Void) {
    self.store = store
    self.dayKey = dayKey
    self.tasks = tasks
    self.move = move
    _selectedIDs = State(initialValue: Set(tasks.map(\.id)))
  }

  static var title: String {
    String(localized: "review.plan.tomorrow", defaultValue: "Plan Tomorrow", table: "Localizable", bundle: MobileL10n.bundle)
  }

  private var selected: [ReviewTaskSummary] { tasks.filter { selectedIDs.contains($0.id) } }

  private var noEstimate: String {
    String(localized: "task_detail.picker.no_length", defaultValue: "No Estimate", table: "Localizable", bundle: MobileL10n.bundle)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if !typeSize.isAccessibilitySize { forecast.padding() }
        List {
          if typeSize.isAccessibilitySize { Section { forecast } }
          if let agenda {
            Section {
              DisclosureGroup(isExpanded: $showAgenda) {
                if agenda.reviewItems.isEmpty {
                  Text(MobileReviewCalmCopy.tomorrowEmpty).foregroundStyle(.secondary)
                } else {
                  ForEach(agenda.reviewItems) { item in
                    switch item.kind {
                    case .event(let event):
                      fact(event.title, event.listTimeLabel(on: dayKey, range: MobileTodayCalmCopy.timeRange(start:end:)) ?? MobileReviewCalmCopy.allDay)
                    case .task(let task):
                      fact(task.title, (task.time(on: dayKey)?.count ?? task.estimatedMinutes).map { LorvexDurationFormat.hoursAndMinutes($0) } ?? noEstimate)
                    case .now: EmptyView()
                    }
                  }
                }
              } label: {
                Label(String(localized: "review.plan.already", defaultValue: "Already planned", table: "Localizable", bundle: MobileL10n.bundle),
                  systemImage: "calendar")
              }
              .accessibilityIdentifier("review.plan.agenda")
            }
          }
          Section(MobileReviewCalmCopy.stillOpenLabel) {
            ForEach(tasks) { task in
              let isSelected = selectedIDs.contains(task.id)
              Button {
                if isSelected { selectedIDs.remove(task.id) } else { selectedIDs.insert(task.id) }
              } label: {
                HStack(spacing: LorvexDesign.Spacing.m) {
                  Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? LorvexDesign.Palette.Destination.review : Color.secondary)
                  fact(task.title, task.estimatedMinutes.map { LorvexDurationFormat.hoursAndMinutes($0) } ?? noEstimate)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(isSelected ? .isSelected : [])
              .accessibilityIdentifier("review.plan.task.\(task.id)")
            }
          }
        }
        Button { move(selected) } label: {
          HStack {
            Text(MobileReviewCalmCopy.moveRow)
            Text(selected.count, format: .number).monospacedDigit()
              .padding(.horizontal, LorvexDesign.Spacing.s).background(.black.opacity(0.18), in: Capsule())
          }
          .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent).tint(LorvexDesign.Palette.Destination.review)
        .disabled(selected.isEmpty)
        .accessibilityIdentifier("review.plan.move")
        .padding(.horizontal).padding(.vertical, LorvexDesign.Spacing.s)
      }
      .mobileSheetTitle(Self.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle)) { dismiss() }
            .accessibilityIdentifier("review.plan.cancel")
        }
      }
      .task(id: store.dayReviewReadKey) { await load() }
    }
  }

  private func load() async {
    loading = true
    await store.loadWorkdayWindow()
    let fresh = await store.loadTomorrowAgenda()
    guard !Task.isCancelled else { return }
    agenda = fresh?.key == dayKey ? fresh : nil
    loading = false
  }

  @ViewBuilder private var forecast: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(verbatim: dayAndHours)
        .font(LorvexDesign.Typography.pageLabel).foregroundStyle(.secondary)
      if let agenda, let window = store.workdayWindow {
        let load = ReviewTomorrowLoad(agenda: agenda, window: window, selected: selected)
        let remaining = window.count - load.plannedMinutes
        let duration = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(abs(remaining)))
        let caption = remaining < 0
          ? String(localized: "calendar.week.load.over", defaultValue: "\(duration) over", table: "Localizable", bundle: MobileL10n.bundle)
          : String(localized: "review.plan.available", defaultValue: "\(duration) free", table: "Localizable", bundle: MobileL10n.bundle)
        Text(caption, serifVoice: .pageSentence)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("review.plan.forecast")
        ProgressView(value: Double(min(window.count, load.plannedMinutes)), total: Double(window.count))
          .tint(LorvexDesign.Palette.Destination.review)
          .accessibilityHidden(true)
        if load.unknownCount > 0 {
          HStack {
            Text(String(localized: "review.plan.excluded", defaultValue: "Excluded from time estimate", table: "Localizable", bundle: MobileL10n.bundle))
            Text(load.unknownCount, format: .number)
          }
          .font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
          .accessibilityElement(children: .combine)
        }
      } else if loading {
        ProgressView()
      } else {
        Button(String(localized: "common.try_again", defaultValue: "Try Again", table: "Localizable", bundle: MobileL10n.bundle)) {
          Task { await load() }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var dayAndHours: String {
    let day = MobileReviewCalmCopy.dayLabel(dayKey)
    guard let window = store.workdayWindow else { return day }
    return day + " · " + MobileTodayCalmCopy.timeRange(start: window.lowerBound, end: window.upperBound)
  }

  private func fact(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(userContent: title).fixedSize(horizontal: false, vertical: true)
      Text(detail).font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
