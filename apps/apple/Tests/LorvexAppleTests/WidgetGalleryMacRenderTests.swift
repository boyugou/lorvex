#if os(macOS)
  import AppKit
  import LorvexCore
  import LorvexWidgetKitSupport
  import LorvexWidgetViews
  import SwiftUI
  import Testing

  /// Renders the widget gallery at the Mac desktop's widget sizes into PNG
  /// files, for visual QA of the widgets as macOS sets them. macOS text styles
  /// are smaller than iOS's (its caption, caption2, and footnote are all 10
  /// points), so the iPhone gallery (`ios_sim_screenshots.sh widgets…`) does
  /// not show how the Mac widgets read.
  ///
  /// Runs only when `LORVEX_WIDGET_GALLERY_DIR` names the output directory, as
  /// `script/widget_gallery_macos.sh` sets it. Each section is one image per
  /// appearance, `<section>-light.png` and `<section>-dark.png`, drawn at twice
  /// the point size in a borderless window far off screen that is never shown.
  /// The content is ``WidgetGallerySample``'s sample day, read through the real
  /// render model builder. WidgetKit's own drawing is not reproduced: a view
  /// WidgetKit cannot draw (an AppKit control) still renders here.
  @Suite(.enabled(if: ProcessInfo.processInfo.environment["LORVEX_WIDGET_GALLERY_DIR"] != nil))
  @MainActor
  struct WidgetGalleryMacRenderTests {
    private typealias Sample = WidgetGallerySample

    /// The Mac desktop's widget grid: 162-point tiles with 18-point gaps, so
    /// a medium is two tiles wide and a large two tiles high.
    private static let small = CGSize(width: 162, height: 162)
    private static let medium = CGSize(width: 342, height: 162)
    private static let large = CGSize(width: 342, height: 342)

    @Test func renderGallery() async throws {
      let directory = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LORVEX_WIDGET_GALLERY_DIR"]))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (name, page) in pages {
        try await render(page, named: name, into: directory)
      }
    }

    private var pages: [(String, AnyView)] {
      [
        (
          "today",
          AnyView(
            VStack(alignment: .leading, spacing: 18) {
              HStack(alignment: .top, spacing: 18) {
                cell("running", Self.small) { LorvexWidgetView(model: Sample.model(.systemSmall)) }
                cell("next", Self.small) {
                  LorvexWidgetView(model: Sample.model(.systemSmall, at: Sample.earlyClock))
                }
                cell("open day", Self.small) { LorvexWidgetView(model: Sample.openDayModel(.systemSmall)) }
                cell("all done", Self.small) { LorvexWidgetView(model: Sample.emptyModel(.systemSmall)) }
              }
              HStack(alignment: .top, spacing: 18) {
                cell("medium", Self.medium) { LorvexWidgetView(model: Sample.model(.systemMedium)) }
                cell("medium · open day", Self.medium) {
                  LorvexWidgetView(model: Sample.openDayModel(.systemMedium))
                }
              }
            })
        ),
        (
          "large",
          AnyView(
            HStack(alignment: .top, spacing: 18) {
              cell("large", Self.large) { LorvexWidgetView(model: Sample.model(.systemLarge)) }
              cell("large · open day", Self.large) {
                LorvexWidgetView(model: Sample.openDayModel(.systemLarge))
              }
            })
        ),
        (
          "habits-progress",
          AnyView(
            VStack(alignment: .leading, spacing: 18) {
              HStack(alignment: .top, spacing: 18) {
                cell("habits", Self.small) { HabitsWidgetView(habits: Sample.habits, family: .systemSmall) }
                cell("habits · all done", Self.small) {
                  HabitsWidgetView(habits: Sample.allDoneHabits, family: .systemSmall)
                }
                cell("progress", Self.small) {
                  ProgressWidgetView(snapshot: Sample.progressSnapshot, family: .systemSmall)
                }
                cell("progress · done", Self.small) {
                  ProgressWidgetView(snapshot: Sample.finishedSnapshot, family: .systemSmall)
                }
              }
              HStack(alignment: .top, spacing: 18) {
                cell("habits · medium", Self.medium) {
                  HabitsWidgetView(habits: Sample.habits, family: .systemMedium)
                }
                cell("habits · medium · overflow", Self.medium) {
                  HabitsWidgetView(habits: Sample.habits + Sample.moreHabits, family: .systemMedium)
                }
              }
            })
        ),
      ]
    }

    /// One widget at `size` under its caption, inside the 16-point content
    /// margins WidgetKit gives a Mac desktop widget, on the widget's backing.
    private func cell(
      _ title: String, _ size: CGSize, @ViewBuilder _ content: () -> some View
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        content()
          .padding(16)
          .frame(width: size.width, height: size.height, alignment: .top)
          .background(.background)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
      }
    }

    private func render(_ page: AnyView, named name: String, into directory: URL) async throws {
      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let hosting = NSHostingView(
          rootView: page.padding(24).background(Color(nsColor: .underPageBackgroundColor)).fixedSize())
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
        // Lets the hosting view finish its first layout pass and resolve the
        // appearance before it is drawn into the bitmap.
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(
          NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.contentView = nil
        try #require(rep.representation(using: .png, properties: [:]))
          .write(to: directory.appendingPathComponent("\(name)-\(label).png"))
      }
    }
  }
#endif
