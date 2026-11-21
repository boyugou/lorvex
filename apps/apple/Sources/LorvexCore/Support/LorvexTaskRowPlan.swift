import Foundation
import SwiftUI

/// The planned work day and the independent deadline as they appear together
/// in a task row. Only an explicit work date creates this line.
public struct LorvexTaskRowPlan: Equatable, Sendable {
  public let work: String
  public let deadline: String?
  public let sharesDeadline: Bool
  public let overdue: Bool
  public let dueSoon: Bool
  /// The work date on a surface with a separate Due column.
  public let workOnly: String

  public init?(
    _ task: LorvexTask, now: Date = Date(), timeZone: TimeZone,
    dayInHeading: String? = nil, timeAlreadyShown: Bool = false
  ) {
    guard let planned = task.plannedDate else { return nil }
    let key = LorvexDateFormatters.ymdUTC.string(from: planned)
    let today = LorvexDateFormatters.ymdUTC.string(
      from: PlannedDayBridge.storageDate(forLocalInstant: now, timeZone: timeZone))
    let slot = timeAlreadyShown && key == today ? nil : task.plannedTime
    // Today already names this day. Keep a saved time if the timeline didn't
    // supply it; an earlier plan on a carried-over task still names its day.
    guard key != dayInHeading || slot != nil else { return nil }
    let day = LorvexDayPhrase.phrase(for: planned, logicalDay: today, position: .inline)
    let plan = String(localized: "task.row.planned_day", defaultValue: "Planned for \(day)", bundle: CoreL10n.bundle)
    sharesDeadline = task.dueDate.map { LorvexDateFormatters.ymdUTC.string(from: $0) == key } ?? false
    let clock = slot.map { lorvexClockRangeLabel(startMinutes: $0.lowerBound, endMinutes: $0.upperBound) }
    workOnly = [plan, clock].compactMap { $0 }.joined(separator: " · ")
    if sharesDeadline {
      let both = String(localized: "task.row.planned_and_due", defaultValue: "Planned and due \(day)", bundle: CoreL10n.bundle)
      work = [both, clock].compactMap { $0 }.joined(separator: " · ")
      deadline = nil
    } else {
      work = workOnly
      deadline = task.dueDate.map {
        Self.dueLabel(LorvexDayPhrase.phrase(for: $0, logicalDay: today, position: .inline))
      }
    }
    overdue = task.isOverdue(now: now, timeZone: timeZone)
    dueSoon = task.isDueSoon(now: now, timeZone: timeZone)
  }

  public static func dueLabel(_ day: String) -> String {
    String(localized: "quick_add.preview.due", defaultValue: "Due \(day)", bundle: CoreL10n.bundle)
  }
}

extension EnvironmentValues {
  /// The work day named by the page heading, such as Today.
  @Entry public var lorvexTaskRowDay: String? = nil
}

public struct LorvexTaskRowPlanLine: View {
  let plan: LorvexTaskRowPlan

  public init(_ plan: LorvexTaskRowPlan) { self.plan = plan }

  public var body: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.m, lineSpacing: LorvexDesign.Spacing.xxs) {
      Text(plan.work)
        .foregroundStyle(plan.sharesDeadline ? deadlineStyle : AnyShapeStyle(.secondary))
        .fixedSize(horizontal: false, vertical: true)
      if let deadline = plan.deadline {
        Text(deadline).foregroundStyle(deadlineStyle).fixedSize(horizontal: false, vertical: true)
      }
    }
    #if os(macOS)
      .font(LorvexDesign.Typography.secondaryText)
    #else
      .font(.footnote)
    #endif
    .accessibilityElement(children: .combine)
  }

  private var deadlineStyle: AnyShapeStyle {
    if plan.overdue { return AnyShapeStyle(LorvexDesign.Palette.overdue) }
    return plan.dueSoon ? AnyShapeStyle(LorvexDesign.Palette.dueSoon) : AnyShapeStyle(.secondary)
  }
}
