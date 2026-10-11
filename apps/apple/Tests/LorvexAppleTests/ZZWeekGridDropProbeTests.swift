#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing
  import UniformTypeIdentifiers

  @testable import LorvexApple
  @testable import LorvexCore

  /// Scratch probe (git-excluded, skipped without `LORVEX_SCRATCH_DIR`): hosts the
  /// real week grid in a window that is never shown and feeds it synthetic task
  /// drops through the AppKit dragging-destination protocol, then reads the plan
  /// the store wrote.
  @MainActor
  struct ZZWeekGridDropProbeTests {

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

    @Test func weekGridPlansADroppedTask() async throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      var report: [String] = []
      let directory = URL(fileURLWithPath: scratch)

      let core = try await makeSeededInMemoryCore()
      let calendar = CalendarEventTiming.deviceCalendar
      let today = calendar.startOfDay(for: Date())
      func key(_ offset: Int) -> String {
        LorvexDateFormatters.ymd.string(
          from: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
      }
      let task = try await core.createTask(title: "Write the launch note", notes: "")
      _ = try await core.createCalendarEvent(
        title: "Standup", startDate: key(2), endDate: nil, startTime: "09:00", endTime: "09:30",
        allDay: false, location: nil, notes: nil)
      let store = AppStore(
        core: core, taskSearchIndexer: NoopTaskSearchIndexer(),
        widgetSnapshotPublisher: NoopWidgetSnapshotPublisher())
      await store.refresh()

      let weekStart = calendar.date(byAdding: .day, value: -1, to: today) ?? today
      let grid = CalendarWeekGridView(
        store: store, weekStart: weekStart, selectEvent: { _ in }, openTask: { _ in },
        createAt: { _, _, _ in }
      )
      .frame(width: 1100, height: 700)
      let hosting = NSHostingView(rootView: grid)
      let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: -20_000, width: 1100, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      defer { window.contentView = nil }
      for _ in 0..<10 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
      }

      let hourHeight = CalendarWeekGridMetrics.hourHeight
      try snapshot(hosting, to: directory.appendingPathComponent("weekgrid-initial.png"))
      var registeredAny: [String] = []
      func gatherAll(_ view: NSView, depth: Int) {
        let types = view.registeredDraggedTypes.map(\.rawValue)
        if !types.isEmpty {
          registeredAny.append(
            "\(String(repeating: "  ", count: depth))\(type(of: view)) frame=\(view.convert(view.bounds, to: nil)) types=\(types)"
          )
        }
        for sub in view.subviews { gatherAll(sub, depth: depth + 1) }
      }
      gatherAll(hosting, depth: 0)
      report.append("views with registered drag types: \(registeredAny.count)")
      report += registeredAny
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
      report.append(
        "type facts: declared=\(UTType.lorvexTask.isDeclared) conformsToData=\(UTType.lorvexTask.conforms(to: .data))"
      )
      report.append("hourHeight=\(hourHeight) destinations=\(destinations.count)")
      for view in destinations {
        report.append(
          "  frame=\(view.convert(view.bounds, to: nil)) flipped=\(view.isFlipped)")
      }

      let board = NSPasteboard(name: NSPasteboard.Name("lorvex.zzprobe.\(UUID().uuidString)"))
      defer { board.releaseGlobally() }
      board.clearContents()
      board.setData(
        try JSONEncoder().encode(LorvexTaskRef(id: task.id, title: task.title)),
        forType: NSPasteboard.PasteboardType(UTType.lorvexTask.identifier))
      board.setString(task.title, forType: .string)

      func plan() async throws -> String {
        let loaded = try await core.loadTask(id: task.id)
        let day = loaded.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "none"
        return "day=\(day) time=\(loaded.plannedTime.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "none")"
      }
      report.append("before: \(try await plan())  (tomorrow=\(key(2)))")

      // Time-axis destinations are the full-day-tall ones; the all-day strips
      // are the short ones.
      let tall = destinations.filter {
        $0.convert($0.bounds, to: nil).height >= 24 * hourHeight - 1
      }.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
      let short = destinations.filter {
        $0.convert($0.bounds, to: nil).height < 24 * hourHeight - 1
      }.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
      report.append("time axes=\(tall.count) all-day strips=\(short.count)")

      if tall.count > 2 {
        let target = tall[2]
        let minute = 10 * 60 + 7
        let y = CGFloat(minute) / 60 * hourHeight
        let local = NSPoint(
          x: target.bounds.midX, y: target.isFlipped ? y : target.bounds.height - y)
        let info = ZZDropProbeTests.FakeDraggingInfo(
          window: window, pasteboard: board, location: target.convert(local, to: nil))
        let entered = target.draggingEntered(info)
        let updated = target.draggingUpdated(info)
        report.append("time axis 10:07: entered=\(entered.rawValue) updated=\(updated.rawValue)")
        for _ in 0..<4 {
          hosting.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(120))
        }
        try snapshot(hosting, to: directory.appendingPathComponent("weekgrid-drop-hover.png"))
        let prepared = target.prepareForDragOperation(info)
        let performed = target.performDragOperation(info)
        target.concludeDragOperation(info)
        report.append("  prepare=\(prepared) perform=\(performed)")
        for _ in 0..<40 {
          try await Task.sleep(for: .milliseconds(100))
          if try await plan().contains("time=none") == false { break }
        }
        report.append("after time-axis drop: \(try await plan()) error=\(store.errorMessage ?? "nil")")
        for _ in 0..<4 {
          hosting.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(120))
        }
        try snapshot(hosting, to: directory.appendingPathComponent("weekgrid-drop-after.png"))
      }

      if short.count > 3 {
        let target = short[3]
        let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        let info = ZZDropProbeTests.FakeDraggingInfo(
          window: window, pasteboard: board, location: center)
        let entered = target.draggingEntered(info)
        report.append("all-day strip (day index 3): entered=\(entered.rawValue)")
        _ = target.prepareForDragOperation(info)
        let performed = target.performDragOperation(info)
        target.concludeDragOperation(info)
        report.append("  perform=\(performed)")
        for _ in 0..<40 {
          try await Task.sleep(for: .milliseconds(100))
          if try await plan().contains("day=\(key(3))") { break }
        }
        report.append(
          "after all-day drop: \(try await plan()) (day index 3=\(key(3))) error=\(store.errorMessage ?? "nil")"
        )
      }

      try report.joined(separator: "\n").write(
        to: directory.appendingPathComponent("weekgrid-drop-probe.txt"), atomically: true,
        encoding: .utf8)
    }

    @Test func monthGridKeepsATasksTimeWhenDroppedOnAnotherDay() async throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      var report: [String] = []
      let directory = URL(fileURLWithPath: scratch)
      let core = try await makeSeededInMemoryCore()
      let calendar = CalendarEventTiming.deviceCalendar
      let today = calendar.startOfDay(for: Date())
      let task = try await core.createTask(title: "Prep the standup", notes: "")
      _ = try await core.updateTask(
        TaskUpdateDraft(
          id: task.id, plannedDate: .set(PlannedDayBridge.storageDate(forLocalInstant: today)),
          plannedTime: .set(9 * 60..<9 * 60 + 45)))
      let store = AppStore(
        core: core, taskSearchIndexer: NoopTaskSearchIndexer(),
        widgetSnapshotPublisher: NoopWidgetSnapshotPublisher())
      await store.refresh()

      let monthAnchor = CalendarPresentationMode.month.periodStart(containing: today, calendar: calendar)
      let days = CalendarMonthGridModel.buildDays(
        monthAnchor: monthAnchor, calendar: calendar, events: [], tasks: [],
        dayKeyFor: { AppStore.ymdFormatter.string(from: $0) })
      let grid = CalendarMonthGridView(
        store: store, monthAnchor: monthAnchor, selectEvent: { _ in }, editEvent: { _ in },
        requestDeleteEvent: { _ in }, openTask: { _ in }, openDay: { _ in },
        createEvent: { _ in }
      )
      .frame(width: 1100, height: 700)
      let hosting = NSHostingView(rootView: grid)
      let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: -20_000, width: 1100, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      defer { window.contentView = nil }
      for _ in 0..<10 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
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
      // Top row first, left to right (AppKit's y axis points up).
      destinations.sort {
        let a = $0.convert($0.bounds, to: nil)
        let b = $1.convert($1.bounds, to: nil)
        return a.minY == b.minY ? a.minX < b.minX : a.minY > b.minY
      }
      report.append("month destinations=\(destinations.count) days=\(days.count)")
      let board = NSPasteboard(name: NSPasteboard.Name("lorvex.zzprobe.\(UUID().uuidString)"))
      defer { board.releaseGlobally() }
      board.clearContents()
      board.setData(
        try JSONEncoder().encode(LorvexTaskRef(id: task.id, title: task.title)),
        forType: NSPasteboard.PasteboardType(UTType.lorvexTask.identifier))

      let index = min(20, destinations.count - 1)
      let target = destinations[index]
      let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
      let info = ZZDropProbeTests.FakeDraggingInfo(window: window, pasteboard: board, location: center)
      let entered = target.draggingEntered(info)
      for _ in 0..<3 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
      }
      try snapshot(hosting, to: directory.appendingPathComponent("month-drop-hover.png"))
      _ = target.prepareForDragOperation(info)
      let performed = target.performDragOperation(info)
      target.concludeDragOperation(info)
      report.append("entered=\(entered.rawValue) perform=\(performed) target cell day=\(days[index].dayKey)")
      var loaded = try await core.loadTask(id: task.id)
      for _ in 0..<40 {
        try await Task.sleep(for: .milliseconds(100))
        loaded = try await core.loadTask(id: task.id)
        if loaded.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == days[index].dayKey { break }
      }
      report.append(
        "after: day=\(loaded.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "none") time=\(loaded.plannedTime.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "none") error=\(store.errorMessage ?? "nil")"
      )
      try report.joined(separator: "\n").write(
        to: directory.appendingPathComponent("month-drop-probe.txt"), atomically: true, encoding: .utf8)
    }

    @Test func calendarWorkspaceWithTheRail() async throws {
      guard let scratch = ProcessInfo.processInfo.environment["LORVEX_SCRATCH_DIR"] else { return }
      let directory = URL(fileURLWithPath: scratch)
      let key = "calendar.workspace.planRail"
      UserDefaults.standard.set(true, forKey: key)
      defer { UserDefaults.standard.removeObject(forKey: key) }
      let core = try await makeSeededInMemoryCore()
      _ = try await core.createTask(title: "Renew the car registration", notes: "")
      _ = try await core.createTask(title: "Reply to Maya about the catering quote", notes: "")
      let store = AppStore(
        core: core, taskSearchIndexer: NoopTaskSearchIndexer(),
        widgetSnapshotPublisher: NoopWidgetSnapshotPublisher())
      await store.refresh()
      for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let hosting = NSHostingView(rootView: CalendarWorkspaceView(store: store).frame(width: 1300, height: 760))
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
          contentRect: NSRect(x: -20_000, y: -20_000, width: 1300, height: 760),
          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        for _ in 0..<12 {
          hosting.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(100))
        }
        try snapshot(hosting, to: directory.appendingPathComponent("workspace-rail-\(label).png"))
        window.contentView = nil
      }
    }
  }
#endif
