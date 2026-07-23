export interface NotificationPermissionPromptPlugin {
  isPermissionGranted: () => Promise<boolean>;
  requestPermission: () => Promise<'granted' | 'denied' | 'default' | string>;
}

interface NotificationPermissionPromptRuntimeState {
  launched: boolean;
}

export type NotificationPermissionPromptCancellationProbe = () => boolean;

interface NotificationPermissionPromptRuntimeDeps {
  confirmPrompt: () => Promise<boolean>;
  enabled: boolean;
  getPrompted: () => Promise<boolean>;
  loadNotificationPlugin: () => Promise<NotificationPermissionPromptPlugin>;
  refreshNotificationPermissionCache: () => void;
  reportPromptError: (error: unknown) => void;
  setGranted: (
    granted: boolean,
    isCancelled: NotificationPermissionPromptCancellationProbe,
  ) => Promise<void>;
  setPrompted: (
    prompted: boolean,
    isCancelled: NotificationPermissionPromptCancellationProbe,
  ) => Promise<void>;
  state: NotificationPermissionPromptRuntimeState;
}

interface NotificationPermissionPromptRuntimeHandle {
  dispose: () => void;
}

export function installNotificationPermissionPromptRuntime(
  deps: NotificationPermissionPromptRuntimeDeps,
): NotificationPermissionPromptRuntimeHandle {
  if (!deps.enabled || deps.state.launched) {
    return { dispose: () => {} };
  }

  let cancelled = false;
  const isCancelled = () => cancelled;

  const runPrompt = async (): Promise<void> => {
    try {
      const prompted = await deps.getPrompted();
      if (prompted || cancelled) return;

      const notification = await deps.loadNotificationPlugin();
      if (cancelled) return;
      const grantedBeforePrompt = await notification.isPermissionGranted();
      if (cancelled) return;

      if (grantedBeforePrompt) {
        await persistPromptResult(deps, true, isCancelled);
        return;
      }

      const accepted = await deps.confirmPrompt();
      if (cancelled) return;

      if (!accepted) {
        return;
      }

      const response = await notification.requestPermission();
      if (cancelled) return;
      const granted = response === 'granted';
      deps.refreshNotificationPermissionCache();
      await persistPromptResult(deps, granted, isCancelled);
    } catch (error) {
      if (!cancelled) {
        deps.reportPromptError(error);
      }
    }
  };

  deps.state.launched = true;
  void runPrompt();

  return {
    dispose: () => {
      cancelled = true;
    },
  };
}

async function persistPromptResult(
  deps: NotificationPermissionPromptRuntimeDeps,
  granted: boolean,
  isCancelled: NotificationPermissionPromptCancellationProbe,
): Promise<void> {
  if (isCancelled()) return;

  await Promise.all([
    deps.setPrompted(true, isCancelled),
    deps.setGranted(granted, isCancelled),
  ]);
}
