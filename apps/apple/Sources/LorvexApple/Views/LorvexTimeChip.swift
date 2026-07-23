import LorvexCore
import SwiftUI

/// A time-of-day control matching ``LorvexDateChip``'s polish: a chip that reads
/// as the formatted time and opens a popover with a live preview and a custom
/// hour + minute grid (accent-disc selection, in the spirit of
/// ``LorvexMiniMonth``), replacing the stock compact hour/minute `DatePicker` —
/// a crude stepper field. The bound `Date`'s day component is ignored; only the
/// hour and minute are read and written. Hours follow the locale's 12-/24-hour
/// convention (a 12-hour locale gets an AM/PM segment using the locale symbols).
struct LorvexTimeChip: View {
  @Environment(\.timeZone) private var timeZone

  let date: Date
  var accessibilityIdentifier: String = "lorvex.timeChip"
  let onSet: (Date) -> Void

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: "clock")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.tint)
        Text(TaskReminderDateTime.displayTimeString(from: date, timeZone: timeZone))
          .font(LorvexDesign.Typography.primaryText)
          .monospacedDigit()
          .foregroundStyle(.primary)
      }
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background(.quaternary.opacity(0.55), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(TaskReminderDateTime.displayTimeString(from: date, timeZone: timeZone))
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier(accessibilityIdentifier)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      LorvexTimeChipPopover(date: date, onSet: onSet)
        .environment(\.timeZone, timeZone)
    }
  }
}

private struct LorvexTimeChipPopover: View {
  @Environment(\.timeZone) private var timeZone

  let date: Date
  let onSet: (Date) -> Void

  private static let cellSize: CGFloat = 34

  private var calendar: Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
  }

  private var currentHour: Int { calendar.component(.hour, from: date) }
  private var currentMinute: Int { calendar.component(.minute, from: date) }
  private var isPM: Bool { currentHour >= 12 }

  /// Whether the locale formats hours without an AM/PM marker.
  private var uses24Hour: Bool {
    let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH"
    return !template.contains("a")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      // Live preview of the chosen time.
      Text(TaskReminderDateTime.displayTimeString(from: date, timeZone: timeZone))
        .font(LorvexDesign.Typography.sectionHeader)
        .monospacedDigit()
        .foregroundStyle(.tint)

      hourGrid

      if !uses24Hour {
        Picker("", selection: meridiemBinding) {
          Text(Self.amSymbol).tag(false)
          Text(Self.pmSymbol).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("lorvex.timeChip.meridiem")
      }

      Divider()

      minuteGrid
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 280)
    .accessibilityIdentifier("lorvex.timeChip.popover")
  }

  // MARK: Hours

  private var hourValues: [Int] { uses24Hour ? Array(0...23) : Array(1...12) }

  private var hourGrid: some View {
    grid {
      ForEach(hourValues, id: \.self) { value in
        cell(
          label: uses24Hour ? String(format: "%02d", value) : "\(value)",
          selected: isHourSelected(value)
        ) {
          commit(hour: hour24(forDisplay: value), minute: currentMinute)
        }
      }
    }
  }

  private func isHourSelected(_ displayHour: Int) -> Bool {
    guard !uses24Hour else { return displayHour == currentHour }
    let current12 = currentHour % 12 == 0 ? 12 : currentHour % 12
    return displayHour == current12
  }

  /// Map a displayed hour (1...12 with the current AM/PM, or 0...23) to a
  /// 24-hour value.
  private func hour24(forDisplay displayHour: Int) -> Int {
    guard !uses24Hour else { return displayHour }
    return (displayHour % 12) + (isPM ? 12 : 0)
  }

  private var meridiemBinding: Binding<Bool> {
    Binding(
      get: { isPM },
      set: { pm in commit(hour: (currentHour % 12) + (pm ? 12 : 0), minute: currentMinute) }
    )
  }

  // MARK: Minutes (5-minute steps)

  private var minuteGrid: some View {
    grid {
      ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
        cell(label: String(format: ":%02d", value), selected: value == currentMinute) {
          commit(hour: currentHour, minute: value)
        }
      }
    }
  }

  // MARK: Shared cell + grid (accent disc when selected, like LorvexMiniMonth)

  private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(Self.cellSize), spacing: 2), count: 6),
      spacing: 2,
      content: content
    )
  }

  private func cell(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label)
        .font(LorvexDesign.Typography.secondaryText.weight(selected ? .semibold : .regular))
        .monospacedDigit()
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .frame(width: Self.cellSize, height: 30)
        .background {
          if selected {
            Circle().fill(Color.accentColor).frame(width: 30, height: 30)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  private func commit(hour: Int, minute: Int) {
    let updated = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    onSet(updated)
  }

  private static let amSymbol: String = DateFormatter().amSymbol ?? "AM"
  private static let pmSymbol: String = DateFormatter().pmSymbol ?? "PM"
}
