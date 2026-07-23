import {
  normalizeAssistantUiCommand,
  type AssistantUiCommand,
} from '@/lib/assistantUiCommand';
import type { DeviceStateKey } from '@/lib/preferences/keys';
import { tryParseOptionalJson } from '@/lib/security/jsonParse';
import {
  ASSISTANT_UI_COMMAND_KEY,
  ASSISTANT_UI_HANDLED_ID_KEY,
} from '@/app-shell/support';

type AssistantUiPollingTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface AssistantUiPollingTimerHost {
  clearTimeout: (handle: AssistantUiPollingTimerHandle) => void;
  setTimeout: (
    callback: () => void,
    delayMs: number,
  ) => AssistantUiPollingTimerHandle;
}

export interface AssistantUiPollingRuntimeOptions extends AssistantUiPollingTimerHost {
  addVisibilityListener: ((handler: () => void) => (() => void)) | null;
  getVisibilityState: () => DocumentVisibilityState | 'visible' | 'hidden';
  poll: (isCancelled: () => boolean) => Promise<void>;
}

const ASSISTANT_UI_POLL_DELAY_MS = 1500;

type AssistantUiReportClientError = (
  source: string,
  message: string,
  error?: unknown,
  details?: string,
  level?: 'debug' | 'info' | 'warn' | 'error',
) => void;

interface AssistantUiCommandPollOptions {
  executeCommand: (command: AssistantUiCommand) => Promise<void>;
  getDeviceState: (key: DeviceStateKey) => Promise<string | null>;
  getHandledCommandId: () => string | null;
  isCancelled: () => boolean;
  reportClientError: AssistantUiReportClientError;
  setDeviceState: (key: DeviceStateKey, value: string | null) => Promise<void>;
  setHandledCommandId: (commandId: string) => void;
}

export function createBrowserAssistantUiPollingTimerHost(): AssistantUiPollingTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export async function pollAssistantUiCommand(options: AssistantUiCommandPollOptions): Promise<void> {
  try {
    const [rawCommand, rawHandledId] = await Promise.all([
      options.getDeviceState(ASSISTANT_UI_COMMAND_KEY),
      options.getDeviceState(ASSISTANT_UI_HANDLED_ID_KEY),
    ]);
    if (options.isCancelled()) return;

    const parsedCommand = tryParseOptionalJson<unknown>(rawCommand);
    if (rawCommand && parsedCommand.error) {
      options.reportClientError(
        'app.assistantUi.commandParse',
        'Failed to parse assistant UI command preference',
        parsedCommand.error,
        rawCommand,
        'warn',
      );
      if (!options.isCancelled()) {
        await options.setDeviceState(ASSISTANT_UI_COMMAND_KEY, null);
      }
      return;
    }

    const command = normalizeAssistantUiCommand(parsedCommand.value);
    if (rawCommand && parsedCommand.value !== null && !command) {
      options.reportClientError(
        'app.assistantUi.commandNormalize',
        'Ignored structurally invalid assistant UI command payload',
        undefined,
        rawCommand,
        'warn',
      );
      if (!options.isCancelled()) {
        await options.setDeviceState(ASSISTANT_UI_COMMAND_KEY, null);
      }
      return;
    }

    const parsedHandledId = tryParseOptionalJson<unknown>(rawHandledId);
    if (rawHandledId && parsedHandledId.error) {
      options.reportClientError(
        'app.assistantUi.handledIdParse',
        'Failed to parse assistant UI handled-id preference',
        parsedHandledId.error,
        rawHandledId,
        'warn',
      );
      if (!options.isCancelled()) {
        await options.setDeviceState(ASSISTANT_UI_HANDLED_ID_KEY, null);
      }
      return;
    }

    const handledId = typeof parsedHandledId.value === 'string' ? parsedHandledId.value : null;
    if (rawHandledId && parsedHandledId.value !== null && handledId === null) {
      options.reportClientError(
        'app.assistantUi.handledIdNormalize',
        'Ignored structurally invalid assistant UI handled-id payload',
        undefined,
        rawHandledId,
        'warn',
      );
      if (!options.isCancelled()) {
        await options.setDeviceState(ASSISTANT_UI_HANDLED_ID_KEY, null);
      }
      return;
    }

    if (handledId && handledId !== options.getHandledCommandId()) {
      options.setHandledCommandId(handledId);
    }

    if (
      command
      && command.command_id !== handledId
      && command.command_id !== options.getHandledCommandId()
    ) {
      if (options.isCancelled()) return;
      await options.executeCommand(command);
      if (options.isCancelled()) return;
      options.setHandledCommandId(command.command_id);
      await options.setDeviceState(ASSISTANT_UI_HANDLED_ID_KEY, command.command_id);
    }
  } catch (error) {
    if (!options.isCancelled()) {
      options.reportClientError('app.assistantUi.poll', 'Assistant UI command poll failed', error);
    }
  }
}

export function installAssistantUiPollingRuntime(
  options: AssistantUiPollingRuntimeOptions,
): () => void {
  let cancelled = false;
  let timer: AssistantUiPollingTimerHandle | null = null;

  const clearPendingTimer = () => {
    if (timer === null) {
      return;
    }
    options.clearTimeout(timer);
    timer = null;
  };

  const scheduleNextTick = () => {
    if (cancelled || options.getVisibilityState() !== 'visible') return;
    timer = options.setTimeout(() => {
      timer = null;
      void tick();
    }, ASSISTANT_UI_POLL_DELAY_MS);
  };

  const tick = async () => {
    try {
      await options.poll(() => cancelled);
    } finally {
      scheduleNextTick();
    }
  };

  const startIfVisible = () => {
    if (cancelled || timer !== null) return;
    if (options.getVisibilityState() !== 'visible') return;
    void tick();
  };

  const removeVisibilityListener = options.addVisibilityListener?.(() => {
    if (options.getVisibilityState() === 'visible') {
      startIfVisible();
      return;
    }
    clearPendingTimer();
  }) ?? (() => {});

  startIfVisible();

  return () => {
    cancelled = true;
    clearPendingTimer();
    removeVisibilityListener();
  };
}
