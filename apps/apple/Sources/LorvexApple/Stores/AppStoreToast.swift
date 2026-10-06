import Foundation

extension AppStore {
  /// Restarts the clock that clears ``toastMessage`` when no window does. It
  /// runs on every assignment, so a replacement message gets its own full
  /// ``toastLifetime`` and clearing the toast cancels the pending expiry.
  func scheduleToastExpiry() {
    toastExpiry?.cancel()
    toastExpiry = nil
    guard let message = toastMessage else { return }
    let lifetime = toastLifetime
    toastExpiry = Task { [weak self] in
      try? await Task.sleep(for: lifetime)
      guard !Task.isCancelled else { return }
      self?.expireToast(ifStill: message)
    }
  }

  /// Clears the toast when it still shows `message`. A newer message stays: it
  /// has its own pending expiry.
  func expireToast(ifStill message: String) {
    guard toastMessage == message else { return }
    toastMessage = nil
  }
}
