import type { McpServerStatus } from '@/lib/ipc/settings';
import type { TranslationKey } from '@/lib/i18n';

export interface McpStatusDiagnostic {
  detail: string;
  summaryKey: TranslationKey;
  tone: 'danger' | 'warning';
}

export function shouldPromptCliMcpTakeover(status: McpServerStatus | null): boolean {
  return Boolean(status?.cli_detected && status.mcp_host_authority !== 'cli');
}

export function shouldShowAppMcpSnippets(status: McpServerStatus | null): boolean {
  return !shouldPromptCliMcpTakeover(status) && status?.mcp_host_authority !== 'cli';
}

export function buildMcpStatusDiagnostics(
  statusLoadError: string | null,
  serverError: string | null,
): McpStatusDiagnostic[] {
  const diagnostics: McpStatusDiagnostic[] = [];
  if (statusLoadError) {
    diagnostics.push({
      detail: statusLoadError,
      summaryKey: 'settings.mcpStatusLoadFailed',
      tone: 'danger',
    });
  }
  if (serverError) {
    diagnostics.push({
      detail: serverError,
      summaryKey: 'settings.mcpStatusServerError',
      tone: 'warning',
    });
  }
  return diagnostics;
}
