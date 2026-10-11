#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import LorvexApple

  // Throwaway visual QA harness; not committed.
  @Suite(.enabled(if: ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] != nil))
  @MainActor
  struct ZZTimeChipRenderProbeTests {
    @Test func dayHoursPopovers() async throws {
      let calendar = Calendar.current
      let today = calendar.startOfDay(for: Date())
      func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
      }
      // Start chip while the window ends at 15:00: up to 14:59 is allowed.
      try await render(
        LorvexTimeChipPopover(
          date: at(9, 0), allowedRange: at(0, 0)...at(15, 0).addingTimeInterval(-60), onSet: { _ in }),
        named: "timechip-start")
      // End chip while the window starts at 08:00: from 08:01 on is allowed.
      try await render(
        LorvexTimeChipPopover(
          date: at(8, 30), allowedRange: at(8, 0).addingTimeInterval(60)...at(23, 59), onSet: { _ in }),
        named: "timechip-end")
      try await render(LorvexTimeChipPopover(date: at(9, 0), onSet: { _ in }), named: "timechip-free")
    }

    func render(_ content: some View, named name: String) async throws {
      let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"]))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let hosting = NSHostingView(
          rootView: content.padding(24).background(Color(nsColor: .underPageBackgroundColor)).fixedSize())
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
