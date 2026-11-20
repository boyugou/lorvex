import SwiftUI

enum ReviewPlanCopy {
  static var schedule: String {
    String(localized: "today.calm.schedule.title", defaultValue: "Schedule", bundle: CoreL10n.bundle)
  }
  static var setDate: String {
    String(localized: "task_detail.metadata.set_date", defaultValue: "Set Date", bundle: CoreL10n.bundle)
  }
  static var cancel: String {
    String(localized: "common.cancel", defaultValue: "Cancel", bundle: CoreL10n.bundle)
  }
  static var less: String {
    String(localized: "today.list.briefing.less", defaultValue: "Show less", bundle: CoreL10n.bundle)
  }
}

#if os(macOS) || os(iOS)
struct ReviewScheduleSheet: View {
  let task: ReviewTaskSummary
  let schedule: (String) async -> Void
  @State private var date: Date
  @Environment(\.dismiss) private var dismiss

  init(task: ReviewTaskSummary, tomorrow: String, schedule: @escaping (String) async -> Void) {
    self.task = task
    self.schedule = schedule
    _date = State(initialValue: PlannedDayBridge.displayDate(forLogicalDay: task.plannedDate ?? tomorrow) ?? Date())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Text(userContent: task.title).font(.headline).accessibilityAddTraits(.isHeader)
      DatePicker(ReviewPlanCopy.setDate, selection: $date, displayedComponents: .date)
        .datePickerStyle(.graphical)
      HStack {
        Spacer()
        Button(ReviewPlanCopy.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(ReviewPlanCopy.schedule) {
          let key = LorvexDateFormatters.ymdUTC.string(from: PlannedDayBridge.storageDate(forLocalInstant: date))
          dismiss()
          Task { await schedule(key) }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    #if os(macOS)
      .frame(width: 330)
    #else
      .presentationDetents([.medium, .large])
    #endif
  }
}
#endif
