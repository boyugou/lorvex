import Foundation
import LorvexCore
import LorvexMobile
import LorvexSystemIntents
import SwiftUI
import TipKit
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
    // App Intents and CarPlay can write the shared store without going through
    // `MobileStore`. Route those committed writes through the same coalesced
    // invalidation observed by the open UI, and relay widget/MCP Darwin signals.
    DatabaseChangeSignal.configureApplicationProcess()
    try? Tips.configure([
      .displayFrequency(.immediate),
      .datastoreLocation(.applicationDefault)
    ])
    let builtStore = Self.makeStore()
    _store = State(initialValue: builtStore)

    #if canImport(WatchConnectivity)
      let receiver = PhoneWatchConnectivityReceiver(store: builtStore)
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
    LorvexMobileStoreRootView(store: store, configuration: .mobile)
      .lorvexMobileSystemEntrypoints(store: store)
      .task {
        #if canImport(UIKit)
          appDelegate.store = store
          // A CloudKit push may have arrived before this attachment (the
          // delegate persisted a handoff instead of dropping it); run the
          // drain it asked for now rather than waiting for a future
          // foreground trigger.
          await store.consumePendingCloudSyncPushHandoffIfNeeded()
        #endif
        #if DEBUG
          await store.debugSeedSampleDataIfNeeded()
          // Load the snapshot before resolving a launch deep-link so hooks that
          // read seeded data (e.g. `lorvex://firsttask`) see it rather than an
          // empty store.
          _ = await store.refresh()
          store.debugApplyLaunchNavigationIfNeeded()
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
        Task {
          await store.refreshResettingCloudSyncPacing()
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
        await store.replenishReminderWindow()
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
          Task { await store.refreshResettingCloudSyncPacing() }
        }
        .keyboardShortcut("r", modifiers: .command)

        Divider()

        primaryTabButton(.today, key: "1")
        primaryTabButton(.tasks, key: "2")
        primaryTabButton(.calendar, key: "3")
        primaryTabButton(.habits, key: "4")
        primaryTabButton(.more, key: "5")

        Divider()

        Button(MobileCommandTitles.newCapture) {
          store.isPresentingCapture = true
        }
        .keyboardShortcut("n", modifiers: .command)

        Divider()

        destinationButton(.lists)
        destinationButton(.memory)
        destinationButton(.review)
        destinationButton(.settings)
      }
    }

    private func primaryTabButton(_ tab: MobileTab, key: Character) -> some View {
      Button(MobileCommandTitles.title(for: tab)) {
        store.openPrimaryShortcutTab(tab)
      }
      .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
    }

    private func destinationButton(_ destination: MobileDestination) -> some View {
      Button(MobileCommandTitles.title(for: destination)) {
        store.openShortcutDestination(destination)
      }
      .keyboardShortcut(
        KeyEquivalent(Character(destination.keyboardShortcutKey)),
        modifiers: .command
      )
    }
  }
#endif
