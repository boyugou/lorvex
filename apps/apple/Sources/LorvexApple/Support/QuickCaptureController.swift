import Foundation
import Observation

/// Owns Quick Capture for the life of the app: the system-wide shortcut that
/// opens it, and the window it opens.
///
/// The shortcut follows ``AppSettingsStore/quickCaptureShortcut``: choosing a
/// chord in Settings registers it, `off` releases it, and a chord another app
/// already owns is reported through
/// ``AppSettingsStore/quickCaptureShortcutIsAvailable`` instead of failing
/// silently. The shortcut toggles the window, so pressing it again closes it.
@MainActor
final class QuickCaptureController {
  /// Posted by the menu command and the palette action to open the window.
  static let requestNotification = Notification.Name("com.lorvex.apple.quickCaptureRequested")

  private let settings: AppSettingsStore
  private let model: QuickCaptureModel
  private let presenter: any QuickCapturePresenting
  private let hotKey: any GlobalHotKeyRegistering
  private var requestObserver: Task<Void, Never>?

  init(
    settings: AppSettingsStore, model: QuickCaptureModel, presenter: any QuickCapturePresenting,
    hotKey: any GlobalHotKeyRegistering
  ) {
    self.settings = settings
    self.model = model
    self.presenter = presenter
    self.hotKey = hotKey
    model.onFinish = { [weak self] in self?.presenter.dismiss() }
  }

  /// Registers the chosen shortcut, keeps it in step with the setting, and
  /// opens the window whenever the menu command or the palette asks for it.
  func start() {
    applyShortcut()
    observeShortcut()
    let requests = NotificationCenter.default.notifications(named: Self.requestNotification)
    requestObserver = Task { [weak self] in
      for await _ in requests {
        self?.present()
      }
    }
  }

  /// Opens the window and starts a capture in it.
  func present() {
    model.prepare()
    presenter.present()
  }

  /// What the shortcut does: opens the window, or closes it when it is already
  /// open.
  func toggle() {
    if presenter.isPresented {
      presenter.dismiss()
    } else {
      present()
    }
  }

  private func applyShortcut() {
    settings.quickCaptureShortcutIsAvailable = hotKey.register(settings.quickCaptureShortcut) {
      [weak self] in self?.toggle()
    }
  }

  /// Re-applies the shortcut each time the setting changes. The tracking
  /// callback runs before the new value lands, so the read happens on the
  /// next turn of the main actor.
  private func observeShortcut() {
    withObservationTracking {
      _ = settings.quickCaptureShortcut
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.applyShortcut()
        self?.observeShortcut()
      }
    }
  }
}
