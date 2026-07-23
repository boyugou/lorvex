#if DEBUG
  import AppKit
  import LorvexCore
  import SwiftUI

  /// DEBUG-only macOS design verifier. The macOS app runs on the host (no
  /// simulator to screenshot), so this renders the desktop design *components*
  /// to a PNG with `ImageRenderer` and exits — `swift run LorvexApple
  /// --dump-snapshots <dir>`.
  ///
  /// It renders the reusable atoms (task row, metric card, habit ring, icon tile,
  /// empty-state panel) rather than whole workspaces: `List`/`Table` containers
  /// render as the SwiftUI unsupported-view placeholder under `ImageRenderer`, but
  /// the components that carry the actual design are plain SwiftUI and render fully.
  ///
  /// Runs at the very top of `LorvexAppleApp.init()`, before the CloudKit-touching
  /// bootstrap, against an in-memory core — so it never hits the unentitled
  /// CKContainer trap that blocks the test host. Compiled out of release builds.
  enum LorvexAppleSnapshotDump {
    static func runIfRequested() {
      let args = CommandLine.arguments
      guard let index = args.firstIndex(of: "--dump-snapshots"), index + 1 < args.count else {
        return
      }
      let dir = args[index + 1]
      Task { @MainActor in
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let core = try? await LorvexPreviewCoreFactory.makeSeeded() else {
          FileHandle.standardError.write(Data("dump: failed to seed the in-memory core\n".utf8))
          exit(1)
        }
        let store = AppStore(core: core)
        await store.refresh()
        write(componentGallery(tasks: store.today.tasks), "macos-components",
          CGSize(width: 700, height: 860), dir)
        LorvexMilestoneSnapshotDump.dump(to: dir)
        exit(0)
      }
      // Pump the main runloop so the @MainActor task can run to its exit(0); a
      // semaphore wait would deadlock the main actor.
      RunLoop.main.run()
    }

    @MainActor @ViewBuilder
    private static func componentGallery(tasks: [LorvexTask]) -> some View {
      VStack(alignment: .leading, spacing: 18) {
        Text("Lorvex — macOS design components").font(.title3.weight(.semibold))

        VStack(spacing: 0) {
          if let task = tasks.first {
            LorvexTaskRow(task: task, isFocused: true)
            Divider()
          }
          if let task = tasks.dropFirst().first { LorvexTaskRow(task: task) }
        }
        .padding(12)
        .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: 12))

        HStack(spacing: 16) {
          ReviewMetricCard(
            title: "Open", metricKey: "open", value: tasks.count, systemImage: "checklist",
            tint: .blue)
          ReviewMetricCard(
            title: "In Focus", metricKey: "focus", value: 2, systemImage: "scope", tint: .indigo)
        }

        HStack(spacing: 22) {
          HabitProgressRing(completed: 1, target: 1, tint: .green, icon: "figure.run") {}
          HabitProgressRing(completed: 0, target: 1, tint: .orange, icon: "book.fill") {}
          LorvexListIconView(icon: "briefcase.fill", tint: .blue, size: 30, font: .body)
          LorvexListIconView(icon: "house.fill", tint: .green, size: 30, font: .body)
          LorvexListIconView(icon: "book.fill", tint: .purple, size: 30, font: .body)
        }

        LorvexEmptyStatePanel(
          title: "No Open Tasks",
          message: "Capture a task to get started — or ask your AI assistant to plan your day.",
          systemImage: "checkmark.circle", tint: .green, style: .inline, chips: []
        ) { EmptyView() }
      }
      .padding(24)
      .frame(width: 700, alignment: .leading)
      .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    static func write<V: View>(_ view: V, _ name: String, _ size: CGSize, _ dir: String) {
      let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
      renderer.scale = 2
      guard let nsImage = renderer.nsImage,
        let tiff = nsImage.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
      else {
        FileHandle.standardError.write(Data("dump: failed to render \(name)\n".utf8))
        return
      }
      try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
      FileHandle.standardError.write(Data("dump: wrote \(name).png\n".utf8))
    }
  }
#endif
