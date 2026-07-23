import LorvexCore
import LorvexMobile
import LorvexSystemIntents
import SwiftUI
import UserNotifications

@main
struct LorvexVisionApp: App {
  #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(LorvexVisionAppDelegate.self) private var appDelegate
  #endif
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Background App Intents share the managed store with the open spatial UI.
    DatabaseChangeSignal.configureApplicationProcess()
  }

  @State private var store = MobileStoreFactory(
    taskReminderSchedulerFactory: {
      UserNotificationTaskReminderScheduler(
        fallbackBody: MobileTaskReminderStrings.fallbackBody,
        actionTitles: MobileTaskReminderStrings.actionTitles)
    },
    setBadge: BadgeCoordinator.liveBadgeSetter,
    notificationAuthorizationStatusProvider: {
      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
  ).makeStore()

  var body: some Scene {
    WindowGroup(VisionAppMetadata.appDisplayName) {
      LorvexMobileStoreRootView(store: store, configuration: .vision)
        .lorvexMobileSystemEntrypoints(store: store)
        // Floor the window so the sidebar + detail split can't be dragged down
        // to a collapsed, unusable width; it still grows freely above this.
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .task(id: scenePhase) {
          // visionOS registers no push subscription (no remote-notification
          // delegate), so a foregrounded window would otherwise converge only on
          // the scene-active refresh below. Drain periodically while active to
          // pull remote changes during long sessions. `refresh()` runs the
          // pacing-gated CloudSync cycle and reloads snapshots; the pacing guard
          // self-throttles, so the fixed interval can't hammer CloudKit. The
          // `.task(id:)` cancels when the scene leaves `.active`.
          guard scenePhase == .active else { return }
          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(90))
            if Task.isCancelled { break }
            _ = await store.refresh()
          }
        }
    }
    // Open at a deliberate spatial size (a portrait-ish planning window).
    // `.contentMinSize` honors the content's `minWidth`/`minHeight` floor above
    // while leaving the window freely resizable upward.
    .defaultSize(width: 720, height: 900)
    .windowResizability(.contentMinSize)
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task {
        await store.refreshResettingCloudSyncPacing()
        store.applyPendingIntentHandoff()
      }
    }
  }
}
