import LorvexCore
import SwiftUI
import UserNotifications

/// The first-run setup wizard for the iOS/iPadOS surface: a welcome, the
/// choice to sync through iCloud, notification permission, and a closing page
/// that names the two ways work gets into Lorvex (capture on any tab, or an
/// assistant connected on the Mac).
///
/// iCloud sync is off until someone turns it on, so the sync page asks: Turn
/// On runs `turnOnCloudSync` (the same transition Settings runs) without
/// waiting for it, and Not Now leaves sync off.
///
/// Reads and writes `setupCompleted` directly to `UserDefaults.standard` using
/// the same key the macOS `AppSettingsStore` uses, so the flag is shared when
/// both targets target the same defaults suite.
public struct MobileSetupWizard: View {
  /// The wizard's pages, in order.
  private enum Step: Int, CaseIterable {
    case welcome, cloudSync, notifications, done
  }

  @State private var step: Step
  @State private var permissionsViewModel = PermissionsStatusViewModel()
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  /// The width of a feature row's symbol column, grown with the text so a
  /// larger symbol still lines the rows' text up.
  @ScaledMetric(relativeTo: .largeTitle) private var featureSymbolColumnWidth: CGFloat = 44
  private let preferences: MobileSetupPreferences
  /// Turns iCloud sync on. Returns at once; the transition runs on its own and
  /// reports its progress in Settings.
  private let turnOnCloudSync: () -> Void
  /// Called after the wizard finishes (Get Started) or is skipped, once
  /// `setupCompleted` has been persisted. Lets the host store lift its own
  /// reminder-authorization hold (`MobileStore.isSetupCompleted`) and re-plan
  /// immediately instead of waiting for the next unrelated refresh.
  private let onComplete: () -> Void

  public init(
    defaults: UserDefaults = .standard,
    turnOnCloudSync: @escaping () -> Void,
    onComplete: @escaping () -> Void = {}
  ) {
    self.preferences = MobileSetupPreferences(defaults: defaults)
    self.turnOnCloudSync = turnOnCloudSync
    self.onComplete = onComplete
    _step = State(initialValue: Self.launchStep)
  }

  /// The page the wizard opens on: the welcome page, or in a DEBUG build the
  /// page named by the `-lorvexSetupStep <welcome|cloudSync|notifications|done>`
  /// launch argument, so a screenshot can show any page without tapping
  /// through the ones before it.
  private static var launchStep: Step {
    #if DEBUG
      let arguments = CommandLine.arguments
      if let index = arguments.firstIndex(of: "-lorvexSetupStep"),
        arguments.indices.contains(index + 1),
        let step = Step.allCases.first(where: { "\($0)" == arguments[index + 1] })
      {
        return step
      }
    #endif
    return .welcome
  }

  public var body: some View {
    NavigationStack {
      content
        .navigationTitle(stepTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            if step != .done {
              Button(String(localized: "setup.skip", defaultValue: "Skip", table: "Localizable", bundle: MobileL10n.bundle)) { skip() }
            }
          }
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome: mobileWelcome
    case .cloudSync: mobileCloudSync
    case .notifications: mobileNotifications
    case .done: mobileDone
    }
  }

  private var stepTitle: String {
    switch step {
    case .welcome: String(localized: "setup.step.welcome", defaultValue: "Welcome", table: "Localizable", bundle: MobileL10n.bundle)
    case .cloudSync: String(localized: "setup.step.sync", defaultValue: "iCloud Sync", table: "Localizable", bundle: MobileL10n.bundle)
    case .notifications: String(localized: "setup.step.notifications", defaultValue: "Notifications", table: "Localizable", bundle: MobileL10n.bundle)
    case .done: String(localized: "setup.step.ready", defaultValue: "Ready", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  // MARK: - Steps

  private var mobileWelcome: some View {
    setupPage(
      systemImage: "checklist",
      iconTint: .accentColor,
      title: Text(String(localized: "setup.welcome.title", defaultValue: "Welcome to Lorvex", table: "Localizable", bundle: MobileL10n.bundle))
    ) {
      featureRow(
        systemImage: "sparkles",
        title: String(localized: "setup.welcome.assistant.title", defaultValue: "Your assistant does the writing", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.welcome.assistant.detail", defaultValue: "Lorvex has no AI of its own. Connect Claude or another MCP assistant to Lorvex on your Mac.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "sun.max",
        title: String(localized: "setup.welcome.today.title", defaultValue: "Your day in one place", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.welcome.today.detail", defaultValue: "What’s planned, due, or started today, in one list.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "person.crop.circle.badge.checkmark",
        title: String(localized: "setup.welcome.control.title", defaultValue: "You have the last word", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.welcome.control.detail", defaultValue: "Your assistant suggests and plans; you decide what stays on your list.", table: "Localizable", bundle: MobileL10n.bundle))
    }
    .safeAreaBar(edge: .bottom) {
      actionStack { continueButton }
    }
  }

  private var mobileCloudSync: some View {
    setupPage(
      systemImage: "icloud",
      iconTint: .accentColor,
      title: Text(String(localized: "setup.sync.title", defaultValue: "Sync with iCloud", table: "Localizable", bundle: MobileL10n.bundle))
    ) {
      featureRow(
        systemImage: "laptopcomputer.and.iphone",
        title: String(localized: "setup.sync.devices.title", defaultValue: "The same on every device", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.sync.devices.detail", defaultValue: "Your tasks, lists, and habits stay in step on iPhone, iPad, and Mac.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "lock.icloud",
        title: String(localized: "setup.sync.private.title", defaultValue: "Private to you", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.sync.private.detail", defaultValue: "Stored encrypted in your own iCloud account. Lorvex has no server of its own.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "switch.2",
        title: String(localized: "setup.sync.off.title", defaultValue: "Off whenever you like", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.sync.off.detail", defaultValue: "Turn syncing off anytime in Settings. Your data stays on this device.", table: "Localizable", bundle: MobileL10n.bundle))
    }
    .safeAreaBar(edge: .bottom) {
      actionStack {
        primaryButton(String(localized: "setup.sync.turn_on", defaultValue: "Turn On iCloud Sync", table: "Localizable", bundle: MobileL10n.bundle)) {
          turnOnCloudSync()
          advance()
        }
        .accessibilityIdentifier("setup.sync.turnOn")
      } secondary: {
        secondaryButton(notNowLabel, action: advance)
          .accessibilityIdentifier("setup.sync.notNow")
      }
    }
  }

  /// The notifications page. Asking here, during onboarding, settles the
  /// decision, so the first reminder re-plan (`MobileStore.rescheduleReminders`)
  /// finds it made instead of raising the system's one-time prompt from a
  /// background refresh. Allow Notifications raises that prompt and moves on
  /// once it is answered. The system asks only once, so when the decision was
  /// made before the page opened, the page states it under the explanation
  /// and offers Continue (and, when notifications are off, Open Settings).
  private var mobileNotifications: some View {
    setupPage(
      systemImage: "bell.badge",
      iconTint: .accentColor,
      title: Text(String(localized: "setup.notifications.title", defaultValue: "Get Task Reminders", table: "Localizable", bundle: MobileL10n.bundle))
    ) {
      featureRow(
        systemImage: "clock",
        title: String(localized: "setup.notifications.due.title", defaultValue: "Reminders on time", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.notifications.due.detail", defaultValue: "Lorvex notifies you when a task’s reminder is due.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "hand.tap",
        title: String(localized: "setup.notifications.act.title", defaultValue: "Act from the notification", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.notifications.act.detail", defaultValue: "Complete the task, snooze it for an hour, or defer it to tomorrow right from the notification.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "gearshape",
        title: String(localized: "setup.notifications.change.title", defaultValue: "Yours to change", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.notifications.change.detail", defaultValue: "You can change this anytime in Settings.", table: "Localizable", bundle: MobileL10n.bundle))
      notificationsAnswer
        .frame(maxWidth: .infinity)
    }
    .task { await permissionsViewModel.refresh() }
    .safeAreaBar(edge: .bottom) {
      notificationsActions
    }
  }

  @ViewBuilder
  private var notificationsAnswer: some View {
    switch permissionsViewModel.notificationsStatus {
    case .authorized, .provisional:
      Label(
        String(localized: "setup.notifications.on", defaultValue: "Notifications are on.", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "checkmark.circle.fill"
      )
      .font(LorvexDesign.Typography.secondaryText.weight(.medium))
      .foregroundStyle(LorvexDesign.Palette.success)
    case .denied:
      Label(
        String(localized: "setup.notifications.off", defaultValue: "Notifications are off for Lorvex.", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "bell.slash"
      )
      .font(LorvexDesign.Typography.secondaryText.weight(.medium))
      .foregroundStyle(.secondary)
    case .notDetermined, .unknown:
      EmptyView()
    }
  }

  @ViewBuilder
  private var notificationsActions: some View {
    switch permissionsViewModel.notificationsStatus {
    case .notDetermined, .unknown:
      actionStack {
        primaryButton(String(localized: "setup.notifications.allow", defaultValue: "Allow Notifications", table: "Localizable", bundle: MobileL10n.bundle)) {
          Task { await requestNotifications() }
        }
        .accessibilityIdentifier("setup.notifications.allow")
      } secondary: {
        secondaryButton(notNowLabel, action: advance)
          .accessibilityIdentifier("setup.notifications.notNow")
      }
    case .authorized, .provisional:
      actionStack { continueButton }
    case .denied:
      actionStack {
        continueButton
      } secondary: {
        secondaryButton(String(localized: "permissions.open_settings", defaultValue: "Open Settings", table: "Localizable", bundle: MobileL10n.bundle)) {
          openURL(LorvexNotificationSettingsURL.settingsURL)
        }
      }
    }
  }

  private var mobileDone: some View {
    setupPage(
      systemImage: "checkmark.seal.fill",
      iconTint: LorvexDesign.Palette.success,
      title: Text(String(localized: "setup.done.title", defaultValue: "You’re ready.", table: "Localizable", bundle: MobileL10n.bundle))
    ) {
      featureRow(
        systemImage: "plus.circle",
        title: String(localized: "setup.done.capture.title", defaultValue: "Capture it yourself", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.done.capture.detail", defaultValue: "Tap ＋ on any tab to add a task.", table: "Localizable", bundle: MobileL10n.bundle))
      featureRow(
        systemImage: "sparkles",
        title: String(localized: "setup.done.assistant.title", defaultValue: "Or let your assistant add it", table: "Localizable", bundle: MobileL10n.bundle),
        detail: String(localized: "setup.done.assistant.detail", defaultValue: "Connect Claude or another assistant in Lorvex’s settings on your Mac, and it adds tasks and plans your day with you.", table: "Localizable", bundle: MobileL10n.bundle))
    }
    .safeAreaBar(edge: .bottom) {
      actionStack {
        primaryButton(String(localized: "setup.get_started", defaultValue: "Get Started", table: "Localizable", bundle: MobileL10n.bundle)) {
          preferences.complete()
          onComplete()
          dismiss()
        }
      }
    }
  }

  // MARK: - Helpers

  private func advance() {
    lorvexAnimated { step = Step(rawValue: step.rawValue + 1) ?? .done }
  }

  /// Raises the system's notification prompt, then moves on whatever the
  /// answer: either one is the decision the page asks for.
  private func requestNotifications() async {
    _ = try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound, .badge])
    await permissionsViewModel.refresh()
    advance()
  }

  /// Skips the remaining steps and finishes setup, so "Skip" leaves onboarding
  /// rather than merely advancing one step. Mirrors the done step's finish
  /// action (`setupCompleted` is set once), which is why the toolbar hides Skip
  /// on the final step.
  private func skip() {
    preferences.complete()
    onComplete()
    dismiss()
  }

  /// A page of the wizard: a tinted icon badge and a title anchored at the
  /// top, and under them the page's points as ``featureRow(systemImage:title:detail:)``
  /// rows (the notifications page adds its answer after them). The badge and
  /// the title sit at one height on every page. The content scrolls, so large
  /// text never pushes a row off the screen; the page's `actionStack` lives in
  /// a `safeAreaBar`, so its buttons stay pinned at the bottom and a row that
  /// scrolls beneath them fades out instead of being cut at their edge.
  private func setupPage<Content: View>(
    systemImage: String,
    iconTint: Color,
    title: Text,
    @ViewBuilder content: () -> Content
  ) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        ZStack {
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous)
            .fill(iconTint.opacity(0.12))
          Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .frame(width: 44, height: 44)
            .foregroundStyle(iconTint)
            .accessibilityHidden(true)
        }
        .frame(width: 96, height: 96)

        title
          .font(LorvexDesign.Typography.screenTitle)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 24)

        VStack(alignment: .leading, spacing: 24) {
          content()
        }
        .padding(.top, 32)
      }
      .frame(maxWidth: 480)
      .padding(.horizontal, 28)
      .padding(.top, 24)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  /// One point a page makes: a tinted symbol beside a short title and a line
  /// that explains it, read by VoiceOver as one element. The symbol takes its
  /// size from a text style, so it grows with the text, as does its column.
  private func featureRow(systemImage: String, title: String, detail: String) -> some View {
    HStack(spacing: 16) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.screenTitle)
        .fontWeight(.regular)
        .foregroundStyle(.tint)
        .frame(width: featureSymbolColumnWidth)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
        Text(detail)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  /// The buttons pinned at the bottom of a page: the main action, and under
  /// it the quieter choice when the page offers one, large and inset from the
  /// screen edges. The second row keeps its height on a page without one, so
  /// the main action sits at the same place on every page.
  private func actionStack<Primary: View, Secondary: View>(
    @ViewBuilder primary: () -> Primary,
    @ViewBuilder secondary: () -> Secondary
  ) -> some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      primary()
      secondaryButton(" ", action: {})
        .hidden()
        .accessibilityHidden(true)
        .overlay { secondary() }
    }
    .controlSize(.large)
    .padding(.horizontal)
    .padding(.vertical, 12)
  }

  /// A page's bottom buttons when it offers only its main action.
  private func actionStack<Primary: View>(@ViewBuilder primary: () -> Primary) -> some View {
    actionStack(primary: primary) { EmptyView() }
  }

  /// A page's main action: prominent, the full width of the page.
  private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
  }

  /// The quieter choice under a page's main action, such as declining it.
  private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderless)
  }

  private var continueButton: some View {
    primaryButton(String(localized: "setup.continue", defaultValue: "Continue", table: "Localizable", bundle: MobileL10n.bundle), action: advance)
  }

  private var notNowLabel: String {
    String(localized: "setup.not_now", defaultValue: "Not Now", table: "Localizable", bundle: MobileL10n.bundle)
  }
}
