import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type RefObject,
} from 'react';
import { useQuery } from '@tanstack/react-query';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { getMcpServerStatus } from '@/lib/ipc/settings';
import { useLazyRef } from '@/lib/useLazyRef';
import {
  createMcpServerStatusQueryOptions,
  readMcpServerStatusData,
} from '@/lib/hooks/useMcpServerStatus.logic';
import { useI18n, type TranslationKey, type TranslationVars } from '@/lib/i18n';
import {
  getClaudeCodeConfigPathHint,
  getClaudeDesktopConfigPathHint,
  getCodexConfigPathHint,
} from '@/lib/platform/platformPaths';
import { safeWriteToClipboard } from '@/lib/platform/safeClipboard';
import { toast } from '@/lib/notifications/toast';
import type {
  AssistantMcpSetupModel,
  AssistantSnippetKey,
  McpAssistantSnippets,
} from '@/components/settings/assistant/types';
import {
  cleanupAssistantCopiedSnippetReset,
  createBrowserAssistantCopiedSnippetTimerHost,
  createAssistantCopiedSnippetRuntimeState,
  scheduleAssistantCopiedSnippetReset,
} from './copiedSnippet.runtime';

interface AssistantMcpControllerState {
  ready: boolean;
  mcp: AssistantMcpSetupModel;
}

interface UseAssistantMcpControllerArgs {
  supportsMcpHosting: boolean;
  settingsMountedRef: RefObject<boolean>;
  logAssistantSettingsError: (source: string, message: string, error: unknown) => void;
}

type FormatAssistantMcpMessage = (key: TranslationKey, vars?: TranslationVars) => string;

export function buildAssistantSnippets(
  mcpServerStatus: {
    resolved: boolean;
    command?: string | null;
    args?: string[] | null;
    cwd?: string | null;
  } | null,
  formatMessage: FormatAssistantMcpMessage,
): McpAssistantSnippets | null {
  const command = mcpServerStatus?.command;
  const args = mcpServerStatus?.args;
  if (!mcpServerStatus?.resolved || !command || !args) return null;

  const baseConfig: Record<string, unknown> = { command, args };
  if (mcpServerStatus.cwd) {
    baseConfig.cwd = mcpServerStatus.cwd;
  }

  const claudeDesktop = JSON.stringify({
    mcpServers: {
      lorvex: baseConfig,
    },
  }, null, 2);

  const claudeCode = JSON.stringify({
    mcpServers: {
      lorvex: {
        type: 'stdio',
        command,
        args,
      },
    },
  }, null, 2);

  const tomlValue = (value: string) =>
    `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  const codexLines = [
    '[mcp_servers.lorvex]',
    `command = ${tomlValue(command)}`,
    `args = [${args.map((item) => tomlValue(item)).join(', ')}]`,
  ];
  if (mcpServerStatus.cwd) {
    codexLines.push(`cwd = ${tomlValue(mcpServerStatus.cwd)}`);
  }
  codexLines.push('startup_timeout_sec = 20');
  codexLines.push('tool_timeout_sec = 120');

  const argsStr = args.length > 0 ? args.map((a) => JSON.stringify(a)).join(', ') : '';
  const codexArgsStr = args.map((a) => tomlValue(a)).join(', ');
  const jsonCommand = command.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const codexCommand = tomlValue(command);
  const cwdNote = mcpServerStatus.cwd
    ? `\n- ${formatMessage('settings.mcpSetupPrompt.cwdNote', { cwd: mcpServerStatus.cwd })}`
    : '';

  const claudeDesktopPath = getClaudeDesktopConfigPathHint();
  const claudeCodePath = getClaudeCodeConfigPathHint();
  const codexPath = getCodexConfigPathHint();

  const setupPrompt = formatMessage('settings.mcpSetupPrompt.template', {
    argsStr,
    claudeCodePath,
    claudeDesktopPath,
    codexArgsStr,
    codexCommand,
    codexPath,
    command,
    cwdNote,
    jsonCommand,
  });

  return {
    claudeDesktop,
    claudeCode,
    codex: codexLines.join('\n'),
    setupPrompt,
    usesCwd: Boolean(mcpServerStatus.cwd),
  };
}

export function useAssistantMcpController({
  supportsMcpHosting,
  settingsMountedRef,
  logAssistantSettingsError,
}: UseAssistantMcpControllerArgs): AssistantMcpControllerState {
  const { t, format } = useI18n();
  const [copiedSnippet, setCopiedSnippet] = useState<AssistantSnippetKey | null>(null);

  const copiedSnippetRuntimeStateRef = useLazyRef(() => createAssistantCopiedSnippetRuntimeState());
  const copiedSnippetTimerHostRef = useLazyRef(() => createBrowserAssistantCopiedSnippetTimerHost());

  // hoist the MCP server status into an app-level
  // TanStack query keyed under QK.mcpServerStatus. Both this
  // controller (for the snippets + status UI in Settings → Assistant
  // MCP) and the empty-state panels on ChangelogView / AIMemoryView /
  // DailyReviewView / HabitsView read the same cache entry, so they
  // stay in lock-step without re-issuing `get_mcp_server_status` per
  // view.
  const {
    data: mcpServerStatusData,
    error: mcpStatusQueryError,
    isFetched: mcpStatusFetched,
  } = useQuery(
    createMcpServerStatusQueryOptions(supportsMcpHosting, getMcpServerStatus),
  );
  const mcpServerStatus = readMcpServerStatusData(mcpServerStatusData);
  const mcpStatusError = mcpStatusQueryError
    ? toIpcErrorMessage(mcpStatusQueryError)
    : null;
  const ready = supportsMcpHosting ? mcpStatusFetched : true;

  useEffect(() => {
    if (mcpStatusQueryError) {
      logAssistantSettingsError(
        'frontend.settings.mcp.status',
        'Load MCP server status failed',
        mcpStatusQueryError,
      );
    }
  }, [mcpStatusQueryError, logAssistantSettingsError]);

  const copySnippet = useCallback(async (key: AssistantSnippetKey, text: string) => {
    const result = await safeWriteToClipboard(text, 'frontend.settings.mcp.copy_snippet');
    if (!result.ok) {
      logAssistantSettingsError('frontend.settings.mcp.copy_snippet', 'Copy MCP snippet failed', result.error);
      // pair the error with the recovery hint when the helper
      // surfaces one (permission/sandbox failure → manual Cmd+C path).
      toast.errorWithDetail(result.error, t('settings.clipboardCopyFailed'));
      if (result.recoveryHint) {
        toast.info(t('settings.clipboardCopyHint'));
      }
      return;
    }
    if (!settingsMountedRef.current) return;
    setCopiedSnippet(key);
    scheduleAssistantCopiedSnippetReset({
      delayMs: 2000,
      isMounted: () => settingsMountedRef.current,
      key,
      setCopiedSnippet,
      state: copiedSnippetRuntimeStateRef.current,
      timerHost: copiedSnippetTimerHostRef.current,
    });
    // *Ref values are stable MutableRefObjects from useLazyRef.
  }, [copiedSnippetRuntimeStateRef, copiedSnippetTimerHostRef, logAssistantSettingsError, settingsMountedRef, t]);

  useEffect(() => {
    return () => {
      cleanupAssistantCopiedSnippetReset(
        // We deliberately read `.current` at cleanup time so we tear
        // down whichever timer is currently armed.
        // eslint-disable-next-line react-hooks/exhaustive-deps
        copiedSnippetRuntimeStateRef.current,
        // eslint-disable-next-line react-hooks/exhaustive-deps
        copiedSnippetTimerHostRef.current,
      );
    };
    // *Ref values are stable MutableRefObjects from useLazyRef.
  }, [copiedSnippetRuntimeStateRef, copiedSnippetTimerHostRef]);

  const mcpAssistantSnippets = useMemo(
    () => buildAssistantSnippets(mcpServerStatus, format),
    [format, mcpServerStatus],
  );

  return {
    ready,
    mcp: {
      mcpServerStatus,
      mcpStatusError,
      mcpAssistantSnippets,
      copiedSnippet,
      onCopySnippet: copySnippet,
    },
  };
}
