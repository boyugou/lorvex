#if DEBUG && os(iOS)
  import UIKit

  /// Dev/QA only: measures, between ``begin(maximumFramesPerSecond:)`` and
  /// ``end()``, how late frames arrived and how long the main thread stayed
  /// busy, for ``DebugInteractionDriver``.
  ///
  /// Two measures, because they answer different questions:
  ///
  /// - **Late frames.** A `CADisplayLink` callback runs on the main thread once
  ///   per display refresh, and the time between two callbacks beyond one
  ///   refresh interval is hitch time. A frame is late when the main thread was
  ///   busy, and also when the render server was: in the simulator, which draws
  ///   sheets and translucent materials on the Mac's CPU and GPU, most late
  ///   frames are of the second kind and say little about a device.
  /// - **Busy main thread.** A run-loop observer times each stretch of work
  ///   the main thread does between two waits for events. A stretch longer
  ///   than one refresh interval held at least one frame back, whatever the
  ///   render server did, so this is the measure of the app's own code (the
  ///   signal Apple's hang detection uses).
  ///
  /// Every second, and at the end, the probe rewrites
  /// `<tmp>/lorvex-frame-probe-<label>.txt` in the app's data container with
  /// one line,
  /// `FRAMEPROBE|<label>|seconds=…|frames=…|hitches=…|hitch_ms=…|worst_ms=…|busy_ms=…|long_busy=…|long_busy_over_ms=…|worst_busy_ms=…|hz=…|done=<0|1>`,
  /// so a run cut short still leaves its totals. `busy_ms` is all main-thread
  /// work; `long_busy` counts the stretches longer than one refresh interval
  /// and `long_busy_over_ms` sums what they ran past it.
  @MainActor
  final class DebugFrameProbe: NSObject {
    private let label: String
    private let file: URL
    private var link: CADisplayLink?
    private var observer: CFRunLoopObserver?
    private var startedAt: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval?
    private var lastWrite: CFTimeInterval = 0
    private var frames = 0
    private var hitches = 0
    private var hitchTime: CFTimeInterval = 0
    private var worstInterval: CFTimeInterval = 0
    private var refreshInterval: CFTimeInterval = 1.0 / 60
    private var busySince: CFTimeInterval?
    private var busyTime: CFTimeInterval = 0
    private var longBusy = 0
    private var longBusyOver: CFTimeInterval = 0
    private var worstBusy: CFTimeInterval = 0

    init(label: String) {
      self.label = label
      file = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("lorvex-frame-probe-\(label).txt")
    }

    func begin(maximumFramesPerSecond: Int) {
      try? FileManager.default.removeItem(at: file)
      startedAt = CACurrentMediaTime()
      let rate = Float(maximumFramesPerSecond)
      let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
      link.add(to: .main, forMode: .common)
      self.link = link

      // The observer runs on the main thread, in the main run loop, so it is
      // already on the main actor.
      let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
      let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) {
        [weak self] _, activity in
        MainActor.assumeIsolated { self?.runLoop(activity) }
      }
      CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
      self.observer = observer
      busySince = startedAt
    }

    func end() {
      link?.invalidate()
      link = nil
      if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
      observer = nil
      runLoop(.beforeWaiting)
      write(seconds: CACurrentMediaTime() - startedAt, done: true)
    }

    private func runLoop(_ activity: CFRunLoopActivity) {
      let now = CACurrentMediaTime()
      if activity == .afterWaiting {
        busySince = now
        return
      }
      guard let since = busySince else { return }
      busySince = nil
      let span = now - since
      busyTime += span
      worstBusy = max(worstBusy, span)
      if span > refreshInterval {
        longBusy += 1
        longBusyOver += span - refreshInterval
      }
    }

    @objc private func tick(_ link: CADisplayLink) {
      let now = link.timestamp
      let expected = link.targetTimestamp - link.timestamp
      if expected > 0 { refreshInterval = expected }
      if let lastTimestamp {
        let interval = now - lastTimestamp
        frames += 1
        worstInterval = max(worstInterval, interval)
        // Half an interval of slack absorbs timer jitter; anything later is a
        // missed refresh.
        if interval > refreshInterval * 1.5 {
          hitches += 1
          hitchTime += interval - refreshInterval
        }
      }
      lastTimestamp = now
      if now - lastWrite >= 1 {
        lastWrite = now
        write(seconds: now - startedAt, done: false)
      }
    }

    private func write(seconds: CFTimeInterval, done: Bool) {
      let line = String(
        format:
          "FRAMEPROBE|%@|seconds=%.2f|frames=%d|hitches=%d|hitch_ms=%.1f|worst_ms=%.1f|busy_ms=%.1f|long_busy=%d|long_busy_over_ms=%.1f|worst_busy_ms=%.1f|hz=%.0f|done=%d\n",
        label, seconds, frames, hitches, hitchTime * 1000, worstInterval * 1000,
        busyTime * 1000, longBusy, longBusyOver * 1000, worstBusy * 1000,
        1 / refreshInterval, done ? 1 : 0)
      try? line.write(to: file, atomically: true, encoding: .utf8)
    }
  }
#endif
