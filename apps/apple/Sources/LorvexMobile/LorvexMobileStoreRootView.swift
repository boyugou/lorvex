import LorvexCore
import SwiftUI

public struct LorvexMobileStoreRootView: View {
  @Bindable var store: MobileStore
  private let configuration: MobileShellConfiguration
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// Persisted app appearance (System/Light/Dark), shared with the Settings
  /// picker via `AppAppearance.preferenceKey`. Drives `preferredColorScheme`.
  @AppStorage(AppAppearance.preferenceKey) private var appearanceRaw = AppAppearance.system.rawValue
  private let setupPreferences: MobileSetupPreferences
  @State private var showSetupWizard = false

  public init(
    store: MobileStore,
    configuration: MobileShellConfiguration = .mobile,
    setupPreferences: MobileSetupPreferences = MobileSetupPreferences()
  ) {
    self.store = store
    self.configuration = configuration
    self.setupPreferences = setupPreferences
  }

  public var body: some View {
    Group {
      switch configuration.preferredChromeStyle(horizontalSizeClass: horizontalSizeClass) {
      case .tabBar:
        tabBarBody
      case .sidebar:
        sidebarBody
      }
    }
    .lorvexSpatialBackground()
    .background(keyboardShortcuts)
    .tint(.accentColor)
    // A crossing staged by a habit completion floats a celebratory badge above
    // the whole shell, wherever the completion was logged (Today / Habits tab).
    .lorvexMobileMilestoneCelebration(store.milestoneCelebration) {
      withAnimation(.easeOut(duration: 0.2)) { store.milestoneCelebration = nil }
    }
    .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme ?? nil)
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
      MobileSetupWizard(defaults: setupPreferences.defaults) {
        // `store.isSetupCompleted` gates the background reminder re-plan's
        // authorization request (see `MobileStore.rescheduleReminders`); flip
        // it and re-plan immediately so any reminder withheld during
        // onboarding arms right away instead of waiting for the next
        // unrelated refresh.
        store.isSetupCompleted = true
        Task { await store.rescheduleReminders() }
      }
      .interactiveDismissDisabled(true)
      // Force the full-height detent: a first-run wizard must own the screen.
      // Without this the sheet adopted a shorter height and clipped the pinned
      // call-to-action once the welcome copy wrapped to multiple lines.
      .presentationDetents([.large])
      .lorvexSpatialBackground()
    }
    .sheet(isPresented: $store.isPresentingCapture) {
      MobileStoreCaptureSheet(store: store)
        .lorvexSpatialBackground()
    }
  }

  private var tabBarBody: some View {
    TabView(selection: $store.selectedTab) {
      tab(.today) {
        NavigationStack(path: $store.routePath) {
          MobileStoreTodayView(store: store)
            // The date IS the title (informative, unlike a redundant "Today" that
            // just echoes the tab). A standard large title — no custom header band,
            // no empty collapse gap.
            .navigationTitle(MobileTodayHeader.dateText())
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

      tab(.tasks) {
        // The Tasks home owns the stack's MobileRoute + MobileTasksScope
        // destinations; the scoped task list it pushes does not re-declare them.
        NavigationStack(path: $store.tasksRoutePath) {
          MobileStoreTasksHomeView(store: store)
        }
      }

      tab(.calendar) {
        NavigationStack {
          MobileStoreCalendarView(store: store)
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      }

      tab(.habits) {
        // Bound (unlike Calendar's) so a deep link / Handoff / Spotlight route to
        // a specific habit can push its detail — see `MobileStore.habitsRoutePath`.
        NavigationStack(path: $store.habitsRoutePath) {
          MobileStoreHabitsView(store: store)
            .navigationDestination(for: MobileRoute.self) { route in
              MobileStoreRouteView(route: route, store: store)
            }
        }
      }

      tab(.more) {
        MobileStoreMoreView(store: store)
      }
    }
  }

  private var sidebarBody: some View {
    NavigationSplitView {
      MobileStoreSidebarList(
        store: store,
        appDisplayName: configuration.appDisplayName
      )
    } detail: {
      MobileStoreDetailView(store: store, iPadDestination: effectiveIPadDestination)
        .lorvexSpatialBackground()
    }
    .onChange(of: store.iPadDestination) { _, destination in
      guard let destination else { return }
      store.selectedTab = .more
      store.moreNavigationPath = [destination]
    }
    .onChange(of: store.moreNavigationPath) { _, path in
      guard store.selectedTab == .more else { return }
      store.iPadDestination = path.first
    }
  }

  private var effectiveIPadDestination: MobileDestination? {
    store.selectedTab == .more ? (store.iPadDestination ?? store.moreNavigationPath.first) : nil
  }

  private func tab<Content: View>(
    _ tab: MobileTab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .tabItem {
        Label(tab.title, systemImage: tab.systemImage)
      }
      .tag(tab)
  }
}
