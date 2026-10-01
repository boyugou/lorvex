#if DEBUG
  import AppKit
  import LorvexCore
  import SwiftUI

  /// DEBUG-only `--ui-preview` mode. Runs the *real* macOS windows (sidebar,
  /// task queue, calendar, detail panes) against a seeded real in-memory core with
  /// CloudKit and EventKit off, so the workspaces can be screenshotted headlessly
  /// (`ImageRenderer`/`--dump-snapshots` only renders the design atoms — `List`
  /// and `Table` containers collapse to placeholders).
  ///
  /// `swift run LorvexApple --ui-preview` (then `screencapture` the window).
  enum LorvexUIPreview {
    static var isActive: Bool {
      CommandLine.arguments.contains("--ui-preview")
    }

    /// `-uiPreviewAppearance dark|light` selects the app's own Appearance
    /// setting for the preview run, so both modes can be captured without
    /// touching the system setting. It goes through the setting because the
    /// main window applies that setting to `NSApp.appearance` on appear.
    static var forcedAppearance: AppAppearance? {
      let arguments = CommandLine.arguments
      guard let index = arguments.firstIndex(of: "-uiPreviewAppearance"),
        index + 1 < arguments.count
      else { return nil }
      switch arguments[index + 1] {
      case "dark": return .dark
      case "light": return .light
      default: return nil
      }
    }

    /// `-uiPreviewTour` walks every workspace after launch and prints one marker
    /// line per stop, so a shell loop can `screencapture -l <window>` each one:
    /// `LORVEX_UI_PREVIEW_WINDOW=<number>` once the window is up, then
    /// `LORVEX_UI_PREVIEW_STOP=<name>` after each workspace has settled, then
    /// `LORVEX_UI_PREVIEW_TOUR_DONE`. The preview never activates the app, so the
    /// tour runs behind whatever the user is doing.
    static var toursWorkspaces: Bool {
      CommandLine.arguments.contains("-uiPreviewTour")
    }

    /// `-uiPreviewAckDir <dir>` makes every tour stop a handshake: after
    /// printing a stop's marker the tour holds that workspace on screen until
    /// the capture driver creates `<dir>/<stop>.ack`. Without the handshake the
    /// tour advances on a fixed delay while the driver may still be shooting,
    /// so a settle loop that outlasts the delay photographs the *next*
    /// workspace and saves it under this stop's name — a PNG whose contents
    /// contradict its file name, which is invisible when captures are reviewed
    /// one at a time. A stop nobody acknowledges falls through after
    /// ``captureAckTimeout``, so a bare
    /// `swift run LorvexApple --ui-preview -uiPreviewTour` still completes.
    static var captureAckDirectory: URL? {
      let arguments = CommandLine.arguments
      guard let index = arguments.firstIndex(of: "-uiPreviewAckDir"),
        index + 1 < arguments.count
      else { return nil }
      return URL(fileURLWithPath: arguments[index + 1])
    }

    /// How long a stop waits to be acknowledged before it gives up on the
    /// driver and advances anyway.
    private static let captureAckTimeout = Duration.seconds(30)

    /// The preview's own defaults, wiped on each launch. Both the settings
    /// store and the tour window's `@AppStorage` read them, so a preview run
    /// neither reads nor writes the developer's defaults and never inherits
    /// view state — an expanded section, a table-mode toggle — from an earlier
    /// run.
    static let previewDefaultsSuiteName = "com.lorvex.apple.ui-preview"

    static var previewDefaults: UserDefaults {
      UserDefaults(suiteName: previewDefaultsSuiteName) ?? .standard
    }

    /// Selection is changed only after launch: setting `store.selection` during
    /// `init` (even to its current value) fires the didSet and stops the
    /// WindowGroup window from opening.
    /// The tour hosts the main window view in its own `NSWindow` rather than
    /// relying on the `Window` scene: SwiftUI opens that scene's window only
    /// when the app activates, and the whole point of the tour is to render
    /// without ever taking focus from the user.
    @MainActor
    static func runTourIfRequested(store: AppStore, settings: AppSettingsStore) {
      guard toursWorkspaces else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        let window = makeTourWindow(store: store, settings: settings)
        window.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(3))
        emit("LORVEX_UI_PREVIEW_WINDOW=\(window.windowNumber)")
        for selection in SidebarSelection.allCases {
          // Review reads its opening mode from the preview defaults when it
          // is created: the week digest is captured first, then the workspace
          // is re-created on the day page, its default, for the plain stop.
          if selection == .reviews {
            previewDefaults.set(ReviewMode.weekly.rawValue, forKey: "review.workspace.mode")
          }
          store.selection = selection
          store.selectedTaskID = nil
          try? await Task.sleep(for: .seconds(2.5))
          if selection == .reviews {
            await emitStop("reviews-weekly")
            previewDefaults.set(ReviewMode.daily.rawValue, forKey: "review.workspace.mode")
            store.selection = .today
            try? await Task.sleep(for: .seconds(0.5))
            store.selection = .reviews
            try? await Task.sleep(for: .seconds(2.5))
          }
          await emitStop(selection.rawValue)
          if selection == .today {
            // Times suggested at the pinned clock, so the capture shows the
            // suggestion starting from "now" rather than from the morning.
            await store.suggestDayTimes()
            try? await Task.sleep(for: .seconds(2))
            await emitStop("today-suggestion")
            store.dismissSuggestedDayTimes()
            try? await Task.sleep(for: .seconds(0.5))
          }
          if selection == .tasks, let first = store.today.tasks.first {
            store.selectedTaskID = first.id
            try? await Task.sleep(for: .seconds(2.5))
            await emitStop("tasks-inspector")
            store.selectedTaskID = nil
          }
          if selection == .tasks, let list = store.lists?.lists.first(where: { !$0.isInbox }) {
            // The same workspace scoped to a list, as the sidebar opens it.
            store.setTaskWorkspaceListScope(list.id)
            try? await Task.sleep(for: .seconds(2.5))
            await emitStop("tasks-list")
            store.setTaskWorkspaceListScope(nil)
          }
          if selection == .calendar {
            // The workspace reads its persisted presentation from the preview
            // defaults when it is created, so each grid is shown by setting
            // the key and re-creating the workspace; the week, its default,
            // is restored afterwards.
            for mode in [CalendarPresentationMode.day, .month] {
              store.selection = .today
              previewDefaults.set(mode.rawValue, forKey: "calendar.workspace.mode")
              try? await Task.sleep(for: .seconds(0.5))
              store.selection = .calendar
              try? await Task.sleep(for: .seconds(2.5))
              await emitStop("calendar-\(mode.rawValue)")
            }
            previewDefaults.set(CalendarPresentationMode.week.rawValue, forKey: "calendar.workspace.mode")
          }
          if selection == .habits, let first = store.habits?.habits.first {
            store.selectedHabitID = first.id
            try? await Task.sleep(for: .seconds(2.5))
            await emitStop("habits-inspector")
            store.selectedHabitID = nil
          }
        }
        // Settings is its own window, and its view reads the category it
        // opens on once, from the preview defaults: each category gets a
        // fresh window, announced before its stop so the driver shoots it.
        store.selection = .today
        for category in SettingsCategory.allCases {
          previewDefaults.set(category.rawValue, forKey: settingsCategoryKey)
          let settingsWindow = makeSettingsWindow(store: store, settings: settings, beside: window)
          settingsWindow.orderFrontRegardless()
          try? await Task.sleep(for: .seconds(2.5))
          emit("LORVEX_UI_PREVIEW_WINDOW=\(settingsWindow.windowNumber)")
          await emitStop("settings-\(category.rawValue)")
          settingsWindow.orderOut(nil)
        }
        previewDefaults.removeObject(forKey: settingsCategoryKey)
        // The menu bar panel is its own window: the tour announces its number
        // before the stop so the driver shoots the panel, not the main window.
        // It opens once on Today and once on Next 7 Days.
        for (scope, stop) in [(MenuBarScope.today, "menubar"), (.week, "menubar-week")] {
          previewDefaults.set(scope.rawValue, forKey: "menubar.scope")
          let panel = makeMenuBarPanelWindow(store: store, beside: window)
          panel.orderFrontRegardless()
          try? await Task.sleep(for: .seconds(2.5))
          emit("LORVEX_UI_PREVIEW_WINDOW=\(panel.windowNumber)")
          await emitStop(stop)
          panel.orderOut(nil)
        }
        previewDefaults.removeObject(forKey: "menubar.scope")
        // A detached list window, on the same list the tasks-list stop scoped
        // to, announced like the other windows of its own.
        if let list = store.lists?.lists.first(where: { !$0.isInbox }) {
          let listWindow = makeDetachedListWindow(store: store, listID: list.id, beside: window)
          listWindow.orderFrontRegardless()
          try? await Task.sleep(for: .seconds(2.5))
          emit("LORVEX_UI_PREVIEW_WINDOW=\(listWindow.windowNumber)")
          await emitStop("list-window")
          listWindow.orderOut(nil)
        }
        // The command palette on two typed queries: the start of a list's
        // name, where the jump leads, and a word that begins no destination or
        // list, where capture leads over the matching tasks.
        let jumpQuery = store.lists?.lists.first(where: { !$0.isInbox })
          .map { String($0.displayName.prefix(4)) } ?? "Hab"
        for (stop, query) in [("palette-jump", jumpQuery), ("palette-search", "offsite")] {
          let palette = makeCommandPaletteWindow(store: store, query: query, beside: window)
          palette.orderFrontRegardless()
          try? await Task.sleep(for: .seconds(2.5))
          emit("LORVEX_UI_PREVIEW_WINDOW=\(palette.windowNumber)")
          await emitStop(stop)
          palette.orderOut(nil)
        }
        // The task detail's field editors on the seeded task that waits on
        // another, so the Dependencies editor shows what a blocker's row says
        // under its title. The route loads the task and its draft even when
        // no loaded list holds it.
        if let load = store.applyRouteNavigation(.task(LorvexPreviewSeedID.venueTask)) { await load() }
        if let waiting = store.selectedTask, !waiting.dependsOn.isEmpty {
          for field in ["doOn", "due", "estimate", "repeat", "reminders", "dependencies"] {
            let editor = makeTaskEditorWindow(store: store, task: waiting, field: field, beside: window)
            editor.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(2))
            emit("LORVEX_UI_PREVIEW_WINDOW=\(editor.windowNumber)")
            await emitStop("task-editor-\(field)")
            editor.orderOut(nil)
          }
        }
        store.selectedTaskID = nil
        store.selection = .today
        // The create and edit sheets of lists and habits, each in a window of
        // its own sized like the sheet. An edit sheet opens on a seeded record.
        var sheetStops: [(String, AnyView)] = []
        let closed = Binding.constant(false)
        sheetStops.append(("sheet-createList", AnyView(CreateListSheet(store: store, isPresented: closed))))
        if let list = store.lists?.lists.first(where: { !$0.isInbox }) {
          sheetStops.append(("sheet-editList", AnyView(EditListSheet(list: list, store: store, isPresented: closed)
            .onAppear { store.prepareListDraft(for: list) })))
        }
        sheetStops.append(("sheet-createHabit", AnyView(CreateHabitSheet(store: store, isPresented: closed))))
        if let habit = store.habits?.habits.first {
          sheetStops.append(("sheet-editHabit", AnyView(EditHabitSheet(habit: habit, store: store, isPresented: closed)
            .onAppear { store.prepareHabitDraft(for: habit) })))
        }
        for (stop, sheet) in sheetStops {
          let sheetWindow = makeSheetWindow(sheet, beside: window)
          sheetWindow.orderFrontRegardless()
          try? await Task.sleep(for: .seconds(2))
          emit("LORVEX_UI_PREVIEW_WINDOW=\(sheetWindow.windowNumber)")
          await emitStop(stop)
          sheetWindow.orderOut(nil)
        }
        // The first-run wizard in a window of its own, a stop per page.
        let wizardState = SetupWizardState()
        let wizard = makeSetupWizardWindow(
          store: store, settings: settings, state: wizardState, beside: window)
        wizard.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(2))
        emit("LORVEX_UI_PREVIEW_WINDOW=\(wizard.windowNumber)")
        for step in SetupWizardStep.allCases {
          wizardState.currentStep = step
          try? await Task.sleep(for: .seconds(1.5))
          await emitStop("setup-\(step)")
          if step == .permissions {
            // Answered one each way, the page's tallest state: the denied
            // row stacks Open Settings under its answer.
            wizardState.calendarPermissionState = .granted
            wizardState.notificationsPermissionState = .denied
            try? await Task.sleep(for: .seconds(1))
            await emitStop("setup-permissions-answered")
          }
        }
        wizard.orderOut(nil)
        emit("LORVEX_UI_PREVIEW_TOUR_DONE")
      }
    }

    @MainActor
    private static func makeTourWindow(store: AppStore, settings: AppSettingsStore) -> NSWindow {
      // Place the tour on the roomiest display, not `NSScreen.main`: the app
      // never activates, so "main" is whichever screen happens to hold the key
      // window, and on a narrow secondary display AppKit clamps the window
      // below the three-pane floor (sidebar + workspace + inspector). The
      // split view then resolves the over-constraint by sliding the sidebar
      // off the left edge — a capture artifact no user with a normal display
      // would ever see.
      let preferred = NSSize(width: 1440, height: 900)
      let screen =
        NSScreen.screens
        .map(\.visibleFrame)
        .max { $0.width * $0.height < $1.width * $1.height }
        ?? NSRect(origin: .zero, size: preferred)
      let size = NSSize(
        width: min(preferred.width, screen.width),
        height: min(preferred.height, screen.height))
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      // The Tasks workspace keeps completed and cancelled tasks under a
      // History disclosure that is collapsed by default. The tour never points
      // at anything, so opening it here is the only way a capture shows the
      // completed row treatment at all.
      previewDefaults.set(true, forKey: "tasks.workspace.showHistory")
      let window = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false)
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.contentMinSize = LorvexWindowID.main.minimumContentSize
      window.toolbarStyle = .unified
      let hostingView = NSHostingView(
        rootView: LorvexMainWindowView(store: store, settings: settings, openMainWindow: {}).lorvexClockLocale()
          .defaultAppStorage(previewDefaults))
      // Let the workspaces' `.toolbar` items drive this AppKit-owned window's
      // toolbar exactly as they drive the `Window` scene, so the capture shows
      // the real chrome.
      hostingView.sceneBridgingOptions = [.toolbars]
      window.contentView = hostingView
      return window
    }

    /// The menu bar panel as the `MenuBarExtra` shows it, hosted in a plain
    /// borderless window sized once to the panel's fitting size, hung from the
    /// top-right corner of the main window's screen the way the real panel
    /// hangs from the status item. The status item itself is not part of the
    /// capture. The hosting view gets no sizing options on purpose: letting
    /// the panel's preferred size drive the window recursed through Auto
    /// Layout until the stack overflowed.
    @MainActor
    private static func makeMenuBarPanelWindow(store: AppStore, beside main: NSWindow) -> NSWindow {
      let hostingView = NSHostingView(
        rootView: MenuBarStatusView(store: store).defaultAppStorage(previewDefaults).lorvexClockLocale())
      hostingView.sizingOptions = []
      let size = hostingView.fittingSize
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(
        x: screen.maxX - size.width - LorvexDesign.Spacing.l,
        y: screen.maxY - LorvexDesign.Spacing.s - size.height)
      let panel = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false)
      panel.isReleasedWhenClosed = false
      panel.hasShadow = true
      panel.contentView = hostingView
      return panel
    }

    /// The preview-defaults key naming the category a Settings window opens
    /// on during the tour; `SettingsView` reads it once when it is created.
    static let settingsCategoryKey = "settings.preview.category"

    /// The Settings window at its ideal size, centered on the main window's
    /// screen, hosting the same view the Settings scene shows.
    @MainActor
    private static func makeSettingsWindow(
      store: AppStore, settings: AppSettingsStore, beside main: NSWindow
    ) -> NSWindow {
      let size = NSSize(width: 860, height: 640)
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      let settingsWindow = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false)
      settingsWindow.isReleasedWhenClosed = false
      settingsWindow.titlebarAppearsTransparent = true
      settingsWindow.titleVisibility = .hidden
      let hostingView = NSHostingView(
        rootView: LorvexSettingsWindowView(settings: settings, store: store).lorvexClockLocale()
          .defaultAppStorage(previewDefaults))
      hostingView.sceneBridgingOptions = [.toolbars]
      settingsWindow.contentView = hostingView
      return settingsWindow
    }

    /// A detached list window at a typical size, centered on the main window's
    /// screen, hosting the view the value-keyed list `WindowGroup` shows. Its
    /// title and toolbar are bridged from that view, as the scene would.
    @MainActor
    private static func makeDetachedListWindow(
      store: AppStore, listID: LorvexList.ID, beside main: NSWindow
    ) -> NSWindow {
      let size = NSSize(width: 720, height: 600)
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      let listWindow = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false)
      listWindow.isReleasedWhenClosed = false
      listWindow.toolbarStyle = .unified
      let hostingView = NSHostingView(
        rootView: DetachedListWindow(store: store, listID: listID).lorvexClockLocale()
          .defaultAppStorage(previewDefaults))
      hostingView.sceneBridgingOptions = [.toolbars, .title]
      listWindow.contentView = hostingView
      return listWindow
    }

    /// The command palette at its fixed size in a borderless window, centered
    /// on the main window's screen, opened on `query` as if it had been typed.
    /// The real palette is a sheet over the main window; the window stands in
    /// for the sheet's frame.
    @MainActor
    private static func makeCommandPaletteWindow(
      store: AppStore, query: String, beside main: NSWindow
    ) -> NSWindow {
      let size = NSSize(width: 560, height: 420)
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      let palette = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false)
      palette.isReleasedWhenClosed = false
      palette.hasShadow = true
      palette.contentView = NSHostingView(
        rootView: CommandPaletteView(store: store, initialQuery: query).lorvexClockLocale()
          .defaultAppStorage(previewDefaults))
      return palette
    }

    /// The first-run wizard at its sheet's size, in a borderless window
    /// centered on the main window's screen; the tour turns its pages through
    /// `state`.
    @MainActor
    private static func makeSetupWizardWindow(
      store: AppStore, settings: AppSettingsStore, state: SetupWizardState, beside main: NSWindow
    ) -> NSWindow {
      let size = NSSize(width: 540, height: 480)
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      let wizard = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false)
      wizard.isReleasedWhenClosed = false
      wizard.hasShadow = true
      wizard.contentView = NSHostingView(
        rootView: SetupWizardSheet(store: store, settings: settings, wizardState: state, onDismiss: {})
          .defaultAppStorage(previewDefaults))
      return wizard
    }

    /// One task detail field editor (`field` is a property row id) for
    /// `task`, padded and backed as its popover shows it, in a borderless
    /// window centered on the main window's screen. The task must be the
    /// store's selected task, whose draft the editor edits.
    @MainActor
    private static func makeTaskEditorWindow(
      store: AppStore, task: LorvexTask, field: String, beside main: NSWindow
    ) -> NSWindow {
      let hostingView = NSHostingView(
        rootView: TaskDetailView(store: store).wordEditor(field, task: task)
          .padding(LorvexDesign.Spacing.m)
          .frame(minWidth: 280)
          .fixedSize()
          .background(.windowBackground)
          .environment(\.taskDetailPanelInPopover, true)
          .defaultAppStorage(previewDefaults))
      let size = hostingView.fittingSize
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      let editor = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false)
      editor.isReleasedWhenClosed = false
      editor.hasShadow = true
      editor.contentView = hostingView
      return editor
    }

    /// A create or edit sheet in a borderless window sized to the sheet's own
    /// frame, so the tour photographs it without presenting a modal.
    @MainActor
    private static func makeSheetWindow(_ sheet: AnyView, beside main: NSWindow) -> NSWindow {
      let hostingView = NSHostingView(
        rootView: sheet
          .background(.windowBackground)
          .defaultAppStorage(previewDefaults))
      let size = hostingView.fittingSize
      let screen = main.screen?.visibleFrame ?? main.frame
      let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
      let sheetWindow = NSWindow(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false)
      sheetWindow.isReleasedWhenClosed = false
      sheetWindow.hasShadow = true
      sheetWindow.contentView = hostingView
      return sheetWindow
    }

    /// Announce a settled workspace, then keep it on screen until the capture
    /// driver says it is done shooting — or until ``captureAckTimeout`` passes
    /// when no driver is listening.
    private static func emitStop(_ name: String) async {
      emit("LORVEX_UI_PREVIEW_STOP=\(name)")
      guard let directory = captureAckDirectory else {
        try? await Task.sleep(for: .seconds(0.5))
        return
      }
      let marker = directory.appendingPathComponent("\(name).ack")
      let deadline = ContinuousClock.now.advanced(by: captureAckTimeout)
      while ContinuousClock.now < deadline {
        if FileManager.default.fileExists(atPath: marker.path) { return }
        try? await Task.sleep(for: .milliseconds(100))
      }
      emit("LORVEX_UI_PREVIEW_STOP_UNACKED=\(name)")
    }

    private static func emit(_ line: String) {
      print(line)
      fflush(stdout)
    }
  }

  extension LorvexAppleBootstrap {
    /// The full app store, but over a seeded in-memory core, or under
    /// `-uiPreviewEmptyStore` an empty one: the app as someone sees it before
    /// they have added anything. `AppStore(core:)` defaults every other
    /// dependency to a no-op — no CloudKit coordinator, no EventKit, no-op
    /// schedulers/publishers — which is exactly what the snapshot dump uses;
    /// here the scene body renders the live windows instead of exiting.
    @MainActor
    static func makeUIPreviewStore() -> AppStore {
      if CommandLine.arguments.contains("-uiPreviewEmptyStore") {
        return AppStore(core: LorvexPreviewCoreFactory.makeUIPreviewEmptyBlocking())
      }
      return AppStore(core: LorvexPreviewCoreFactory.makeUIPreviewSeededBlocking(
        todaySchedule: true,
        plannedDay: CommandLine.arguments.contains("-uiPreviewPlannedDay"),
        untimed: CommandLine.arguments.contains("-uiPreviewUntimed"),
        dayState: LorvexPreviewDayState.requested))
    }

    /// Ephemeral settings for `--ui-preview`: ``LorvexUIPreview/previewDefaults``
    /// wiped on each launch, so the preview never reads or writes the user's
    /// real settings, with onboarding pre-completed so the setup wizard doesn't
    /// block the workspace under capture.
    @MainActor
    static func makeUIPreviewSettings() -> AppSettingsStore {
      let suite = LorvexUIPreview.previewDefaultsSuiteName
      let defaults = LorvexUIPreview.previewDefaults
      defaults.removePersistentDomain(forName: suite)
      let settings = AppSettingsStore(defaults: defaults)
      settings.setupCompleted = true
      if let appearance = LorvexUIPreview.forcedAppearance {
        settings.appearance = appearance
      }
      return settings
    }
  }
#endif
