import LorvexCloudSync
import LorvexCore
import SwiftUI

public struct LorvexMobileStoreRootView: View {
  @Bindable var store: MobileStore
  /// Persisted app appearance (System/Light/Dark), shared with the Settings
  /// picker via `AppAppearance.preferenceKey`. Drives `preferredColorScheme`.
  @AppStorage(AppAppearance.preferenceKey) private var appearanceRaw = AppAppearance.system.rawValue
  private let setupPreferences: MobileSetupPreferences
  @State private var showSetupWizard = false
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  public init(
    store: MobileStore,
    setupPreferences: MobileSetupPreferences = MobileSetupPreferences()
  ) {
    self.store = store
    self.setupPreferences = setupPreferences
  }

  public var body: some View {
    tabBarBody
    // A crossing staged by a habit completion floats a celebratory badge above
    // the whole shell, wherever the completion was logged (Today, the Habits
    // workspace, a habit's detail).
    .lorvexMobileMilestoneCelebration(store.milestoneCelebration) {
      lorvexAnimated(.easeOut(duration: 0.2)) { store.milestoneCelebration = nil }
    }
    .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme ?? nil)
    .lorvexClockLocale()
    // Task rows count their due days in the synced product zone.
    .environment(\.lorvexProductTimeZone, store.logicalTimeZone)
    // Surface mutation failures (capture/complete/calendar/etc.) — the store
    // sets `errorMessage` but without this the failure was invisible.
    .alert(
      String(
        localized: "error.title", defaultValue: "Something went wrong", table: "Localizable",
        bundle: MobileL10n.bundle),
      isPresented: Binding(
        get: { store.errorMessage != nil },
        set: { if !$0 { store.errorMessage = nil } }
      )
    ) {
      Button(
        String(
          localized: "common.ok", defaultValue: "OK", table: "Localizable",
          bundle: MobileL10n.bundle), role: .cancel
      ) { store.errorMessage = nil }
    } message: {
      if let message = store.errorMessage {
        Text(message)
      }
    }
    // A one-time notice that a corrupt/incompatible database was set aside on
    // open and a fresh one created — so the user isn't left silently staring at
    // an empty app wondering where their data went.
    .alert(
      String(
        localized: "database.recovery.title", defaultValue: "Previous data set aside",
        table: "Localizable", bundle: MobileL10n.bundle),
      isPresented: Binding(
        get: { store.databaseRecoveryMessage != nil },
        set: { if !$0 { store.databaseRecoveryMessage = nil } }
      )
    ) {
      Button(
        String(
          localized: "common.ok", defaultValue: "OK", table: "Localizable",
          bundle: MobileL10n.bundle), role: .cancel
      ) {
        store.databaseRecoveryMessage = nil
      }
    } message: {
      if let message = store.databaseRecoveryMessage {
        Text(message)
      }
    }
    .mobileRecurringCancelDialog(store)
    .task {
      // Start the app-lifetime CloudKit observers (push refresh + account
      // change) once. The store outlives this view, so they keep running.
      store.startLifetimeObserversIfNeeded()
      if store.snapshot.today == .empty {
        await store.refresh()
      }
    }
    .task {
      if !setupPreferences.setupCompleted {
        showSetupWizard = true
      }
    }
    .sheet(isPresented: $showSetupWizard) {
      MobileSetupWizard(
        defaults: setupPreferences.defaults,
        turnOnCloudSync: {
          // The request is made before the task starts, as the Settings
          // toggle makes it, so a cloud-data deletion that lands first
          // supersedes it.
          let request = store.makeCloudSyncModeRequest(.live)
          Task { await store.setCloudSyncModeFromSettings(request) }
        },
        onComplete: {
          // `store.isSetupCompleted` gates the background reminder re-plan's
          // authorization request (see `MobileStore.rescheduleReminders`);
          // flip it and re-plan immediately so any reminder withheld during
          // onboarding arms right away instead of waiting for the next
          // unrelated refresh.
          store.isSetupCompleted = true
          Task { await store.rescheduleReminders() }
        })
      .interactiveDismissDisabled(true)
      // Force the full-height detent: a first-run wizard must own the screen.
      // Without this the sheet adopted a shorter height and clipped the pinned
      // call-to-action once the welcome copy wrapped to multiple lines.
      .presentationDetents([.large])
    }
    .sheet(isPresented: $store.isPresentingCapture) {
      MobileStoreCaptureSheet(store: store, showsAsCard: horizontalSizeClass == .regular)
    }
    // Last, so the sheets presented from this view (capture, setup) inherit the
    // accent as the sheets inside the tabs do; without it their Cancel button
    // draws in the label color while every other sheet's draws in the accent.
    .tint(.accentColor)
  }

  /// The tab bar's selection: one of the store's tabs, or the round + that
  /// opens capture. Choosing + raises the capture sheet and leaves the current
  /// tab selected, because capture is an action, not a place.
  private var tabBarSelection: Binding<MobileTabBarItem> {
    Binding(
      get: { .tab(store.selectedTab) },
      set: { item in
        switch item {
        case .tab(let tab): store.selectedTab = tab
        case .capture: store.isPresentingCapture = true
        }
      })
  }

  /// iPhone and iPad navigation: Today, Calendar, Tasks, and Review in the bar,
  /// and the round + beside it on every tab. The bar holds only the tabs it
  /// shows: Habits and Memory open as workspaces on the Tasks stack, Settings
  /// on Today's, so a link that names one pushes it rather than selecting a
  /// tab the bar does not draw.
  private var tabBarBody: some View {
    TabView(selection: tabBarSelection) {
      tab(.today) {
        NavigationStack(path: $store.routePath) {
          MobileStoreTodayView(store: store)
            // The page opens with its own date and sentence, so the bar keeps
            // "Today" only as the back-button name and draws no title.
            .navigationTitle(MobileTab.today.title)
            #if os(iOS)
              .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
              ToolbarItem(placement: .principal) { Text(verbatim: "").accessibilityHidden(true) }
            }
            // Block with skeletons only on the first load. Refreshes keep
            // existing content visible and use the native `.refreshable` affordance.
            .overlay {
              if store.isLoading, store.snapshot.today == .empty {
                MobileInitialWorkspaceSkeleton()
              }
            }
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      }

      tab(.calendar) {
        // Bound (like Tasks) so tapping a scheduled task pushes its
        // detail onto the Calendar stack in place — see
        // `MobileStore.calendarRoutePath`.
        // No readable-width cap here: the day grid and its agenda pane use the
        // whole window, and the calendar already draws an inline title. The
        // week agenda caps itself.
        NavigationStack(path: $store.calendarRoutePath) {
          MobileStoreCalendarView(store: store)
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      }

      tab(.tasks) {
        // The Tasks home owns the stack's MobileRoute + MobileTasksScope
        // destinations; the scoped task list it pushes does not re-declare them.
        NavigationStack(path: $store.tasksRoutePath) {
          MobileStoreTasksHomeView(store: store)
            .mobileReadableWidth(inlineTitleAtRegularWidth: true)
        }
      }

      tab(.review) {
        NavigationStack(path: $store.reviewRoutePath) {
          MobileStoreReviewView(store: store)
            .mobileReadableWidth(inlineTitleAtRegularWidth: true)
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      }

      Tab(value: MobileTabBarItem.capture, role: .search) {
        Color.clear
      } label: {
        Label(
          String(
            localized: "today.capture", defaultValue: "Capture", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus")
      }
      .accessibilityIdentifier("tabBar.capture")
    }
  }

  private func tab<Content: View>(
    _ tab: MobileTab,
    @ViewBuilder content: @escaping () -> Content
  ) -> some TabContent<MobileTabBarItem> {
    Tab(tab.title, systemImage: tab.systemImage, value: MobileTabBarItem.tab(tab)) {
      content()
    }
  }
}

/// A tab bar item on iPhone: a store tab, or the round + that opens capture.
enum MobileTabBarItem: Hashable {
  case tab(MobileTab)
  case capture
}
