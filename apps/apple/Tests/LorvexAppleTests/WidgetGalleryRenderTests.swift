#if os(macOS)
  import AppKit
  import Foundation
  import LorvexWidgetKitSupport
  import LorvexWidgetViews
  import SwiftUI
  import Testing

  /// Renders the widget views at the Mac desktop's widget sizes into contact
  /// sheets, one per widget group and appearance, for visual QA of the widget
  /// design. Runs only when `LORVEX_WIDGET_GALLERY_DIR` names the output
  /// directory:
  ///
  ///     LORVEX_WIDGET_GALLERY_DIR=/path/to/dir swift test --filter WidgetGalleryRender
  ///
  /// Each sheet is hosted in a borderless window that is never ordered front
  /// and drawn at 2x. A widget draws inside the content margins WidgetKit gives
  /// a desktop widget, over the `.background` style its container uses.
  @Suite(.enabled(if: WidgetGallerySheet.outputDirectory != nil))
  @MainActor
  struct WidgetGalleryRenderTests {
    private typealias Sample = WidgetGallerySample

    @Test
    func rendersTodaySheet() async throws {
      let sheet = WidgetGallerySheet {
        WidgetGallerySheet.row {
          WidgetGallerySheet.cell("small · running", .small) {
            LorvexWidgetView(model: Sample.model(.systemSmall))
          }
          WidgetGallerySheet.cell("small · next", .small) {
            LorvexWidgetView(model: Sample.model(.systemSmall, at: Sample.earlyClock))
          }
          WidgetGallerySheet.cell("small · open day", .small) {
            LorvexWidgetView(model: Sample.openDayModel(.systemSmall))
          }
          WidgetGallerySheet.cell("small · all done", .small) {
            LorvexWidgetView(model: Sample.emptyModel(.systemSmall))
          }
        }
        WidgetGallerySheet.row {
          WidgetGallerySheet.cell("medium · running", .medium) {
            LorvexWidgetView(model: Sample.model(.systemMedium))
          }
          WidgetGallerySheet.cell("medium · open day", .medium) {
            LorvexWidgetView(model: Sample.openDayModel(.systemMedium))
          }
        }
        WidgetGallerySheet.row {
          WidgetGallerySheet.cell("large · running", .large) {
            LorvexWidgetView(model: Sample.model(.systemLarge))
          }
          WidgetGallerySheet.cell("large · open day", .large) {
            LorvexWidgetView(model: Sample.openDayModel(.systemLarge))
          }
        }
      }
      try await sheet.render(named: "today")
    }

    @Test
    func rendersHabitsAndProgressSheet() async throws {
      let sheet = WidgetGallerySheet {
        WidgetGallerySheet.row {
          WidgetGallerySheet.cell("habits · small", .small) {
            HabitsWidgetView(habits: Sample.habits, family: .systemSmall)
          }
          WidgetGallerySheet.cell("habits · small · all done", .small) {
            HabitsWidgetView(habits: Sample.allDoneHabits, family: .systemSmall)
          }
          WidgetGallerySheet.cell("habits · medium", .medium) {
            HabitsWidgetView(habits: Sample.habits, family: .systemMedium)
          }
        }
        WidgetGallerySheet.row {
          WidgetGallerySheet.cell("habits · medium · overflow", .medium) {
            HabitsWidgetView(habits: Sample.habits + Sample.moreHabits, family: .systemMedium)
          }
          WidgetGallerySheet.cell("progress · small", .small) {
            ProgressWidgetView(snapshot: Sample.progressSnapshot, family: .systemSmall)
          }
          WidgetGallerySheet.cell("progress · small · done", .small) {
            ProgressWidgetView(snapshot: Sample.finishedSnapshot, family: .systemSmall)
          }
        }
        WidgetGallerySheet.row {
          WidgetGallerySheet.cell("habits · small · none", .small) {
            HabitsWidgetView(habits: [], family: .systemSmall)
          }
          WidgetGallerySheet.cell("progress · small · empty day", .small) {
            ProgressWidgetView(
              snapshot: WidgetSnapshot(
                generatedAt: "2026-06-30T12:00:00Z", timezone: "UTC",
                stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0, completedTodayCount: 0),
                briefing: nil, tasks: []),
              family: .systemSmall)
          }
          WidgetGallerySheet.cell("habits · small · stale", .small) {
            HabitsWidgetView(habits: Sample.habits, family: .systemSmall, staleAgeLabel: "2h")
          }
          WidgetGallerySheet.cell("progress · small · stale", .small) {
            ProgressWidgetView(snapshot: Sample.progressSnapshot, family: .systemSmall, staleAgeLabel: "2h")
          }
        }
      }
      try await sheet.render(named: "habits-progress")
    }
  }

  /// A contact sheet of widgets at the Mac desktop's sizes, rendered in light
  /// and dark to `<LORVEX_WIDGET_GALLERY_DIR>/<name>-<appearance>.png`.
  @MainActor
  struct WidgetGallerySheet {
    nonisolated static var outputDirectory: URL? {
      ProcessInfo.processInfo.environment["LORVEX_WIDGET_GALLERY_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
      }
    }

    /// The Mac desktop's widget sizes: a small widget is 170pt square, and
    /// medium and large span two of them and the 18pt gap between.
    enum Size {
      case small, medium, large

      var points: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 358, height: 170)
        case .large: CGSize(width: 358, height: 358)
        }
      }
    }

    /// WidgetKit's content margin around a desktop widget's view.
    static let contentMargin: CGFloat = 16

    private let content: AnyView

    init(@ViewBuilder _ content: () -> some View) {
      self.content = AnyView(VStack(alignment: .leading, spacing: 22) { content() })
    }

    static func row(@ViewBuilder _ content: () -> some View) -> some View {
      HStack(alignment: .top, spacing: 18) { content() }
    }

    static func cell(_ title: String, _ size: Size, @ViewBuilder _ content: () -> some View) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
        content()
          .padding(contentMargin)
          .frame(width: size.points.width, height: size.points.height, alignment: .top)
          .background(.background)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
      }
    }

    func render(named name: String) async throws {
      let directory = try #require(Self.outputDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let png = try await draw(appearance: appearance)
        try png.write(to: directory.appendingPathComponent("\(name)-\(label).png"))
      }
    }

    /// Lays the sheet out in a window that is never ordered front, lets
    /// SwiftUI commit, and draws the hosting view into a 2x bitmap.
    private func draw(appearance: NSAppearance.Name) async throws -> Data {
      let hosting = NSHostingView(
        rootView: content
          .padding(24)
          .background(Color(nsColor: .underPageBackgroundColor))
          .fixedSize())
      hosting.appearance = NSAppearance(named: appearance)
      let size = hosting.fittingSize
      let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: appearance)
      window.contentView = hosting
      hosting.frame = NSRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(250))
      hosting.layoutSubtreeIfNeeded()

      let rep = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      rep.size = size
      hosting.cacheDisplay(in: hosting.bounds, to: rep)
      window.contentView = nil
      return try #require(rep.representation(using: .png, properties: [:]))
    }
  }
#endif
