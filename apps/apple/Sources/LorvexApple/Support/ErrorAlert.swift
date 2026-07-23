import SwiftUI

extension View {
  /// Presents `AppStore.errorMessage` as a modal error alert on the window that
  /// mounts it. Like ``lorvexRecurringCancelDialog(_:)``, a SwiftUI `alert`
  /// only presents on its host window, so every scene root that drives a store
  /// must mount this: the main/workspace store for shared windows, and each
  /// per-window store for detached task/list windows. Without it, a failed
  /// mutation in a detached window sets `errorMessage` with no visible
  /// feedback.
  func lorvexErrorAlert(_ store: AppStore) -> some View {
    modifier(LorvexErrorAlertModifier(store: store))
  }
}

private struct LorvexErrorAlertModifier: ViewModifier {
  @Bindable var store: AppStore

  private var isPresented: Binding<Bool> {
    Binding(
      get: { store.errorMessage != nil },
      set: { if !$0 { store.errorMessage = nil } }
    )
  }

  func body(content: Content) -> some View {
    content.alert(
      String(localized: "common.error", defaultValue: "Error", table: "Localizable", bundle: LorvexL10n.bundle),
      isPresented: isPresented
    ) {
      Button(String(localized: "common.ok", defaultValue: "OK", table: "Localizable", bundle: LorvexL10n.bundle)) {
        store.errorMessage = nil
      }
    } message: {
      Text(store.errorMessage ?? "")
    }
  }
}
