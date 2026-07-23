import LorvexCore
import SwiftUI

enum MainWindowLayoutMetrics {
  static let sidebarMinWidth: CGFloat = 148
  static let sidebarIdealWidth: CGFloat = 164
  static let sidebarMaxWidth: CGFloat = 184
  // The task detail's content (priority chips, action row, checklist rows with
  // trailing menus) needs ~300pt to render without its trailing controls
  // clipping, so the inspector must not be squeezed below that.
  static let inspectorMinWidth: CGFloat = 300
  static let inspectorIdealWidth: CGFloat = 320
  static let inspectorMaxWidth: CGFloat = 380
}

struct ContentView: View {
  @Bindable var store: AppStore
  var settings: AppSettingsStore

  @State private var navigationColumnVisibility: NavigationSplitViewVisibility = .all
  @State private var showSetupWizard: Bool = false

  var body: some View {
    NavigationSplitView(columnVisibility: $navigationColumnVisibility) {
      SidebarView(store: store)
        .navigationSplitViewColumnWidth(
          min: MainWindowLayoutMetrics.sidebarMinWidth,
          ideal: MainWindowLayoutMetrics.sidebarIdealWidth,
          max: MainWindowLayoutMetrics.sidebarMaxWidth
        )
    } detail: {
      // The workspace owns the full main area — Calendar, Habits, the Eisenhower
      // matrix, etc. render edge-to-edge instead of being squeezed into a middle
      // column. The task detail rides in a trailing inspector that appears only
      // once a task is actually selected, so nothing heavy is shown by default.
      WorkspaceView(store: store)
        .environment(settings)
        .inspector(isPresented: inspectorPresented) {
          Group {
            if store.selectedTaskID != nil {
              TaskDetailView(store: store)
            } else if let habitID = store.selectedHabitID {
              HabitDetailInspector(store: store, habitID: habitID)
            }
          }
          .inspectorColumnWidth(
            min: MainWindowLayoutMetrics.inspectorMinWidth,
            ideal: MainWindowLayoutMetrics.inspectorIdealWidth,
            max: MainWindowLayoutMetrics.inspectorMaxWidth
          )
        }
    }
    .navigationSplitViewStyle(.balanced)
    // Escape collapses the open task/habit inspector, matching its ✕ and the
    // re-click-to-close gesture. A focused text field consumes Escape first
    // (cancelling its edit), so this only fires once nothing else claims it.
    .onExitCommand { store.dismissOpenInspector() }
    // The window's minimum content width must equal the sum of the VISIBLE
    // panes' minimums. The inspector lives inside the detail column, so with a
    // fixed window minimum the three-pane case over-constrains the split view
    // and it resolves by sliding the sidebar off (the half-clipped sidebar).
    // Raising the minimum only while a task is selected keeps the two-pane
    // minimum compact and makes the three-pane layout a hard stop instead:
    // `.windowResizability(.contentMinSize)` re-clamps the window live, growing
    // it automatically when the inspector opens at the minimum width.
    .frame(minWidth: minimumWindowWidth)
    // `.contentMinSize` resizability only reads the content minimum at window
    // creation; this enforcer re-clamps the live window whenever the minimum
    // changes (inspector opens → wider floor, closes → back to the base).
    .background(WindowMinWidthEnforcer(store: store))
    // Publish the live column visibility so the View-menu "Show/Hide Sidebar"
    // command (⌃⌘S) drives the same state as the toolbar's sidebar toggle.
    .focusedSceneValue(\.sidebarVisibility, $navigationColumnVisibility)
    .focusedSceneValue(\.lorvexTaskCommandContext, taskCommandContext)
    .sheet(isPresented: $showSetupWizard) {
      SetupWizardSheet(store: store, settings: settings) {
        showSetupWizard = false
        // The wizard flag only gates this sheet; assistants read the core's
        // setup state. Mirror completion so get_setup_status agrees.
        // `store.isSetupCompleted` gates the background reminder re-plan's
        // authorization request (see `rescheduleReminders`); flip it and
        // re-plan immediately so any reminder withheld during onboarding
        // arms right away instead of waiting for the next unrelated refresh.
        store.isSetupCompleted = true
        Task {
          await store.markCoreSetupComplete()
          await store.rescheduleReminders()
        }
      }
      // Match the mobile wizard: the user must reach the final step (which sets
      // `setupCompleted`), not Escape-dismiss it — otherwise the wizard re-opens
      // on every launch. Every step has a Skip/Continue path to the end.
      .interactiveDismissDisabled(true)
    }
    .sheet(isPresented: $store.showCommandPalette) {
      CommandPaletteView(store: store)
    }
    .onAppear {
      if !settings.setupCompleted {
        showSetupWizard = true
      }
    }
    .onChange(of: settings.setupCompleted) { _, completed in
      if !completed {
        showSetupWizard = true
      }
    }
    .task(id: store.focusSurfaceTaskSignature) {
      await store.loadFocusSurfaceTasks()
    }
    .lorvexErrorAlert(store)
    .alert(
      String(
        localized: "database.recovery.title",
        defaultValue: "Previous data set aside",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      isPresented: Binding(
        get: { store.databaseRecoveryMessage != nil },
        set: { if !$0 { store.databaseRecoveryMessage = nil } }
      )
    ) {
      Button(String(localized: "common.ok", defaultValue: "OK", table: "Localizable", bundle: LorvexL10n.bundle)) {
        store.databaseRecoveryMessage = nil
      }
    } message: {
      if let message = store.databaseRecoveryMessage {
        Text(message)
      }
    }
    .lorvexToast(message: store.toastMessage) {
      store.toastMessage = nil
    }
    .lorvexMilestoneCelebration(store.milestoneCelebration) {
      lorvexAnimated(.spring(response: 0.4, dampingFraction: 0.82)) {
        store.milestoneCelebration = nil
      }
    }
    // Recurring-cancel scope choice for the main workspace store. Detached
    // task/list windows mount the same modifier on their per-window stores.
    .lorvexRecurringCancelDialog(store)
    .lorvexPermanentDeleteDialog(store)
  }

  /// The window's minimum content width as a function of the visible panes:
  /// the two-pane base (`LorvexWindowID.main.minimumContentSize`) plus, while
  /// the task inspector is open, its ideal width — so sidebar + workspace keep
  /// their full two-pane budget and the split view never has to collapse the
  /// sidebar to satisfy the inspector.
  private var minimumWindowWidth: CGFloat {
    let base = LorvexWindowID.main.minimumContentSize.width
    guard store.selectedTaskID != nil || store.selectedHabitID != nil else { return base }
    return base + MainWindowLayoutMetrics.inspectorIdealWidth
  }

  private var taskCommandContext: LorvexTaskCommandContext? {
    switch store.selection {
    case .today:
      LorvexTaskCommandContext(
        store: store,
        selectionSurface: .focus,
        fallbackTaskID: store.selectedTaskID
      )
    case .tasks:
      LorvexTaskCommandContext(
        store: store,
        selectionSurface: .taskWorkspace,
        fallbackTaskID: store.selectedTaskID
      )
    case .lists:
      LorvexTaskCommandContext(
        store: store,
        selectionSurface: .selectedList,
        fallbackTaskID: store.selectedTaskID
      )
    case .calendar where store.selectedTask != nil:
      LorvexTaskCommandContext(store: store, selectionSurface: nil)
    case .calendar, .habits, .reviews, .memory:
      nil
    }
  }

  /// The task detail inspector is shown whenever a task is selected. The
  /// selection is cleared on navigation into workspaces that don't surface a
  /// task detail (see `AppStore.selection`'s didSet), so this stays empty by
  /// default; tapping a scheduled task in the Calendar — which sets the
  /// selection itself — now opens the inspector too. Dismissing it clears the
  /// selection so it doesn't silently reopen.
  private var inspectorPresented: Binding<Bool> {
    Binding(
      get: { store.selectedTaskID != nil || store.selectedHabitID != nil },
      set: { presented in
        if !presented {
          store.selectedTaskID = nil
          store.selectedHabitID = nil
        }
      }
    )
  }
}
