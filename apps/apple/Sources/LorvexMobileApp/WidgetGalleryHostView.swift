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
  /// faithfully. The content is ``WidgetGallerySample``'s sample day, read at
  /// 10:12 through the real `WidgetRenderModelBuilder`, so the gallery shows
  /// what the builder makes of a running time, not hand-written rows.
  ///
  /// The gallery is taller than one screen, so `-lorvexWidgetGallerySection
  /// <section>` shows one of its sections alone: `today` (the small and medium
  /// Today families), `large`, `lock` (the Lock Screen families), or `more`
  /// (Habits and Progress). Without it every section is shown.
  struct WidgetGalleryHostView: View {
    private typealias Sample = WidgetGallerySample

    enum Section: String, CaseIterable {
      case today, large, lock, more
    }

    /// The section named on the command line, or nil for the whole gallery.
    static var requestedSection: Section? {
      let arguments = CommandLine.arguments
      guard let index = arguments.firstIndex(of: "-lorvexWidgetGallerySection"),
        index + 1 < arguments.count
      else { return nil }
      return Section(rawValue: arguments[index + 1])
    }

    private var sections: [Section] {
      Self.requestedSection.map { [$0] } ?? Section.allCases
    }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          ForEach(sections, id: \.self) { section in
            self.section(section)
          }
        }
        .padding(24)
      }
      .background(LorvexDesign.Palette.groupedBackground)
    }

    @ViewBuilder
    private func section(_ section: Section) -> some View {
      switch section {
      case .today:
        group("Today · small") {
          HStack(alignment: .top, spacing: 16) {
            cell("running", 158, 158) { LorvexWidgetView(model: Sample.model(.systemSmall)) }
            cell("next", 158, 158) { LorvexWidgetView(model: Sample.model(.systemSmall, at: Sample.earlyClock)) }
          }
          HStack(alignment: .top, spacing: 16) {
            cell("open day", 158, 158) { LorvexWidgetView(model: Sample.openDayModel(.systemSmall)) }
            cell("all done", 158, 158) { LorvexWidgetView(model: Sample.emptyModel(.systemSmall)) }
          }
        }
        group("Today · medium") {
          cell("systemMedium", 338, 158) { LorvexWidgetView(model: Sample.model(.systemMedium)) }
          cell("systemMedium · open day", 338, 158) {
            LorvexWidgetView(model: Sample.openDayModel(.systemMedium))
          }
        }
      case .large:
        group("Today · large") {
          HStack(alignment: .top, spacing: 16) {
            cell("systemLarge", 338, 354) { LorvexWidgetView(model: Sample.model(.systemLarge)) }
          }
          cell("systemLarge · open day", 338, 354) {
            LorvexWidgetView(model: Sample.openDayModel(.systemLarge))
          }
        }
      case .lock:
        group("Today · Lock Screen") {
          HStack(alignment: .top, spacing: 16) {
            accessoryCell("circular", 72, 72) {
              LorvexWidgetView(model: Sample.model(.accessoryCircular))
            }
            accessoryCell("circular · open day", 72, 72) {
              LorvexWidgetView(model: Sample.openDayModel(.accessoryCircular))
            }
            accessoryCell("circular · ahead", 72, 72) {
              LorvexWidgetView(model: Sample.model(.accessoryCircular, at: Sample.earlyClock))
            }
          }
          HStack(alignment: .top, spacing: 16) {
            accessoryCell("rectangular", 170, 72) {
              LorvexWidgetView(model: Sample.model(.accessoryRectangular))
            }
            accessoryCell("rectangular · open day", 170, 72) {
              LorvexWidgetView(model: Sample.openDayModel(.accessoryRectangular))
            }
          }
          accessoryCell("inline", 300, 30) {
            LorvexWidgetView(model: Sample.model(.accessoryInline))
          }
          accessoryCell("inline · open day", 300, 30) {
            LorvexWidgetView(model: Sample.openDayModel(.accessoryInline))
          }
        }
      case .more:
        group("Habits") {
          HStack(alignment: .top, spacing: 16) {
            cell("habits · small", 158, 158) {
              HabitsWidgetView(habits: Sample.habits, family: .systemSmall)
            }
            cell("habits · small · all done", 158, 158) {
              HabitsWidgetView(habits: Sample.allDoneHabits, family: .systemSmall)
            }
          }
          cell("habits · medium", 338, 158) {
            HabitsWidgetView(habits: Sample.habits, family: .systemMedium)
          }
          cell("habits · medium · overflow", 338, 158) {
            HabitsWidgetView(habits: Sample.habits + Sample.moreHabits, family: .systemMedium)
          }
        }
        group("Progress") {
          HStack(alignment: .top, spacing: 16) {
            cell("progress · small", 158, 158) {
              ProgressWidgetView(snapshot: Sample.progressSnapshot, family: .systemSmall)
            }
            cell("progress · small · done", 158, 158) {
              ProgressWidgetView(snapshot: Sample.finishedSnapshot, family: .systemSmall)
            }
          }
          HStack(alignment: .top, spacing: 16) {
            accessoryCell("progress · circular", 72, 72) {
              ProgressWidgetView(snapshot: Sample.progressSnapshot, family: .accessoryCircular)
            }
            accessoryCell("progress · inline", 200, 30) {
              ProgressWidgetView(snapshot: Sample.progressSnapshot, family: .accessoryInline)
            }
          }
        }
      }
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
        // The widget views draw inside WidgetKit's content margins and add
        // none of their own; 16pt is the system's margin on iPhone and iPad.
        content()
          .padding(16)
          .frame(width: width, height: height, alignment: .top)
          .background(LorvexDesign.Palette.card)
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
  }
#endif
