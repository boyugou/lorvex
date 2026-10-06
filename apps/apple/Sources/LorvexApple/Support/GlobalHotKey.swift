import AppKit
import Carbon.HIToolbox

/// Makes a ``QuickCaptureShortcut`` fire from any app, whether or not Lorvex is
/// frontmost. A protocol so the controller that owns the shortcut is tested
/// without registering a real system-wide key.
@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
  /// Registers `shortcut` to run `handler`, replacing the previous registration.
  /// Returns `false` when the system refuses the chord because another app owns
  /// it. `.off` removes the registration and returns `true`.
  func register(_ shortcut: QuickCaptureShortcut, handler: @escaping @MainActor () -> Void) -> Bool
}

/// One system-wide hot key on the Carbon event manager: the public API that
/// delivers a key chord to an app that is not frontmost without asking for
/// Accessibility access, and one the Mac App Store allows.
@MainActor
final class CarbonGlobalHotKey: GlobalHotKeyRegistering {
  /// Tags this app's hot key among the system's: "LRVX".
  private static let signature: OSType = 0x4C52_5658
  private static let identifier: UInt32 = 1

  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var handler: (@MainActor () -> Void)?

  func register(_ shortcut: QuickCaptureShortcut, handler: @escaping @MainActor () -> Void) -> Bool {
    unregister()
    guard let chord = shortcut.chord else { return true }
    installEventHandlerIfNeeded()
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      chord.keyCode, chord.modifiers,
      EventHotKeyID(signature: Self.signature, id: Self.identifier),
      GetApplicationEventTarget(), 0, &reference)
    guard status == noErr, let reference else { return false }
    hotKey = reference
    self.handler = handler
    return true
  }

  private func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    handler = nil
  }

  /// Installs the application-wide handler for hot-key presses once. The event
  /// manager delivers application-target events on the main thread, so the
  /// handler runs main-actor code directly.
  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else { return }
    var pressed = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, event, context in
      guard let event, let context else { return OSStatus(eventNotHandledErr) }
      var pressedKey = EventHotKeyID()
      let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &pressedKey)
      guard status == noErr, pressedKey.signature == CarbonGlobalHotKey.signature,
        pressedKey.id == CarbonGlobalHotKey.identifier
      else { return OSStatus(eventNotHandledErr) }
      let hotKey = Unmanaged<CarbonGlobalHotKey>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated { hotKey.handler?() }
      return noErr
    }
    InstallEventHandler(
      GetApplicationEventTarget(), callback, 1, &pressed,
      Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
  }
}
