import { useCallback, useEffect, useRef } from 'react';

import {
  assistantCommandViewToAppView,
  type AssistantUiCommand,
} from '@/lib/assistantUiCommand';
import { assertNever } from '@/lib/errors/assertNever';
import { reportClientError } from '@/lib/errors/errorLogging';
import { getDeviceState, setDeviceState } from '@/lib/ipc/settings';
import type { Locale } from '@/lib/i18n';
import type { AppearanceProfile, ThemeMode } from '@/lib/theme';
import type { View } from '@/lib/types';
import {
  createBrowserAssistantUiPollingTimerHost,
  installAssistantUiPollingRuntime,
  pollAssistantUiCommand,
} from './useAssistantUiRuntime.runtime';

const assistantUiPollingTimerHost = createBrowserAssistantUiPollingTimerHost();

interface UseAssistantUiRuntimeOptions {
  supportsAssistantCommandPolling: boolean;
  navigateToView: (target: View) => View;
  setAppearanceProfile: (profile: AppearanceProfile) => void;
  setLocale: (locale: Locale) => void;
  setMode: (mode: ThemeMode) => void;
  setSelectedTaskId: (taskId: string | null) => void;
  applySystemLocale: () => void;
}

export function useAssistantUiRuntime({
  supportsAssistantCommandPolling,
  navigateToView,
  setAppearanceProfile,
  setLocale,
  setMode,
  setSelectedTaskId,
  applySystemLocale,
}: UseAssistantUiRuntimeOptions) {
  const assistantUiHandledCommandIdRef = useRef<string | null>(null);

  const executeAssistantUiCommand = useCallback(async (command: AssistantUiCommand) => {
    switch (command.action) {
      case 'enter_focus_mode': {
        // Focus mode is retired; the action is acknowledged so the
        // assistant command is marked handled, but it no longer
        // launches a focus window.
        return;
      }
      case 'exit_focus_mode': {
        // Focus mode is retired; nothing to exit.
        return;
      }
      case 'focus_task': {
        if (typeof command.task_id !== 'string') return;
        // Focus mode is retired; bring the referenced task into view
        // on Today instead of opening a focus window.
        const targetView = navigateToView({ type: 'today' });
        setSelectedTaskId(targetView.type === 'today' ? command.task_id : null);
        return;
      }
      case 'open_task': {
        if (typeof command.task_id !== 'string') return;
        navigateToView({ type: 'today' });
        setSelectedTaskId(command.task_id);
        return;
      }
      case 'switch_view': {
        const next = assistantCommandViewToAppView(command.view, command.list_id);
        if (!next) return;
        const resolved = navigateToView(next);
        if (resolved.type !== 'list') {
          setSelectedTaskId(null);
        }
        return;
      }
      case 'set_theme': {
        if (!command.theme) return;
        setMode(command.theme);
        return;
      }
      case 'set_appearance_profile': {
        if (!command.appearance_profile) return;
        setAppearanceProfile(command.appearance_profile);
        return;
      }
      case 'set_language': {
        if (!command.language) return;
        if (command.language === 'system') {
          applySystemLocale();
        } else {
          setLocale(command.language);
        }
        return;
      }
      default:
        return assertNever(command.action, 'assistant UI action');
    }
  }, [
    navigateToView,
    setAppearanceProfile,
    setLocale,
    setMode,
    setSelectedTaskId,
    applySystemLocale,
  ]);

  useEffect(() => {
    if (!supportsAssistantCommandPolling) return;

    return installAssistantUiPollingRuntime({
      addVisibilityListener: typeof document === 'undefined'
        ? null
        : (handler) => {
            document.addEventListener('visibilitychange', handler);
            return () => document.removeEventListener('visibilitychange', handler);
          },
      getVisibilityState: () => (typeof document === 'undefined' ? 'visible' : document.visibilityState),
      poll: (isCancelled) => pollAssistantUiCommand({
        executeCommand: executeAssistantUiCommand,
        getDeviceState,
        getHandledCommandId: () => assistantUiHandledCommandIdRef.current,
        isCancelled,
        reportClientError,
        setDeviceState,
        setHandledCommandId: (commandId) => {
          assistantUiHandledCommandIdRef.current = commandId;
        },
      }),
      ...assistantUiPollingTimerHost,
    });
  }, [executeAssistantUiCommand, supportsAssistantCommandPolling]);
}
