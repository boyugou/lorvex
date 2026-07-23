#if DEBUG
  import LorvexCore
  import LorvexWidgetKitSupport
  import LorvexWidgetViews
  import SwiftUI

  /// DEBUG-only: hosts the real WidgetKit views at their canonical sizes so the
  /// widget design can be visually QA'd in the simulator (which can't screenshot
  /// live widgets). Shown as the app root when launched with `-lorvexWidgetGallery`.
  ///
  /// Renders in-app on purpose: the rows wrap `Link`/`Button(intent:)`, which an
  /// off-screen `ImageRenderer` collapses to placeholders but the live app draws
  /// faithfully.
  struct WidgetGalleryHostView: View {
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          group("Habits") {
            HStack(alignment: .top, spacing: 16) {
              cell("habits · small", 158, 158) {
                HabitsWidgetView(habits: Self.sampleHabits, family: .systemSmall)
              }
            }
            cell("habits · medium", 338, 158) {
              HabitsWidgetView(habits: Self.sampleHabits, family: .systemMedium)
            }
          }
          group("Progress") {
            HStack(alignment: .top, spacing: 16) {
              cell("progress · small", 158, 158) {
                ProgressWidgetView(snapshot: Self.progressSnapshot, family: .systemSmall)
              }
              accessoryCell("progress · circular", 72, 72) {
                ProgressWidgetView(snapshot: Self.progressSnapshot, family: .accessoryCircular)
              }
            }
          }
          group("Small") {
            HStack(alignment: .top, spacing: 16) {
              cell("systemSmall", 158, 158) { LorvexWidgetView(model: Self.model(.systemSmall)) }
              cell("all done", 158, 158) {
                LorvexWidgetView(model: Self.model(.systemSmall, state: .empty))
              }
            }
          }
          group("Accessory (Lock Screen)") {
            HStack(alignment: .top, spacing: 16) {
              accessoryCell("circular", 72, 72) {
                LorvexWidgetView(model: Self.model(.accessoryCircular))
              }
              accessoryCell("rectangular", 170, 72) {
                LorvexWidgetView(model: Self.model(.accessoryRectangular))
              }
            }
            accessoryCell("inline", 240, 30) {
              LorvexWidgetView(model: Self.model(.accessoryInline))
            }
          }
          group("Medium & Large") {
            cell("systemMedium", 338, 158) { LorvexWidgetView(model: Self.model(.systemMedium)) }
            cell("systemLarge", 338, 354) { LorvexWidgetView(model: Self.model(.systemLarge)) }
          }
        }
        .padding(24)
      }
      .background(LorvexDesign.Palette.groupedBackground)
    }

    // MARK: Layout chrome

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
      VStack(alignment: .leading, spacing: 14) {
        Text(title).font(.title3.weight(.semibold))
        content()
      }
    }

    private func cell(
      _ title: String, _ width: CGFloat, _ height: CGFloat,
      @ViewBuilder _ content: () -> some View
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        content()
          .frame(width: width, height: height, alignment: .top)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
      }
    }

    private func accessoryCell(
      _ title: String, _ width: CGFloat, _ height: CGFloat,
      @ViewBuilder _ content: () -> some View
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        content()
          .frame(width: width, height: height)
          .padding(10)
          .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          .environment(\.colorScheme, .dark)
      }
    }

    // MARK: Sample data

    static func sampleRows(_ count: Int) -> [WidgetTaskRenderRow] {
      let data: [(String, String?, String?, Int?)] = [
        ("Reply to the investor update email", "Overdue · Work", "P1", 1),
        ("Review the Q3 planning doc", "Today 2:00 PM · 45m", "P1", 1),
        ("Refactor the sync layer", "90m · Engineering", "P2", 2),
        ("Buy groceries for the week", "Personal", "P2", 2),
        ("Read the GRPO paper", "Research", "P3", 3),
        ("Renew passport", "In 5 days", "P3", 3),
      ]
      return data.prefix(count).enumerated().map { index, row in
        WidgetTaskRenderRow(
          id: "task-\(index)", title: row.0, metadata: row.1, priorityLabel: row.2,
          priorityTier: row.3, urlString: "lorvex://task/task-\(index)")
      }
    }

    /// Stats-only snapshot for the progress widget (2 done of 5 due today → 40%).
    static var progressSnapshot: WidgetSnapshot {
      WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: "UTC",
        stats: .init(focusCount: 3, overdueCount: 1, dueTodayCount: 3, completedTodayCount: 2),
        briefing: nil, focusTasks: [])
    }

    static var sampleHabits: [WidgetSnapshot.HabitSummary] {
      [
        .init(id: "h1", name: "Meditate", icon: "brain.head.profile", completedToday: 1, target: 1),
        .init(id: "h2", name: "Read 30 minutes", icon: "book.fill", completedToday: 0, target: 1),
        .init(id: "h3", name: "Drink water", icon: "drop.fill", completedToday: 2, target: 3),
        .init(id: "h4", name: "Morning run", icon: "figure.run", completedToday: 1, target: 1),
        .init(id: "h5", name: "Stretch", icon: "figure.mind.and.body", completedToday: 0, target: 2),
      ]
    }

    static func model(_ family: WidgetFamilyKind, state: WidgetRenderState = .content)
      -> WidgetRenderModel
    {
      WidgetRenderModel(
        family: family, state: state,
        headline: "Today",
        subheadline: "3 in focus · 1 overdue · 5 due today",
        statusText: "Updated now",
        staleAgeLabel: nil,
        focusCountText: "3", focusCount: 3,
        completedCount: 2,
        attentionCountText: "1 overdue",
        taskRows: state == .empty ? [] : sampleRows(family.maxTaskRows),
        urlString: "lorvex://today")
    }
  }
#endif
