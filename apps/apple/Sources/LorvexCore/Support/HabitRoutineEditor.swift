#if os(macOS) || os(iOS)
  import LorvexDomain
  import SwiftUI

  struct HabitRoutineEditor: View {
    let period: HabitRoutinePeriod
    let habits: [LorvexHabit]
    let otherStart: Int?
    let save: (HabitRoutine) async throws -> Void
    @State private var draft: HabitRoutine
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(
      period: HabitRoutinePeriod, routine: HabitRoutine, habits: [LorvexHabit],
      otherStart: Int?, save: @escaping (HabitRoutine) async throws -> Void
    ) {
      self.period = period
      self.habits = habits.filter { !$0.archived }
      self.otherStart = otherStart
      self.save = save
      _draft = State(initialValue: routine)
    }

    private var selected: [LorvexHabit] {
      let byID = Dictionary(habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      return draft.habitIDs.compactMap { byID[$0] }
    }

    // The picker represents a wall clock, independent of either device's time
    // zone or the DST transition on the date someone edits their routine.
    private var time: Binding<Date> {
      Binding(
        get: { Date(timeIntervalSince1970: Double(draft.startMinutes * 60)) },
        set: { draft.startMinutes = ((Int($0.timeIntervalSince1970) % 86400 + 86400) % 86400) / 60 }
      )
    }

    var body: some View {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        Label(RoutineCopy.name(period), systemImage: RoutineCopy.symbol(period))
          .font(LorvexDesign.Typography.sectionHeader).accessibilityAddTraits(.isHeader)
        DatePicker(RoutineCopy.start, selection: time, displayedComponents: .hourAndMinute)
          .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        if draft.startMinutes == otherStart {
          Text(RoutineCopy.sameTime).foregroundStyle(.secondary)
        }
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
            let chosen = selected
            ForEach(chosen) { habit in
              HStack {
                habitLabel(habit)
                Spacer()
                if let i = chosen.firstIndex(where: { $0.id == habit.id }) {
                  iconButton("arrow.up", title: RoutineCopy.up, habit: habit, id: "up.\(habit.id)") {
                    swap(habit.id, chosen[i - 1].id)
                  }.disabled(i == 0)
                  iconButton("arrow.down", title: RoutineCopy.down, habit: habit, id: "down.\(habit.id)") {
                    swap(habit.id, chosen[i + 1].id)
                  }.disabled(i == chosen.count - 1)
                }
                iconButton("minus.circle", title: RoutineCopy.remove, habit: habit, id: "remove.\(habit.id)") {
                  draft.habitIDs.removeAll { $0 == habit.id }
                }
              }
            }
            let available = habits.filter { !draft.habitIDs.contains($0.id) }
            if !available.isEmpty {
              if !chosen.isEmpty { Divider() }
              Text(RoutineCopy.choose).font(LorvexDesign.Typography.pageLabel).foregroundStyle(
                .secondary)
              ForEach(available) { habit in
                Button {
                  draft.habitIDs.append(habit.id)
                } label: {
                  HStack {
                    habitLabel(habit)
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                  }.frame(minHeight: Self.hitSize).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("routine.add.\(habit.id)")
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error { Text(userContent: error).font(.callout).foregroundStyle(.secondary) }
        HStack {
          Spacer()
          Button(RoutineCopy.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
          Button(RoutineCopy.save) {
            saving = true
            Task {
              do {
                try await save(draft)
                dismiss()
              } catch { self.error = error.localizedDescription }
              saving = false
            }
          }.keyboardShortcut(.defaultAction)
            .disabled(!draft.habitIDs.isEmpty && draft.startMinutes == otherStart)
            .accessibilityIdentifier("routine.save")
        }
      }
      .padding().disabled(saving).interactiveDismissDisabled(saving)
      #if os(macOS)
        .frame(width: 380, height: min(500, 188 + CGFloat(habits.count) * 34))
      #else
        .presentationDetents([.medium, .large])
      #endif
    }

    private static var hitSize: CGFloat {
      #if os(iOS)
        44
      #else
        24
      #endif
    }

    private func habitLabel(_ habit: LorvexHabit) -> some View {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: LorvexSymbol.name(for: habit.icon, fallback: "repeat"))
          .foregroundStyle(LorvexHabitPalette.baseColor(for: habit)).frame(width: 24)
        Text(userContent: habit.name)
      }
    }

    private func iconButton(
      _ symbol: String, title: String, habit: LorvexHabit, id: String, action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        Image(systemName: symbol).frame(minWidth: Self.hitSize, minHeight: Self.hitSize)
      }.buttonStyle(.borderless).help(title).accessibilityLabel(Text(verbatim: "\(title), \(habit.name)"))
        .accessibilityIdentifier("routine.\(id)")
    }

    private func swap(_ id: String, _ other: String) {
      guard let a = draft.habitIDs.firstIndex(of: id), let b = draft.habitIDs.firstIndex(of: other)
      else { return }
      draft.habitIDs.swapAt(a, b)
    }
  }
#endif
