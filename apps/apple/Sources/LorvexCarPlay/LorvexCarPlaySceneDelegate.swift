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
//
// A simulator build can be made CarPlay-capable without Apple's approval:
// script/carplay_sim_enable.sh patches the built app's Info.plist and re-signs
// it ad hoc with the CarPlay entitlement.

#if canImport(CarPlay) && os(iOS)
  import CarPlay
  import Foundation
  import LorvexCore
  import UIKit

  /// CarPlay scene delegate. Presents Today's list as one `CPListTemplate`
  /// titled Today, in Today's order with a task whose time is running first.
  /// Each row carries a one-line detail (its time, else its state or estimate)
  /// and a state glyph, and opens a `CPActionSheetTemplate` (Done, Tomorrow
  /// instead, Open on iPhone) rather than completing on a single tap.
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

    /// Re-renders the list at each minute boundary so a running time's "Until"
    /// detail and the lead row follow the clock without a core read. Cancelled
    /// on disconnect.
    private var minuteTickerTask: Task<Void, Never>?

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
      startMinuteTicker()
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
      minuteTickerTask?.cancel()
      minuteTickerTask = nil
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

    /// Wakes at each minute boundary and re-renders the already-loaded rows.
    private func startMinuteTicker() {
      minuteTickerTask?.cancel()
      minuteTickerTask = Task { [weak self] in
        while !Task.isCancelled {
          let secondsIntoMinute = Calendar.current.component(.second, from: Date())
          try? await Task.sleep(for: .seconds(max(1, 60 - secondsIntoMinute)))
          guard !Task.isCancelled, let self else { return }
          self.updateRootTemplateSections()
        }
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

    // MARK: - Template

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
      // retry slot; the list is cut from its end, so the lead task always shows.
      let budget = max(0, Int(CPListTemplate.maximumItemCount) - (hasError ? 1 : 0))
      let nowMinutes = controller.nowMinutes
      let rows = Array(controller.rows.prefix(budget))
      if !rows.isEmpty {
        sections.append(CPListSection(
          items: rows.map { makeItem(for: $0, nowMinutes: nowMinutes) }))
      }

      let template = CPListTemplate(
        title: String(
          localized: "carplay.title", defaultValue: "Today",
          table: "Localizable", bundle: CarPlayL10n.bundle),
        sections: sections)
      // Shown by the system only while the template has no sections: a clear
      // day reads as a quiet screen, not as a fake tappable row.
      template.emptyViewTitleVariants = [
        String(
          localized: "carplay.empty.title", defaultValue: "All clear",
          table: "Localizable", bundle: CarPlayL10n.bundle)
      ]
      template.emptyViewSubtitleVariants = [
        String(
          localized: "carplay.empty.detail", defaultValue: "Nothing left for today.",
          table: "Localizable", bundle: CarPlayL10n.bundle)
      ]
      return template
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

    /// Builds a task row: title, the clock detail, and a state glyph. Tapping
    /// it presents an action sheet rather than completing immediately — a
    /// single tap can no longer accidentally close a task.
    private func makeItem(
      for row: CarPlayTaskListController.Row,
      nowMinutes: Int?
    ) -> CPListItem {
      let item = CPListItem(
        text: row.title,
        detailText: CarPlayRowCopy.detail(for: row, nowMinutes: nowMinutes),
        image: Self.stateImage(for: row))
      item.accessoryType = .disclosureIndicator
      // CarPlay invokes the handler on the main thread but its type is not
      // `@MainActor`-isolated, so hop explicitly before touching state.
      item.handler = { [weak self] _, completion in
        completion()
        Task { @MainActor in self?.presentActions(for: row, nowMinutes: nowMinutes) }
      }
      return item
    }

    /// One glyph per row state, with the meaning colors carry everywhere else
    /// in Lorvex: blue is what the driver started, red is a missed deadline,
    /// grey is the rest of the day.
    private static func stateImage(for row: CarPlayTaskListController.Row) -> UIImage? {
      let name: String
      let tint: UIColor
      if row.isStarted {
        name = "play.circle.fill"
        tint = .systemBlue
      } else if row.isOverdue {
        name = "exclamationmark.circle"
        tint = .systemRed
      } else {
        name = "circle"
        tint = .systemGray
      }
      let configuration = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
      return UIImage(systemName: name, withConfiguration: configuration)?
        .withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    // MARK: - Actions

    private func presentActions(for row: CarPlayTaskListController.Row, nowMinutes: Int?) {
      var actions: [CPAlertAction] = [
        mutationAction(
          title: String(
            localized: "carplay.action.complete", defaultValue: "Done",
            table: "Localizable", bundle: CarPlayL10n.bundle)
        ) { [controller] in try await controller.complete(id: row.id) }
      ]

      actions.append(mutationAction(
        title: String(
          localized: "carplay.action.defer_tomorrow", defaultValue: "Tomorrow instead",
          table: "Localizable", bundle: CarPlayL10n.bundle)
      ) { [controller] in try await controller.deferToTomorrow(id: row.id) })

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

      let sheet = CPActionSheetTemplate(
        title: row.title,
        message: CarPlayRowCopy.detail(for: row, nowMinutes: nowMinutes),
        actions: actions)
      interfaceController?.presentTemplate(sheet, animated: true, completion: nil)
    }

    /// An action that dismisses the sheet, runs one controller mutation, and
    /// re-renders the list. `CPAlertActionHandler` is not `@MainActor`-isolated,
    /// so the handler hops onto the main actor first.
    private func mutationAction(
      title: String,
      work: @escaping @MainActor () async throws -> Void
    ) -> CPAlertAction {
      CPAlertAction(title: title, style: .default) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.dismissPresented()
          await self.runAndRefresh(work)
        }
      }
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
