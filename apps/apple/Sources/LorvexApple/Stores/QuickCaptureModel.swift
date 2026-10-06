import Foundation
import LorvexCore
import Observation

/// The state behind the Quick Capture window: the line being typed and how far
/// the capture has come.
///
/// One model serves every presentation of the window. A presentation starts
/// from ``prepare()``; a capture ends in ``submit()``, which writes
/// the task through ``AppStore/commitCapture(_:)`` (the same reading of
/// the line as the menu bar's field and the command palette) and shows where it
/// landed before asking the window to close.
@MainActor
@Observable
final class QuickCaptureModel {
  enum Phase: Equatable {
    /// Typing, or ready to retry after a failure was edited away.
    case editing
    /// The task is written; the window shows the list it landed in.
    case captured(listName: String)
    /// The write failed. The line stays so the user can retry.
    case failed(message: String)
  }

  /// The line being typed.
  var text = "" {
    didSet {
      if case .failed = phase, text != oldValue { phase = .editing }
    }
  }

  private(set) var phase = Phase.editing

  /// Bumped to ask the window's field for keyboard focus: at every
  /// presentation, and again once the window has become the key window (a
  /// request made while the window was still hidden may not take).
  private(set) var focusRequest = 0

  /// Bumped whenever the window's state is reset, by a new presentation or by
  /// Escape. A write still in flight from before the reset sees the change and
  /// leaves the window alone.
  private var generation = 0

  /// Asks the window to close once a capture's confirmation has been shown.
  var onFinish: (@MainActor () -> Void)?

  private let store: AppStore
  private let confirmationHold: Duration
  private var isSubmitting = false

  /// `confirmationHold` is how long the confirmation shows before the window
  /// closes.
  init(store: AppStore, confirmationHold: Duration = .milliseconds(800)) {
    self.store = store
    self.confirmationHold = confirmationHold
  }

  /// What the capture will create from the typed line, for the preview under
  /// the field.
  func preview() -> LorvexCapturePreview { store.quickAddPreview(text) }

  /// Starts a presentation. A line left half-typed when the window was
  /// dismissed is still there.
  func prepare() {
    focusRequest &+= 1
    generation &+= 1
    phase = .editing
    isSubmitting = false
  }

  /// Asks the window's field for keyboard focus.
  func requestFocus() {
    focusRequest &+= 1
  }

  /// Escape: throws the draft away, since the user does not want the line, and
  /// asks the window to close.
  func cancel() {
    generation &+= 1
    isSubmitting = false
    text = ""
    phase = .editing
    onFinish?()
  }

  /// Writes the typed line as a task and shows where it landed. A blank line
  /// does nothing, and a second Return while the write is under way is
  /// ignored.
  ///
  /// A failure stays in the window, with the line, so the user can retry; the
  /// store's own alert is not raised for it. A write that finishes after the
  /// window was dismissed or presented again is still a created task (its
  /// fan-out runs), but it leaves the new presentation's line and state alone,
  /// and its failure is left on the store for the main window's alert instead
  /// of being lost.
  func submit() async {
    guard !isSubmitting, phase == .editing || isFailed,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    isSubmitting = true
    let owner = generation
    let receipt = await store.commitCapture(text)
    if receipt != nil {
      // The fan-out (Spotlight, reminders, badge, widget, one sync cycle) runs
      // on its own time: the confirmation never waits for it.
      Task { await store.publishAfterTaskCreate() }
    }
    guard owner == generation else { return }
    guard let receipt else {
      isSubmitting = false
      phase = .failed(message: store.errorMessage ?? "")
      store.errorMessage = nil
      return
    }
    text = ""
    phase = .captured(listName: receipt.listName)
    try? await Task.sleep(for: confirmationHold)
    guard owner == generation else { return }
    isSubmitting = false
    onFinish?()
  }

  private var isFailed: Bool {
    if case .failed = phase { return true }
    return false
  }
}
