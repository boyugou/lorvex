#if os(macOS) || os(iOS)
  import LorvexDomain
  import SwiftUI

  /// Today and the editor share habit identity and the day's ordinary check-in
  /// actions. Switching routines changes only which rows are in view.
  public struct TodayHabitRoutine: View {
    public let catalog: HabitCatalogSnapshot
    public let day: String
    public let nowMinutes: Int?
    public let checkIn: (LorvexHabit) async -> Void
    public let undoOne: (LorvexHabit) async -> Void
    public let skip: (LorvexHabit) async -> Void
    public let save: (HabitRoutinePeriod, HabitRoutine) async throws -> Void

    @State private var selection: HabitRoutinePeriod?
    @State private var editor: HabitRoutinePeriod?
    @State private var writing = false
    @State private var expandedOverride: Bool?

    public init(
      catalog: HabitCatalogSnapshot, day: String, nowMinutes: Int?,
      checkIn: @escaping (LorvexHabit) async -> Void,
      undoOne: @escaping (LorvexHabit) async -> Void,
      skip: @escaping (LorvexHabit) async -> Void,
      save: @escaping (HabitRoutinePeriod, HabitRoutine) async throws -> Void
    ) {
      self.catalog = catalog
      self.day = day
      self.nowMinutes = nowMinutes
      self.checkIn = checkIn
      self.undoOne = undoOne
      self.skip = skip
      self.save = save
    }

    private var current: HabitRoutinePeriod {
      catalog.routines.current(at: nowMinutes, habits: catalog.habits)
    }
    private var period: HabitRoutinePeriod { selection ?? current }

    public var body: some View {
      Group {
        if catalog.hasConfiguredRoutine {
          let rows = catalog.routines.members(period, on: day, habits: catalog.habits)
          let expanded =
            expandedOverride ?? catalog.routines.showsSteps(period, at: nowMinutes, rows: rows)
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
            HStack(spacing: LorvexDesign.Spacing.s) {
              Button {
                lorvexAnimated(.snappy(duration: 0.18)) { expandedOverride = !expanded }
              } label: {
                HStack(spacing: LorvexDesign.Spacing.s) {
                  Image(systemName: RoutineCopy.symbol(period)).foregroundStyle(.secondary)
                  Text(RoutineCopy.name(period)).font(LorvexDesign.Typography.pageLabel)
                  let eligible = rows.filter { !$0.isSkipped }
                  if !eligible.isEmpty {
                    let kept = eligible.filter { $0.completionsToday >= max(1, $0.targetCount) }
                      .count
                    Text(verbatim: "\(kept.formatted())/\(eligible.count.formatted())")
                      .font(LorvexDesign.Typography.tertiaryText).monospacedDigit().foregroundStyle(
                        .secondary)
                  }
                  Image(systemName: expanded ? "chevron.down" : "chevron.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("today.routine.disclosure")
              Menu {
                Button(RoutineCopy.edit) { editor = period }
                Divider()
                ForEach(HabitRoutinePeriod.allCases) { option in
                  Button {
                    selection = option
                    expandedOverride = true
                  } label: {
                    Label(
                      RoutineCopy.name(option),
                      systemImage: option == period ? "checkmark" : RoutineCopy.symbol(option))
                  }
                }
              } label: {
                Image(systemName: "ellipsis.circle").frame(
                  minWidth: Self.rowHeight, minHeight: Self.rowHeight)
              }
              #if os(macOS)
                .menuStyle(.borderlessButton)
              #endif
              .menuIndicator(.hidden).fixedSize()
              .accessibilityLabel(RoutineCopy.actions)
              .accessibilityIdentifier("today.routine.menu")
            }
            if expanded {
              if rows.isEmpty {
                if catalog.routines[period].habitIDs.isEmpty {
                  Button(RoutineCopy.choose) { editor = period }.buttonStyle(.borderless)
                } else {
                  Text(RoutineCopy.nothingDue).font(LorvexDesign.Typography.secondaryText)
                    .foregroundStyle(.secondary)
                }
              }
              ForEach(rows) { habit in
                if habit.id != rows.first?.id { Divider().accessibilityHidden(true) }
                habitRow(habit)
              }
            }
          }
        } else {
          Menu {
            ForEach(HabitRoutinePeriod.allCases) { period in
              Button {
                editor = period
              } label: {
                Label(RoutineCopy.name(period), systemImage: RoutineCopy.symbol(period))
              }
            }
          } label: {
            Label(RoutineCopy.setUp, systemImage: "sun.and.horizon")
          }
          #if os(macOS)
            .menuStyle(.borderlessButton)
          #endif
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("today.routine.setup")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onChange(of: current) { _, _ in
        selection = nil
        expandedOverride = nil
      }
      .onChange(of: day) { _, _ in
        selection = nil
        expandedOverride = nil
      }
      .sheet(item: $editor) { period in
        HabitRoutineEditor(
          period: period, routine: catalog.routines[period], habits: catalog.habits,
          otherStart: otherStart(for: period)
        ) { routine in
          try await save(period, routine)
          selection = period
          expandedOverride = true
        }
      }
    }

    private func otherStart(for period: HabitRoutinePeriod) -> Int? {
      let other = catalog.routines[period == .morning ? .evening : .morning]
      return other.habitIDs.isEmpty ? nil : other.startMinutes
    }

    private func habitRow(_ habit: LorvexHabit) -> some View {
      let count = habit.completionsToday
      let target = max(1, habit.targetCount)
      let done = count >= target
      return HStack(spacing: LorvexDesign.Spacing.s) {
        Button {
          write { if habit.isSkipped { await skip(habit) } else { await checkIn(habit) } }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.m) {
            LorvexHabitCheckRing(
              fraction: Double(count) / Double(target),
              tint: done ? LorvexDesign.Palette.done : LorvexHabitPalette.baseColor(for: habit),
              diameter: 26, symbol: LorvexSymbol.name(for: habit.icon, fallback: "repeat"),
              segments: target, isSkipped: habit.isSkipped)
            Text(userContent: habit.name)
              .foregroundStyle(done || habit.isSkipped ? Color.secondary : .primary)
            Spacer(minLength: 0)
            if habit.isSkipped {
              Text(RoutineCopy.skipped).foregroundStyle(.secondary)
            } else if target > 1 {
              Text(verbatim: "\(count.formatted())/\(target.formatted())").monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
          .frame(minHeight: Self.rowHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(writing || (done && target > 1))
        .accessibilityValue(done ? RoutineCopy.done : "")
        .accessibilityIdentifier("today.routine.check.\(habit.id)")
        if LorvexHabitSkip.action(for: habit) != nil || (target > 1 && count > 0) {
          Menu {
            if let action = LorvexHabitSkip.action(for: habit) {
              Button(action == .skip ? RoutineCopy.skip : RoutineCopy.unskip) {
                write { await skip(habit) }
              }
            }
            if target > 1 && count > 0 {
              Button(RoutineCopy.undoOne) { write { await undoOne(habit) } }
            }
          } label: {
            Image(systemName: "ellipsis.circle").frame(
              minWidth: Self.rowHeight, minHeight: Self.rowHeight)
          }
          #if os(macOS)
            .menuStyle(.borderlessButton)
          #endif
          .menuIndicator(.hidden)
          .fixedSize()
          .accessibilityLabel(Text(verbatim: "\(habit.name), \(RoutineCopy.actions)"))
          .accessibilityIdentifier("today.routine.actions.\(habit.id)")
          .disabled(writing)
        }
      }
    }

    private static var rowHeight: CGFloat {
      #if os(iOS)
        44
      #else
        30
      #endif
    }

    private func write(_ action: @escaping @MainActor () async -> Void) {
      guard !writing else { return }
      expandedOverride = true
      writing = true
      Task {
        await action()
        writing = false
      }
    }
  }
#endif
