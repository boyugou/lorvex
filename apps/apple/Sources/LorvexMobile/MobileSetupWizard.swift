import LorvexCore
import SwiftUI
import UserNotifications

/// Three-step first-run setup wizard for the iOS/iPadOS surface.
///
/// Reads and writes `setupCompleted` directly to `UserDefaults.standard` using
/// the same key the macOS `AppSettingsStore` uses, so the flag is shared when
/// both targets target the same defaults suite.
public struct MobileSetupWizard: View {
  @State private var step = 0
  @State private var permissionsViewModel = PermissionsStatusViewModel()
  @Environment(\.dismiss) private var dismiss
  private let preferences: MobileSetupPreferences
  /// Called after the wizard finishes (Get Started) or is skipped, once
  /// `setupCompleted` has been persisted. Lets the host store lift its own
  /// reminder-authorization hold (`MobileStore.isSetupCompleted`) and re-plan
  /// immediately instead of waiting for the next unrelated refresh.
  private let onComplete: () -> Void

  public init(defaults: UserDefaults = .standard, onComplete: @escaping () -> Void = {}) {
    self.preferences = MobileSetupPreferences(defaults: defaults)
    self.onComplete = onComplete
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
            if step < 2 {
              Button(String(localized: "setup.skip", defaultValue: "Skip", table: "Localizable", bundle: MobileL10n.bundle)) { skip() }
            }
          }
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case 0: mobileWelcome
    case 1: mobilePermissionsInfo
    default: mobileDone
    }
  }

  private var stepTitle: String {
    switch step {
    case 0: return String(localized: "setup.step.welcome", defaultValue: "Welcome", table: "Localizable", bundle: MobileL10n.bundle)
    case 1: return String(localized: "setup.step.permissions", defaultValue: "Permissions", table: "Localizable", bundle: MobileL10n.bundle)
    default: return String(localized: "setup.step.ready", defaultValue: "Ready", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  // MARK: - Steps

  private var mobileWelcome: some View {
    setupHero(
      systemImage: "sparkles",
      iconTint: .accentColor,
      title: Text(String(localized: "setup.welcome.title", defaultValue: "Welcome to Lorvex", table: "Localizable", bundle: MobileL10n.bundle)),
      subtitle: Text(String(localized: "setup.welcome.subtitle", defaultValue: "Your AI-native planner — capture tasks in a tap, plan your day, and stay in sync across your Apple devices.", table: "Localizable", bundle: MobileL10n.bundle))
    )
    .safeAreaInset(edge: .bottom) {
      bottomBar(String(localized: "setup.continue", defaultValue: "Continue", table: "Localizable", bundle: MobileL10n.bundle), action: advance)
    }
  }

  private var mobilePermissionsInfo: some View {
    Form {
      Section {
        MobileWizardNotificationsPermissionRow(viewModel: permissionsViewModel)
      } header: {
        Text(String(localized: "setup.permissions.header", defaultValue: "Optional permissions", table: "Localizable", bundle: MobileL10n.bundle))
      } footer: {
        Text(String(localized: "setup.permissions.footer", defaultValue: "You can grant notifications now or later from Settings.", table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .task { await permissionsViewModel.refresh() }
    .safeAreaInset(edge: .bottom) {
      bottomBar(String(localized: "setup.continue", defaultValue: "Continue", table: "Localizable", bundle: MobileL10n.bundle), action: advance)
    }
  }

  private var mobileDone: some View {
    setupHero(
      systemImage: "checkmark.seal.fill",
      iconTint: .green,
      title: Text(String(localized: "setup.done.title", defaultValue: "You're ready.", table: "Localizable", bundle: MobileL10n.bundle)),
      subtitle: Text(String(localized: "setup.done.subtitle", defaultValue: "Use Capture to save tasks quickly, then organize them from Today or Lists.", table: "Localizable", bundle: MobileL10n.bundle))
    )
    .safeAreaInset(edge: .bottom) {
      bottomBar(String(localized: "setup.get_started", defaultValue: "Get Started", table: "Localizable", bundle: MobileL10n.bundle)) {
        preferences.complete()
        onComplete()
        dismiss()
      }
    }
  }

  // MARK: - Helpers

  private func advance() {
    withAnimation { step += 1 }
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

  /// A centered hero panel: a tinted icon badge over a title and subtitle.
  /// Shared by the welcome and done steps. The content is vertically centered by
  /// the flexible spacers; the step's pinned `bottomBar` lives in a
  /// `safeAreaInset`, so the call-to-action can never be squeezed off-screen the
  /// way it was when the button shared the spacer-driven stack.
  private func setupHero(
    systemImage: String,
    iconTint: Color,
    title: Text,
    subtitle: Text
  ) -> some View {
    VStack(spacing: 16) {
      Spacer(minLength: 24)
      ZStack {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
      .padding(.bottom, 8)

      title
        .font(LorvexDesign.Typography.screenTitle)
        .multilineTextAlignment(.center)
        // Inside the spacer-driven stack the sheet proposes a single line of
        // height, so a title wider than the sheet would truncate ("Welcome to
        // Lorv…") instead of wrapping. fixedSize lets it claim the height it needs.
        .fixedSize(horizontal: false, vertical: true)

      subtitle
        .font(LorvexDesign.Typography.secondaryText)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 24)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 28)
  }

  /// Full-width prominent call-to-action pinned at the bottom of a step.
  private func bottomBar(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .padding(.horizontal)
    .padding(.vertical, 12)
  }
}

/// The wizard's own explicit notifications request row — primes authorization
/// here, during onboarding, so the first real reminder re-plan
/// (`MobileStore.rescheduleReminders`) finds the decision already made instead
/// of triggering the system's one-time prompt itself from a background
/// refresh. Reuses `PermissionsStatusView`'s row vocabulary (status text,
/// Request button, Open Settings link) so Settings and onboarding present a
/// single consistent permission language, and needs no new localized strings.
private struct MobileWizardNotificationsPermissionRow: View {
  let viewModel: PermissionsStatusViewModel

  var body: some View {
    HStack {
      Label(
        String(localized: "setup.permissions.notifications", defaultValue: "Notifications deliver task reminders.", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "bell")
      Spacer()
      statusOrAction
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var statusOrAction: some View {
    switch viewModel.notificationsStatus {
    case .authorized, .provisional:
      Text(String(localized: "permissions.status.allowed", defaultValue: "Allowed", table: "Localizable", bundle: MobileL10n.bundle))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.green)
    case .denied:
      Link(
        String(localized: "permissions.open_settings", defaultValue: "Open Settings", table: "Localizable", bundle: MobileL10n.bundle),
        destination: LorvexNotificationSettingsURL.settingsURL
      )
      .font(LorvexDesign.Typography.tertiaryText)
    case .notDetermined, .unknown:
      Button(String(localized: "permissions.request", defaultValue: "Request", table: "Localizable", bundle: MobileL10n.bundle)) {
        Task {
          _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
          await viewModel.refresh()
        }
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .buttonStyle(.borderless)
    }
  }
}
