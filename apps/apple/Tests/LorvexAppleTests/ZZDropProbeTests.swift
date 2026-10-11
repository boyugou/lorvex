#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing
  import UniformTypeIdentifiers

  @testable import LorvexApple
  @testable import LorvexCore

  /// Scratch probe (git-excluded, skipped without `LORVEX_SCRATCH_DIR`): hosts the
  /// real sidebar in a window that is never shown and feeds it a synthetic task
  /// drop through the AppKit dragging-destination protocol.
  @MainActor
  struct ZZDropProbeTests {

    final class FakeDraggingInfo: NSObject, NSDraggingInfo {
      nonisolated(unsafe) static var calls: [String] = []
      let window: NSWindow
      let pasteboard: NSPasteboard
      var location: NSPoint

      init(window: NSWindow, pasteboard: NSPasteboard, location: NSPoint) {
        self.window = window
        self.pasteboard = pasteboard
        self.location = location
      }

      var draggingDestinationWindow: NSWindow? { Self.calls.append("draggingDestinationWindow"); return window }
      var draggingSourceOperationMask: NSDragOperation { Self.calls.append("draggingSourceOperationMask"); return [.copy, .move, .generic] }
      var draggingLocation: NSPoint { Self.calls.append("draggingLocation"); return location }
      var draggedImageLocation: NSPoint { Self.calls.append("draggedImageLocation"); return location }
      var draggedImage: NSImage? { Self.calls.append("draggedImage"); return nil }
      var draggingPasteboard: NSPasteboard { Self.calls.append("draggingPasteboard"); return pasteboard }
      var draggingSource: Any? { Self.calls.append("draggingSource"); return nil }
      var draggingSequenceNumber: Int { Self.calls.append("draggingSequenceNumber"); return 1 }
      var draggingFormation: NSDraggingFormation = .default
      var animatesToDestination: Bool = false
      var numberOfValidItemsForDrop: Int = 1 { didSet { Self.calls.append("set numberOfValidItemsForDrop=\(numberOfValidItemsForDrop)") } }
      var springLoadingHighlight: NSSpringLoadingHighlight { Self.calls.append("springLoadingHighlight"); return .none }
      func slideDraggedImage(to screenPoint: NSPoint) { Self.calls.append("slideDraggedImage") }
      func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
      ) {
        Self.calls.append("enumerateDraggingItems classes=\(classArray) options=\(enumOpts.rawValue) searchOptions=\(searchOptions.keys.map(\.rawValue))")
        var stop = ObjCBool(false)
        for (index, item) in (pasteboard.pasteboardItems ?? []).enumerated() {
          block(NSDraggingItem(pasteboardWriter: item), index, &stop)
          if stop.boolValue { break }
        }
      }
      func resetSpringLoading() { Self.calls.append("resetSpringLoading") }
    }

    private func collect(_ view: NSView, depth: Int, into out: inout [String]) {
      let types = view.registeredDraggedTypes.map(\.rawValue)
      if !types.isEmpty {
        out.append(
          "\(String(repeating: "  ", count: depth))\(type(of: view)) frame="
            + "\(view.convert(view.bounds, to: nil)) types=\(types)")
      }
      for sub in view.subviews { collect(sub, depth: depth + 1, into: &out) }
    }

    private func accessibilityRows(_ element: Any, window: NSWindow, depth: Int = 0) -> [String] {
      var lines: [String] = []
      guard depth < 40 else { return lines }
      let children: [Any]
      if let view = element as? NSView {
        children = view.accessibilityChildren() ?? []
      } else if let object = element as? NSAccessibilityElementProtocol & NSObjectProtocol,
        let accessible = object as? NSAccessibilityProtocol
      {
        children = accessible.accessibilityChildren() ?? []
        if let identifier = accessible.accessibilityIdentifier(), identifier.hasPrefix("sidebar.") {
          let screen = accessible.accessibilityFrame()
          let local = window.convertFromScreen(screen)
          lines.append("\(identifier) windowFrame=\(local)")
        }
      } else {
        children = []
      }
      for child in children { lines += accessibilityRows(child, window: window, depth: depth + 1) }
      return lines
    }

    @Test func sidebarAcceptsATaskDrop() async throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      var report: [String] = []

      let core = try await makeSeededInMemoryCore()
      let store = AppStore(
        core: core, taskSearchIndexer: NoopTaskSearchIndexer(),
        widgetSnapshotPublisher: NoopWidgetSnapshotPublisher())
      await store.refresh()

      let hosting = NSHostingView(rootView: SidebarView(store: store).frame(width: 260, height: 720))
      let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: -20_000, width: 260, height: 720),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      defer { window.contentView = nil }
      for _ in 0..<8 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
      }

      var registered: [String] = []
      collect(hosting, depth: 0, into: &registered)
      report.append("== views registered for dragged types (\(registered.count))")
      report += registered

      let taskType = UTType.lorvexTask
      report.append(
        "== type facts: declared=\(taskType.isDeclared) dynamic=\(taskType.isDynamic)"
          + " conformsToData=\(taskType.conforms(to: .data))"
          + " conformsToItem=\(taskType.conforms(to: .item))"
          + " supertypes=\(taskType.supertypes.map(\.identifier))")
      let checklistType = UTType.lorvexChecklistItem
      report.append(
        "== checklist type facts: declared=\(checklistType.isDeclared)"
          + " conformsToData=\(checklistType.conforms(to: .data))")

      let board = NSPasteboard(name: NSPasteboard.Name("lorvex.zzprobe.\(UUID().uuidString)"))
      board.clearContents()
      let ref = LorvexTaskRef(id: LorvexPreviewSeedID.venueTask, title: "Venue")
      board.setData(try JSONEncoder().encode(ref), forType: NSPasteboard.PasteboardType(UTType.lorvexTask.identifier))
      board.setString(ref.title, forType: .string)
      defer { board.releaseGlobally() }

      report.append(
        "== pasteboard facts: canReadItem(data)=\(board.canReadItem(withDataConformingToTypes: [UTType.data.identifier]))"
          + " canReadItem(item)=\(board.canReadItem(withDataConformingToTypes: [UTType.item.identifier]))"
          + " types=\(board.types?.map(\.rawValue) ?? [])")

      func destination(at windowPoint: NSPoint) -> NSView? {
        let hostPoint = hosting.convert(windowPoint, from: nil)
        var view = hosting.hitTest(hostPoint)
        while let candidate = view {
          let types = candidate.registeredDraggedTypes.map(\.rawValue)
          if types.contains(UTType.lorvexTask.identifier) { return candidate }
          view = candidate.superview
        }
        return nil
      }

      report.append("== entered sweep (x=130)")
      let height = hosting.bounds.height
      for y in stride(from: 8.0, to: Double(height), by: 14.0) {
        let hostPoint = NSPoint(x: 130, y: hosting.isFlipped ? y : Double(height) - y)
        let windowPoint = hosting.convert(hostPoint, to: nil)
        let info = FakeDraggingInfo(window: window, pasteboard: board, location: windowPoint)
        let hit = hosting.hitTest(hostPoint).map { "\(type(of: $0))" } ?? "nil"
        if let target = destination(at: windowPoint) {
          let operation = target.draggingEntered(info)
          target.draggingExited(info)
          report.append("y=\(Int(y)) hit=\(hit) dest=\(type(of: target)) op=\(operation.rawValue)")
        } else {
          report.append("y=\(Int(y)) hit=\(hit) dest=none")
        }
      }

      report.append("== direct entered on every destination view")
      var destinations: [NSView] = []
      func gather(_ view: NSView) {
        if String(describing: type(of: view)).contains("DraggingDestination") { destinations.append(view) }
        for sub in view.subviews { gather(sub) }
      }
      gather(hosting)
      for target in destinations {
        let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        let info = FakeDraggingInfo(window: window, pasteboard: board, location: center)
        let operation = target.draggingEntered(info)
        report.append("view frame=\(target.convert(target.bounds, to: nil)) entered op=\(operation.rawValue)")
        if operation != [] {
          let prepared = target.prepareForDragOperation(info)
          let performed = target.performDragOperation(info)
          target.concludeDragOperation(info)
          report.append("  prepare=\(prepared) perform=\(performed)")
        } else {
          target.draggingExited(info)
        }
      }
      var movedList: String? = "inbox"
      for _ in 0..<40 {
        try await Task.sleep(for: .milliseconds(100))
        movedList = try await core.loadTask(id: LorvexPreviewSeedID.venueTask).listID
        if movedList != "inbox" { break }
      }
      report.append("== venue task list after drops: \(movedList ?? "nil") errorMessage=\(store.errorMessage ?? "nil")")
      report.append("== sidebar lists: \(store.orderedLists.map { "\($0.id)=\($0.displayName)" })")
      report.append("== dragging-info calls (\(FakeDraggingInfo.calls.count)): \(FakeDraggingInfo.calls.joined(separator: " | "))")

      try report.joined(separator: "\n").write(
        toFile: scratch + "/drop-probe.txt", atomically: true, encoding: .utf8)
    }

    @Test func typeConformanceFacts() throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      var report: [String] = []
      let variants: [(String, UTType)] = [
        ("plain", UTType(exportedAs: "com.lorvex.apple.zzprobe.plain")),
        ("conformingTo data", UTType(exportedAs: "com.lorvex.apple.zzprobe.data", conformingTo: .data)),
      ]
      for (label, type) in variants {
        let board = NSPasteboard(name: NSPasteboard.Name("lorvex.zzprobe.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(Data("{}".utf8), forType: NSPasteboard.PasteboardType(type.identifier))
        let available = board.availableType(from: [
          NSPasteboard.PasteboardType("public.data"), NSPasteboard.PasteboardType("public.item"),
        ])
        report.append(
          "\(label): declared=\(type.isDeclared) dynamic=\(type.isDynamic)"
            + " conformsToData=\(type.conforms(to: .data))"
            + " supertypes=\(type.supertypes.map(\.identifier).sorted())"
            + " availableType(data,item)=\(available?.rawValue ?? "nil")"
            + " canReadItem(data)=\(board.canReadItem(withDataConformingToTypes: [UTType.data.identifier]))")
      }
      try report.joined(separator: "\n").write(
        toFile: scratch + "/type-facts.txt", atomically: true, encoding: .utf8)
    }

    // MARK: custom vs system content type

    struct ProbeCustomRef: Codable, Transferable {
      var id: String
      static let type = UTType(exportedAs: "com.lorvex.apple.zzprobe.custom")
      static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: type)
        ProxyRepresentation(exporting: \.id)
      }
    }

    struct ProbeSystemRef: Codable, Transferable {
      var id: String
      static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        ProxyRepresentation(exporting: \.id)
      }
    }

    struct ProbeDeclaredRef: Codable, Transferable {
      var id: String
      static let type = UTType(exportedAs: "com.lorvex.apple.zzprobe.declared")
      static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: type)
        ProxyRepresentation(exporting: \.id)
      }
    }

    final class Hits: @unchecked Sendable {
      var custom: [String] = []
      var system: [String] = []
      var declared: [String] = []
    }

    struct ProbeHost: View {
      let hits: Hits
      var body: some View {
        VStack(spacing: 20) {
          Color.red.frame(width: 200, height: 80)
            .dropDestination(for: ProbeCustomRef.self) { refs, _ in
              hits.custom += refs.map(\.id)
              return true
            }
          Color.blue.frame(width: 200, height: 80)
            .dropDestination(for: ProbeSystemRef.self) { refs, _ in
              hits.system += refs.map(\.id)
              return true
            }
          Color.green.frame(width: 200, height: 80)
            .dropDestination(for: ProbeDeclaredRef.self) { refs, _ in
              hits.declared += refs.map(\.id)
              return true
            }
        }
        .padding(20)
      }
    }

    @Test func customVersusSystemTypeDrop() async throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      var report: [String] = []
      let hits = Hits()
      let hosting = NSHostingView(rootView: ProbeHost(hits: hits).frame(width: 240, height: 360))
      let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: -20_000, width: 240, height: 360),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      defer { window.contentView = nil }
      for _ in 0..<6 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
      }

      var destinations: [NSView] = []
      func gather(_ view: NSView) {
        if String(describing: type(of: view)).contains("DraggingDestination"),
          !view.registeredDraggedTypes.isEmpty
        {
          destinations.append(view)
        }
        for sub in view.subviews { gather(sub) }
      }
      gather(hosting)
      report.append("destinations: \(destinations.map { "\($0.convert($0.bounds, to: nil)) \($0.registeredDraggedTypes.map(\.rawValue))" })")

      func drop(typeIdentifier: String, payload: Data, label: String) async throws {
        let board = NSPasteboard(name: NSPasteboard.Name("lorvex.zzprobe.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(payload, forType: NSPasteboard.PasteboardType(typeIdentifier))
        board.setString("text", forType: .string)
        for target in destinations {
          let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
          let info = FakeDraggingInfo(window: window, pasteboard: board, location: center)
          let operation = target.draggingEntered(info)
          var line = "\(label) frame=\(target.convert(target.bounds, to: nil)) entered=\(operation.rawValue)"
          if operation != [] {
            line += " prepare=\(target.prepareForDragOperation(info)) perform=\(target.performDragOperation(info))"
            target.concludeDragOperation(info)
          } else {
            target.draggingExited(info)
          }
          report.append(line)
        }
        try await Task.sleep(for: .milliseconds(1500))
      }

      let json = try JSONEncoder().encode(["id": "x"])
      try await drop(
        typeIdentifier: ProbeCustomRef.type.identifier, payload: json, label: "custom")
      report.append("hits after custom drop: custom=\(hits.custom) system=\(hits.system)")
      try await drop(typeIdentifier: UTType.json.identifier, payload: json, label: "system")
      report.append("hits after system drop: custom=\(hits.custom) system=\(hits.system)")
      let declaredType = ProbeDeclaredRef.type
      report.append(
        "declared type facts: declared=\(declaredType.isDeclared) dynamic=\(declaredType.isDynamic)"
          + " conformsToData=\(declaredType.conforms(to: .data)) supertypes=\(declaredType.supertypes.map(\.identifier).sorted())")
      try await drop(
        typeIdentifier: declaredType.identifier, payload: json, label: "declared")
      report.append("hits after declared drop: custom=\(hits.custom) system=\(hits.system) declared=\(hits.declared)")
      report.append("calls: \(FakeDraggingInfo.calls.count)")

      try report.joined(separator: "\n").write(
        toFile: scratch + "/custom-vs-system.txt", atomically: true, encoding: .utf8)
    }

    // MARK: visual QA of the drop affordances

    private func snapshot(_ hosting: NSView, to url: URL) throws {
      let size = hosting.bounds.size
      let rep = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      rep.size = size
      hosting.cacheDisplay(in: hosting.bounds, to: rep)
      try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    @Test func renderDropAffordances() async throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      let directory = URL(fileURLWithPath: scratch)

      // The drag image: one task, then a multi-task selection.
      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let view = VStack(alignment: .leading, spacing: 16) {
          TaskDragPreview(title: "面签材料", count: 1).fixedSize()
          TaskDragPreview(title: "Book the offsite venue", count: 3).fixedSize()
          TaskDragPreview(title: "A very long task title that has to be cut off before it runs across the window", count: 12).fixedSize()
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor))
        .fixedSize()
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(
          contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        try snapshot(hosting, to: directory.appendingPathComponent("drag-preview-\(label).png"))
        window.contentView = nil
      }

      // The real sidebar with a task drag over one row at a time.
      let core = try await makeSeededInMemoryCore()
      _ = try await core.createList(name: "Personal", description: nil)
      let store = AppStore(
        core: core, taskSearchIndexer: NoopTaskSearchIndexer(),
        widgetSnapshotPublisher: NoopWidgetSnapshotPublisher())
      await store.refresh()
      let board = NSPasteboard(name: NSPasteboard.Name("lorvex.zzprobe.\(UUID().uuidString)"))
      defer { board.releaseGlobally() }
      board.clearContents()
      board.setData(
        try JSONEncoder().encode(LorvexTaskRef(id: LorvexPreviewSeedID.venueTask, title: "Venue")),
        forType: NSPasteboard.PasteboardType(UTType.lorvexTask.identifier))

      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let hosting = NSHostingView(rootView: SidebarView(store: store).frame(width: 260, height: 520))
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
          contentRect: NSRect(x: -20_000, y: -20_000, width: 260, height: 520),
          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        for _ in 0..<8 {
          hosting.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(80))
        }
        var destinations: [NSView] = []
        func gather(_ view: NSView) {
          if String(describing: type(of: view)).contains("DraggingDestination"),
            !view.registeredDraggedTypes.isEmpty
          {
            destinations.append(view)
          }
          for sub in view.subviews { gather(sub) }
        }
        gather(hosting)
        // Top of the window first (AppKit's y axis points up).
        destinations.sort { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
        for (index, target) in destinations.enumerated() {
          let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
          let info = FakeDraggingInfo(window: window, pasteboard: board, location: center)
          _ = target.draggingEntered(info)
          for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
          }
          try snapshot(hosting, to: directory.appendingPathComponent("sidebar-drop-\(index)-\(label).png"))
          target.draggingExited(info)
          try await Task.sleep(for: .milliseconds(120))
        }
        window.contentView = nil
        try "\(destinations.count) destinations".write(
          to: directory.appendingPathComponent("sidebar-drop-count-\(label).txt"), atomically: true, encoding: .utf8)
      }
    }
  }
#endif
