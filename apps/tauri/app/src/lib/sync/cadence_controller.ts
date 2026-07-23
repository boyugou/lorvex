/**
 * Event-driven sync cadence controller.
 *
 * when the device is offline, the previous implementation
 * still woke the cadence timer every `SYNC_LOOP_OFFLINE_MS` (5 min)
 * just to confirm it was still offline. On airplane mode / low-power
 * that wastes radio + battery. This controller gates the scheduler so
 * that while `navigator.onLine === false` no timer is installed at
 * all — we resume on the `online` / `connection.change` events.
 *
 * The controller is deliberately decoupled from React + the DOM so
 * that the logic tests under `scripts/tests/runtime/` can drive it
 * with a virtual clock and a scripted online/offline flag. The
 * `useBackgroundSyncBackend` hook composes this controller with the
 * real `window.setTimeout`, `navigator.onLine`, and event listeners.
 */
interface CadenceHost {
  /** Current epoch millis — injectable for virtual clocks in tests. */
  now(): number;
  /** True when the device reports network reachability. */
  isOnline(): boolean;
  /** Schedule `callback` to run after `delayMs`. Returns a cancel fn. */
  setTimeout(callback: () => void, delayMs: number): () => void;
  /** Execute the tick. Returns when the tick has fully settled. */
  runTick(): Promise<void> | void;
}

interface CadenceController {
  /** Schedule the next tick after `delayMs`. No-op when offline. */
  schedule(delayMs: number): void;
  /** Cancel any pending cadence timer without scheduling a replacement. */
  cancel(): void;
  /** True when a cadence timer is currently armed. */
  hasPendingTick(): boolean;
  /**
   * Handler for the `online` event: always attempts a sync, even if
   * the normal resume throttle would otherwise suppress it.
   */
  handleOnline(): void;
  /**
   * Handler for the `offline` event: cancels the pending timer. The
   * controller is now dormant until `online` or `connection.change`
   * re-arms it.
   */
  handleOffline(): void;
  /**
   * Handler for `navigator.connection`'s `change` event. Some laptops
   * transition Wi-Fi ↔ cellular without `navigator.onLine` flipping
   * (e.g. tethering), so when the connection changes and we're still
   * online, we attempt a fresh sync.
   */
  handleConnectionChange(): void;
  /** Dispose: cancels the timer and marks the controller shut down. */
  dispose(): void;
}

interface CreateCadenceControllerOptions {
  host: CadenceHost;
  /** Invoked when `online` / `connection.change` requests a sync. */
  onResumeRequested: () => void;
}

export function createCadenceController(
  options: CreateCadenceControllerOptions,
): CadenceController {
  const { host, onResumeRequested } = options;
  let cancelTimer: (() => void) | undefined;
  let disposed = false;

  const cancel = (): void => {
    if (cancelTimer) {
      cancelTimer();
      cancelTimer = undefined;
    }
  };

  const schedule = (delayMs: number): void => {
    if (disposed) return;
    cancel();
    // Suspend the cadence timer entirely while offline. This is the
    // core of a sync tick that starts offline is
    // guaranteed to short-circuit without touching the network, so
    // waking the CPU / radio every 5 min to schedule it is pure
    // waste. The `online` and `connection.change` listeners re-arm
    // the scheduler the moment connectivity returns.
    if (!host.isOnline()) return;
    cancelTimer = host.setTimeout(() => {
      cancelTimer = undefined;
      void host.runTick();
    }, Math.max(0, delayMs));
  };

  const handleOnline = (): void => {
    if (disposed) return;
    onResumeRequested();
  };

  const handleOffline = (): void => {
    if (disposed) return;
    cancel();
  };

  const handleConnectionChange = (): void => {
    if (disposed) return;
    // Only resume when the browser reports we still have connectivity.
    // If a `change` event fires because the last interface dropped,
    // `navigator.onLine` will be false and `offline` will follow —
    // there is nothing for us to do here.
    if (!host.isOnline()) return;
    onResumeRequested();
  };

  const hasPendingTick = (): boolean => cancelTimer !== undefined;

  const dispose = (): void => {
    disposed = true;
    cancel();
  };

  return {
    schedule,
    cancel,
    hasPendingTick,
    handleOnline,
    handleOffline,
    handleConnectionChange,
    dispose,
  };
}
