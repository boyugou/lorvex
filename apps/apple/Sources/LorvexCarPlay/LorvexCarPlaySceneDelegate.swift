// LorvexCarPlaySceneDelegate.swift
// LorvexCarPlay
//
// PROVISIONING NOTE: This file compiles on any iOS 14+ SDK, but the CarPlay
// scene is only reachable on a real device after Apple approves the
// com.apple.developer.carplay-communication entitlement for the Lorvex App ID.
// Without that approval the template application scene listed in Info.plist is
// silently ignored by CarPlay.
//
// Required provisioning steps (Apple must grant each):
//   1. Request CarPlay entitlement at developer.apple.com → Certificates,
//      Identifiers & Profiles → your App ID → Additional Capabilities.
//   2. Add Config/LorvexCarPlay.entitlements (provided) to the app target's
//      Code Signing Entitlements build setting (or merge into
//      LorvexMobileApp.entitlements).
//   3. Add the CPTemplateApplicationScene configuration to
//      LorvexMobileApp-Info.plist (see the documentation block in that file).

#if canImport(CarPlay) && os(iOS)
  import CarPlay
  import Foundation
  import LorvexCore

  /// CarPlay scene delegate. Builds and maintains a CPListTemplate with two
  /// sections — Focus tasks and all remaining Today tasks — and wires each row
  /// to present a `CPActionSheetTemplate` of task actions (Complete, defer,
  /// un-focus, Handoff) rather than completing on a single tap.
  @MainActor
  public final class LorvexCarPlaySceneDelegate: NSObject,
    CPTemplateApplicationSceneDelegate
  {

    private var interfaceController: CPInterfaceController?
    private let controller = CarPlayTaskListController()

    /// Streams `DatabaseChangeSignal.didChangeNotification` while connected and
    /// schedules a debounced list refresh. Cancelled on disconnect.
    private var dataChangeObserverTask: Task<Void, Never>?

    /// The pending debounced refresh. Each incoming change cancels and restarts
    /// it, so a burst of writes collapses into a single list refresh.
    private var pendingRefreshTask: Task<Void, Never>?

    /// Coalescing window for live data-change refreshes. Writes from the MCP host
    /// (the product's primary write surface) can land in bursts; one refresh after
    /// a short quiet period keeps the driving list current without rebuilding the
    /// template on every individual write.
    private static let dataChangeDebounce: Duration = .seconds(2)

    /// The process-global Darwin → NotificationCenter relay is started at most
    /// once. It has no teardown (it is shared with the host app's stores), so it
    /// must not be re-registered on every CarPlay reconnect.
    private static var hasStartedDatabaseChangeRelay = false

    /// Mirrors `Notification.Name.lorvexCloudKitRemoteChange` declared in
    /// LorvexCloudSync. LorvexCarPlay depends only on LorvexCore, so the name is
    /// referenced by its stable raw value rather than the symbol. Posting it asks
    /// the in-process store that owns the CloudSync coordinator to drain the
    /// outbox and pull from CloudKit — the same channel the app delegate uses when
    /// a silent push arrives.
    private static let cloudKitRemoteChangeNotification = Notification.Name(
      "com.lorvex.cloudkit.remoteChange")

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(
      _ templateApplicationScene: CPTemplateApplicationScene,
      didConnect interfaceController: CPInterfaceController
    ) {
      self.interfaceController = interfaceController
      // Connecting is the strongest "make this fresh now" moment: kick a CloudKit
      // pull so a drive begun after edits on another device shows them instead of
      // a stale local snapshot, and subscribe to live writes so the list no longer
      // freezes for the rest of the drive.
      triggerSyncOnConnect()
      startObservingDataChanges()
      Task { [weak self] in
        guard let self else { return }
        do {
          try await self.loadAndPresent()
        } catch {
          self.controller.errorMessage = CarPlayTaskListController.driverSafeErrorMessage(for: error)
          self.interfaceController?.setRootTemplate(self.buildTemplate(), animated: false, completion: nil)
        }
      }
    }

    public func templateApplicationScene(
      _ templateApplicationScene: CPTemplateApplicationScene,
      didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
      dataChangeObserverTask?.cancel()
      dataChangeObserverTask = nil
      pendingRefreshTask?.cancel()
      pendingRefreshTask = nil
      self.interfaceController = nil
    }

    // MARK: - Private

    private func loadAndPresent() async throws {
      try await controller.refresh()
      let template = buildTemplate()
      interfaceController?.setRootTemplate(template, animated: false, completion: nil)
    }

    // MARK: - Live data refresh

    /// Subscribes to the shared "local database changed" signal — the same
    /// mechanism the macOS `AppStore` and `LorvexMobile` store observe — so the
    /// driving list reflects writes made by the assistant (MCP host) mid-drive.
    /// Refreshes are debounced; see `dataChangeDebounce`.
    private func startObservingDataChanges() {
      // The Darwin → NotificationCenter relay is process-global and persistent;
      // only the per-connection async-stream subscription below is torn down on
      // disconnect. The host app's store may also start the relay, so guard so a
      // CarPlay reconnect never stacks duplicate relays.
      if !Self.hasStartedDatabaseChangeRelay {
        DatabaseChangeSignal.startObserving()
        Self.hasStartedDatabaseChangeRelay = true
      }
      dataChangeObserverTask?.cancel()
      dataChangeObserverTask = Task { [weak self] in
        let stream = NotificationCenter.default.notifications(
          named: DatabaseChangeSignal.didChangeNotification)
        for await _ in stream {
          guard !Task.isCancelled else { return }
          self?.scheduleDebouncedRefresh()
        }
      }
    }

    /// Restarts the debounce window. The most recent change wins: a steady stream
    /// of writes refreshes the list once, `dataChangeDebounce` after the last one.
    private func scheduleDebouncedRefresh() {
      pendingRefreshTask?.cancel()
      pendingRefreshTask = Task { [weak self] in
        try? await Task.sleep(for: Self.dataChangeDebounce)
        guard !Task.isCancelled, let self else { return }
        await self.runAndRefresh { try await self.controller.refresh() }
      }
    }

    /// Asks the in-process store that owns the CloudSync coordinator to drain the
    /// outbox and pull from CloudKit. CarPlay's own core has no sync coordinator,
    /// so it signals the host app over the established remote-change channel
    /// rather than reaching across module boundaries.
    private func triggerSyncOnConnect() {
      NotificationCenter.default.post(
        name: Self.cloudKitRemoteChangeNotification, object: nil)
    }

    private func buildTemplate() -> CPListTemplate {
      var sections: [CPListSection] = []
      let hasError = controller.errorMessage != nil

      // Error section with a Retry row when the last load failed. It consumes
      // one slot from the CarPlay item budget so the task rows never overflow
      // the system's per-template maximum.
      if let errorMessage = controller.errorMessage {
        sections.append(CPListSection(
          items: [makeRetryItem(detail: errorMessage)],
          header: String(
            localized: "carplay.section.error", defaultValue: "Error",
            table: "Localizable", bundle: CarPlayL10n.bundle),
          sectionIndexTitle: nil
        ))
      }

      // CarPlay caps total rows per template (driving safety). Reserve the
      // retry slot, give Focus priority, then fill the remainder with Today.
      let budget = max(0, Int(CPListTemplate.maximumItemCount) - (hasError ? 1 : 0))
      let focusRows = Array(controller.focusRows.prefix(budget))
      let todayRows = Array(controller.todayRows.prefix(max(0, budget - focusRows.count)))

      if !hasError, focusRows.isEmpty, todayRows.isEmpty {
        sections.append(CPListSection(items: [makeEmptyStateItem()]))
        return CPListTemplate(title: "Lorvex", sections: sections)
      }

      if !focusRows.isEmpty {
        sections.append(CPListSection(
          items: focusRows.map(makeItem),
          header: String(
            localized: "carplay.section.focus", defaultValue: "Focus",
            table: "Localizable", bundle: CarPlayL10n.bundle),
          sectionIndexTitle: nil
        ))
      }
      if !todayRows.isEmpty {
        sections.append(CPListSection(
          items: todayRows.map(makeItem),
          header: String(
            localized: "carplay.section.today", defaultValue: "Today",
            table: "Localizable", bundle: CarPlayL10n.bundle),
          sectionIndexTitle: nil
        ))
      }
      return CPListTemplate(title: "Lorvex", sections: sections)
    }

    private func makeRetryItem(detail: String) -> CPListItem {
      let retryItem = CPListItem(
        text: String(
          localized: "carplay.action.retry", defaultValue: "Retry",
          table: "Localizable", bundle: CarPlayL10n.bundle),
        detailText: detail
      )
      retryItem.handler = { [weak self] _, completion in
        guard let self else { completion(); return }
        Task { @MainActor in
          self.controller.errorMessage = nil
          do {
            try await self.loadAndPresent()
          } catch {
            self.controller.errorMessage = CarPlayTaskListController.driverSafeErrorMessage(for: error)
            self.updateRootTemplateSections()
          }
          completion()
        }
      }
      return retryItem
    }

    /// A single non-actionable row shown when there is nothing to do. Leaving
    /// `handler` nil keeps it from rendering a tappable disclosure.
    private func makeEmptyStateItem() -> CPListItem {
      CPListItem(
        text: String(
          localized: "carplay.empty.title", defaultValue: "All clear",
          table: "Localizable", bundle: CarPlayL10n.bundle),
        detailText: String(
          localized: "carplay.empty.detail", defaultValue: "No tasks for today.",
          table: "Localizable", bundle: CarPlayL10n.bundle)
      )
    }

    /// Builds a task row. Tapping it presents an action sheet rather than
    /// completing immediately — a single tap can no longer accidentally close a
    /// task, and the driver gets defer / un-focus / Handoff affordances too.
    private func makeItem(for row: CarPlayTaskListController.Row) -> CPListItem {
      let item = CPListItem(text: row.title, detailText: nil)
      // CarPlay invokes the handler on the main thread but its type is not
      // `@MainActor`-isolated, so hop explicitly before touching state.
      item.handler = { [weak self] _, completion in
        completion()
        Task { @MainActor in self?.presentActions(for: row) }
      }
      return item
    }

    private func presentActions(for row: CarPlayTaskListController.Row) {
      // CPAlertActionHandler is not `@MainActor`-isolated, so each handler hops
      // back onto the main actor before touching the controller or templates.
      var actions: [CPAlertAction] = [
        CPAlertAction(
          title: String(
            localized: "carplay.action.complete", defaultValue: "Complete",
            table: "Localizable", bundle: CarPlayL10n.bundle),
          style: .default
        ) { [weak self] _ in
          Task { @MainActor in
            guard let self else { return }
            self.dismissPresented()
            await self.runAndRefresh { try await self.controller.complete(id: row.id) }
          }
        },
        CPAlertAction(
          title: String(
            localized: "carplay.action.defer_tomorrow", defaultValue: "Defer to Tomorrow",
            table: "Localizable", bundle: CarPlayL10n.bundle),
          style: .default
        ) { [weak self] _ in
          Task { @MainActor in
            guard let self else { return }
            self.dismissPresented()
            await self.runAndRefresh { try await self.controller.deferToTomorrow(id: row.id) }
          }
        },
      ]

      if row.isFocus {
        actions.append(CPAlertAction(
          title: String(
            localized: "carplay.action.remove_focus", defaultValue: "Remove from Focus",
            table: "Localizable", bundle: CarPlayL10n.bundle),
          style: .default
        ) { [weak self] _ in
          Task { @MainActor in
            guard let self else { return }
            self.dismissPresented()
            await self.runAndRefresh { try await self.controller.removeFromFocus(id: row.id) }
          }
        })
      }

      actions.append(CPAlertAction(
        title: String(
          localized: "carplay.action.open_iphone", defaultValue: "Open on iPhone",
          table: "Localizable", bundle: CarPlayL10n.bundle),
        style: .default
      ) { [weak self] _ in
        Task { @MainActor in
          self?.broadcastHandoffActivity(for: row)
          self?.dismissPresented()
        }
      })

      actions.append(CPAlertAction(
        title: String(
          localized: "carplay.action.cancel", defaultValue: "Cancel",
          table: "Localizable", bundle: CarPlayL10n.bundle),
        style: .cancel
      ) { [weak self] _ in
        Task { @MainActor in self?.dismissPresented() }
      })

      let sheet = CPActionSheetTemplate(title: row.title, message: nil, actions: actions)
      interfaceController?.presentTemplate(sheet, animated: true, completion: nil)
    }

    /// Runs an async mutation, then refreshes the root list. A failure is mapped
    /// to a driver-safe retry row rather than surfaced raw. Caller dismisses the
    /// action sheet first so the list is visible while the work runs.
    private func runAndRefresh(_ work: @MainActor () async throws -> Void) async {
      do {
        controller.errorMessage = nil
        try await work()
      } catch {
        controller.errorMessage = CarPlayTaskListController.driverSafeErrorMessage(for: error)
      }
      updateRootTemplateSections()
    }

    private func dismissPresented() {
      interfaceController?.dismissTemplate(animated: true, completion: nil)
    }

    private func updateRootTemplateSections() {
      guard let ctrl = interfaceController,
        let updated = ctrl.rootTemplate as? CPListTemplate
      else { return }
      updated.updateSections(buildTemplate().sections)
    }

    // MARK: - NSUserActivity Handoff

    /// Sets a `NSUserActivity` on the scene so the paired iPhone can pick up
    /// the selected task via Handoff.
    private func broadcastHandoffActivity(for row: CarPlayTaskListController.Row) {
      guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? CPTemplateApplicationScene }).first
      else { return }
      let activity = NSUserActivity(activityType: LorvexActivityType.openTask)
      activity.title = row.title
      activity.userInfo = [LorvexActivityKey.taskID: row.id]
      activity.isEligibleForHandoff = true
      scene.userActivity = activity
    }
  }
#endif
