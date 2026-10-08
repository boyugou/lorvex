import Foundation
import LorvexCore
import LorvexMobile
import LorvexSystemIntents
import SwiftUI
import UserNotifications

@main
struct LorvexMobileApp: App {
  #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(LorvexMobileAppDelegate.self) private var appDelegate
  #endif
  @Environment(\.scenePhase) private var scenePhase

  @State private var store: MobileStore

  // Retained for the process lifetime and activated during App initialization,
  // before any SwiftUI view task runs. A WatchConnectivity background launch
  // must not depend on the root view being constructed before its delegate is
  // ready.
  #if canImport(WatchConnectivity)
    private let watchReceiver: PhoneWatchConnectivityReceiver?
  #endif

  init() {
    #if canImport(UIKit)
      // The system runs App Intents in this process while it is in the
      // background, where the store's connections may still be suspended from
      // the app's last trip there. Each intent takes the store back through
      // this before it uses it.
      DatabaseSuspension.installBackgroundAccess(BackgroundDatabaseWork.access)
    #endif
    // App Intents can write the shared store without going through
    // `MobileStore`. Route those committed writes through the same coalesced
    // invalidation observed by the open UI, and relay widget/MCP Darwin signals.
    DatabaseChangeSignal.configureApplicationProcess()
    let builtStore = Self.makeStore()
    builtStore.diagnosticFallback = .live
    _store = State(initialValue: builtStore)

    #if canImport(WatchConnectivity)
      let receiver = PhoneWatchConnectivityReceiver(
        store: builtStore,
        databaseAccess: PhoneWatchDatabaseAccess(
          begin: { BackgroundDatabaseWork.begin() },
          end: { BackgroundDatabaseWork.end() }))
      receiver?.activate()
      watchReceiver = receiver
    #endif
  }

  @MainActor
  private static func makeStore() -> MobileStore {
    MobileStoreFactory(
      feedbackProviderFactory: {
        #if canImport(UIKit)
          return UIKitFeedbackProvider()
        #else
          return NoOpFeedbackProvider()
        #endif
      },
      taskReminderSchedulerFactory: {
        UserNotificationTaskReminderScheduler(
          fallbackBody: MobileTaskReminderStrings.fallbackBody,
          actionTitles: MobileTaskReminderStrings.actionTitles)
      },
      habitReminderSchedulerFactory: {
        UserNotificationHabitReminderScheduler(body: MobileHabitReminderStrings.body)
      },
      setBadge: BadgeCoordinator.liveBadgeSetter,
      notificationAuthorizationStatusProvider: {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
      }
    ).makeStore()
  }

  @ViewBuilder
  private var rootContent: some View {
    LorvexMobileStoreRootView(store: store)
      .lorvexMobileSystemEntrypoints(store: store)
      .task {
        #if canImport(UIKit)
          appDelegate.store = store
          // A background notification action may have failed before this
          // attachment (no observer was live); surface the recorded breadcrumb
          // now instead of losing it.
          await store.consumePendingNotificationActionError()
        #endif
        #if DEBUG
          #if os(iOS)
            DebugLaunchOrientation.applyIfRequested()
          #endif
          await store.debugSeedSampleDataIfNeeded()
          // Load the snapshot before resolving a launch deep-link so hooks that
          // read seeded data (e.g. `lorvex://firsttask`) see it rather than an
          // empty store.
          _ = await store.refresh()
          store.debugApplyLaunchNavigationIfNeeded()
          #if os(iOS)
            await DebugListScroller.scrollIfRequested()
            await DebugAccessibilityDump.dumpIfRequested()
          #endif
        #endif
      }
  }

  var body: some Scene {
    WindowGroup(MobileAppMetadata.appDisplayName) {
      #if DEBUG
        if CommandLine.arguments.contains("-lorvexWidgetGallery") {
          WidgetGalleryHostView()
        } else {
          rootContent
        }
      #else
        rootContent
      #endif
    }
    .lorvexMobileCommands(store: store)
    .lorvexReminderBackgroundRefresh(store: store)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        // Everything below reaches the database, which refuses locks while the
        // app is suspended. Take it back before the first read.
        DatabaseSuspension.resume()
        Task {
          await store.refresh()
          store.applyPendingIntentHandoff()
          if let typeID = LorvexShortcutHandoff.consume(),
            let action = LorvexQuickAction(typeIdentifier: typeID)
          {
            store.performQuickAction(action)
          }
        }
      }
      #if os(iOS)
        if phase == .background {
          // Ask iOS for a periodic background wake to re-arm the rolling reminder
          // window while the app is suspended (see ``ReminderBackgroundRefresh``).
          ReminderBackgroundRefresh.schedule()
          // Send what this device queued, then give up the App Group
          // database's locks before the system suspends this process.
          BackgroundSyncFlush.flushThenSuspend(store: store)
        }
      #endif
    }
  }
}

private extension Scene {
  @SceneBuilder
  func lorvexMobileCommands(store: MobileStore) -> some Scene {
    #if os(iOS)
      self.commands {
        LorvexMobileAppCommands(store: store)
      }
    #else
      self
    #endif
  }

  /// Registers the reminder-window background-refresh handler. Best-effort: iOS
  /// decides when to run it, and foreground/push replenishment remain the primary
  /// paths (see ``ReminderBackgroundRefresh``).
  @SceneBuilder
  func lorvexReminderBackgroundRefresh(store: MobileStore) -> some Scene {
    #if os(iOS)
      self.backgroundTask(.appRefresh(ReminderBackgroundRefresh.taskIdentifier)) {
        // Queue the next wake up front so an early expiration still leaves a
        // future opportunity scheduled, then run the same reminder-window
        // replenishment the foreground refresh fan-out does.
        ReminderBackgroundRefresh.schedule()
        await BackgroundDatabaseWork.run {
          await store.replenishReminderWindow()
        }
      }
    #else
      self
    #endif
  }
}

#if os(iOS)
  @MainActor
  private struct LorvexMobileAppCommands: Commands {
    let store: MobileStore

    var body: some Commands {
      CommandMenu(MobileCommandTitles.workspaceMenu) {
        Button(MobileCommandTitles.refresh) {
          Task { await store.refresh() }
        }
        .keyboardShortcut("r", modifiers: .command)

        Divider()

        // ⌘1–⌘4 follow the tab bar left to right, and Habits and Memory take
        // ⌘5 and ⌘6, the numbers the Mac sidebar gives every destination.
        primaryTabButton(.today, key: "1")
        primaryTabButton(.calendar, key: "2")
        primaryTabButton(.tasks, key: "3")
        primaryTabButton(.review, key: "4")
        destinationButton(.habits)
        destinationButton(.memory)

        Divider()

        Button(MobileCommandTitles.newCapture) {
          store.isPresentingCapture = true
        }
        .keyboardShortcut("n", modifiers: .command)
      }

      // The system inserts its own "Settings…" (⌘,) app command; replacing that
      // group with ours keeps the platform shortcut without a duplicate.
      CommandGroup(replacing: .appSettings) {
        destinationButton(.settings)
      }
    }

    private func primaryTabButton(_ tab: MobileTab, key: Character) -> some View {
      Button(MobileCommandTitles.title(for: tab)) {
        store.openPrimaryShortcutTab(tab)
      }
      .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
    }

    @ViewBuilder
    private func destinationButton(_ destination: MobileDestination) -> some View {
      let button = Button(MobileCommandTitles.title(for: destination)) {
        store.openShortcutDestination(destination)
      }
      if let key = destination.keyboardShortcutKey {
        button.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
      } else {
        button
      }
    }
  }
#endif
