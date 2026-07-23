import { useCallback, useState } from 'react';
import { revealItemInDir } from '@tauri-apps/plugin-opener';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { Button } from '@/components/ui/Button';
import { TonalButton } from '@/components/ui/TonalButton';
import {
  getClaudeCodeConfigPathHint,
  getClaudeDesktopConfigPathHint,
  getCodexConfigPathHint,
} from '@/lib/platform/platformPaths';
import { SettingsSection } from '../SettingsPrimitives';
import {
  buildMcpStatusDiagnostics,
  shouldPromptCliMcpTakeover,
  shouldShowAppMcpSnippets,
} from './McpSetupSection.logic';
import type { AssistantMcpSetupModel } from './types';

interface McpSetupSectionProps {
  mcp: AssistantMcpSetupModel;
}

export function McpSetupSection({
  mcp,
}: McpSetupSectionProps) {
  const { t } = useI18n();
  const [showManual, setShowManual] = useState(false);
  const claudeDesktopConfigPath = getClaudeDesktopConfigPathHint();
  const claudeCodeConfigPath = getClaudeCodeConfigPathHint();
  const codexConfigPath = getCodexConfigPathHint();

  // 'Reveal in Finder / Explorer' so a non-technical user
  // can jump to the parent directory of the config file instead of
  // staring at a hidden path (~/Library/... on macOS, %APPDATA% on
  // Windows are Finder/Explorer-hidden by default). Failure to open
  // is reported quietly — the UI is diagnostic-only.
  const revealConfigPath = useCallback(async (path: string, label: string) => {
    try {
      await revealItemInDir(path);
    } catch (error) {
      reportClientError(
        'settings.mcp.revealConfigPath',
        `Failed to reveal MCP config path for ${label}`,
        error,
        path,
        'warn',
      );
    }
  }, []);
  const {
    mcpServerStatus,
    mcpStatusError,
    mcpAssistantSnippets,
    copiedSnippet,
    onCopySnippet,
  } = mcp;
  const cliIsAuthority = mcpServerStatus?.mcp_host_authority === 'cli';
  const cliShouldTakeAuthority = shouldPromptCliMcpTakeover(mcpServerStatus);
  const showAppMcpSnippets = shouldShowAppMcpSnippets(mcpServerStatus);
  const mcpStatusDiagnostics = buildMcpStatusDiagnostics(
    mcpStatusError,
    mcpServerStatus?.error ?? null,
  );

  return (
    <SettingsSection
      title={t('settings.mcpConnect')}
      description={t('settings.mcpConnectDesc')}
    >
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2 text-xs">
          {cliIsAuthority ? (
            <span className="px-2 py-1 rounded-r-control bg-accent/10 text-accent">
              {t('settings.mcpHostCli')}
            </span>
          ) : (
            <span
              className={`px-2 py-1 rounded-r-control ${
                mcpServerStatus?.resolved ? 'chip-success' : 'chip-warning'
              }`}
            >
              {mcpServerStatus?.resolved ? t('settings.mcpConfigured') : t('settings.mcpNotConfigured')}
            </span>
          )}
        </div>

        {/* CLI is authority: show CLI command reference, suppress App snippets */}
        {cliIsAuthority && (
          <div className="bg-accent/5 border border-accent/20 rounded-r-card p-3.5 space-y-1.5">
            <p className="text-xs text-text-secondary">{t('settings.mcpHostCliDesc')}</p>
            <pre className="text-xs font-mono text-accent select-all">lorvex mcp install --for all</pre>
          </div>
        )}

        {/* CLI detected but not authority: suggest setting up */}
        {cliShouldTakeAuthority && (
          <div className="bg-surface-1 border border-surface-3 rounded-r-card p-3.5 space-y-1.5">
            <p className="text-xs text-text-muted">{t('settings.mcpHostCliDetected')}</p>
            <pre className="text-xs font-mono text-text-secondary select-all">lorvex mcp install --for all</pre>
          </div>
        )}

        {mcpStatusDiagnostics.map((diagnostic) => (
          <details
            key={diagnostic.summaryKey}
            className={`text-xs group ${diagnostic.tone === 'danger' ? 'text-danger' : 'text-warning'}`}
          >
            <summary className="cursor-pointer select-none">
              {t(diagnostic.summaryKey)}
            </summary>
            <p className="mt-1 text-text-muted wrap-break-word">
              <span className="font-medium">{t('settings.mcpStatusTechnicalDetails')}:</span>{' '}
              {diagnostic.detail}
            </p>
          </details>
        ))}

        {/* App snippets: only show when CLI is not the preferred local host */}
        {!showAppMcpSnippets ? null : mcpAssistantSnippets ? (
          <div className="space-y-4">
            {/* Primary action: copy setup prompt */}
            <div className="bg-surface-1 border border-accent/20 rounded-r-card p-3.5 space-y-2.5">
              <div className="flex items-center justify-between gap-2">
                <p className="text-xs text-text-secondary">{t('settings.mcpCopyPromptDesc')}</p>
                <button
                  type="button"
                  onClick={() => {
                    void onCopySnippet('setupPrompt', mcpAssistantSnippets.setupPrompt);
                  }}
                  className="shrink-0 text-sm font-medium px-4 py-1.5 rounded-r-control bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-colors focus-ring-strong"
                >
                  {copiedSnippet === 'setupPrompt' ? t('settings.mcpPromptCopied') : t('settings.mcpCopyPrompt')}
                </button>
              </div>
            </div>

            {/* Manual config toggle */}
            <button
              type="button"
              onClick={() => setShowManual((prev) => !prev)}
              className="text-xs text-text-muted hover:text-text-secondary transition-colors focus-ring-soft rounded-r-control px-1"
            >
              {showManual ? t('settings.mcpHideManualConfig') : t('settings.mcpShowManualConfig')}
            </button>

            {/* Collapsible manual config snippets */}
            {showManual && (
              <div className="space-y-2">
                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs text-text-secondary">{t('settings.mcpClaudeDesktop')}</p>
                    <TonalButton
                      tone="accent"
                      onClick={() => {
                        void onCopySnippet('claudeDesktop', mcpAssistantSnippets.claudeDesktop);
                      }}
                    >
                      {copiedSnippet === 'claudeDesktop' ? t('common.copied') : t('common.copy')}
                    </TonalButton>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs text-text-muted min-w-0 flex-1 truncate">
                      {t('settings.mcpConfigPath')}: <span className="font-mono">{claudeDesktopConfigPath}</span>
                    </p>
                    <Button
                      variant="outline"
                      onClick={() => {
                        void revealConfigPath(claudeDesktopConfigPath, 'claudeDesktop');
                      }}
                    >
                      {t('settings.mcpRevealConfig')}
                    </Button>
                  </div>
                  <p className="text-2xs text-text-muted leading-relaxed">
                    {t('settings.mcpConfigInstruction')}
                  </p>
                  <pre className="bg-surface-1 border border-surface-3 rounded-r-card p-3 text-xs text-text-secondary whitespace-pre-wrap wrap-break-word font-mono select-all">
                    {mcpAssistantSnippets.claudeDesktop}
                  </pre>
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs text-text-secondary">{t('settings.mcpClaudeCode')}</p>
                    <TonalButton
                      tone="accent"
                      onClick={() => {
                        void onCopySnippet('claudeCode', mcpAssistantSnippets.claudeCode);
                      }}
                    >
                      {copiedSnippet === 'claudeCode' ? t('common.copied') : t('common.copy')}
                    </TonalButton>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs text-text-muted min-w-0 flex-1 truncate">
                      {t('settings.mcpConfigPath')}: <span className="font-mono">{claudeCodeConfigPath}</span>
                    </p>
                    <Button
                      variant="outline"
                      onClick={() => {
                        void revealConfigPath(claudeCodeConfigPath, 'claudeCode');
                      }}
                    >
                      {t('settings.mcpRevealConfig')}
                    </Button>
                  </div>
                  <p className="text-2xs text-text-muted leading-relaxed">
                    {t('settings.mcpConfigInstruction')}
                  </p>
                  <pre className="bg-surface-1 border border-surface-3 rounded-r-card p-3 text-xs text-text-secondary whitespace-pre-wrap wrap-break-word font-mono select-all">
                    {mcpAssistantSnippets.claudeCode}
                  </pre>
                  {mcpAssistantSnippets.usesCwd && (
                    <p className="text-xs text-warning border-s-2 border-warning/60 bg-[var(--warning-tint-sm)] px-2 py-1 rounded-e">{t('settings.mcpClaudeCodeCwdWarning')}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs text-text-secondary">{t('settings.mcpCodex')}</p>
                    <TonalButton
                      tone="accent"
                      onClick={() => {
                        void onCopySnippet('codex', mcpAssistantSnippets.codex);
                      }}
                    >
                      {copiedSnippet === 'codex' ? t('common.copied') : t('common.copy')}
                    </TonalButton>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs text-text-muted min-w-0 flex-1 truncate">
                      {t('settings.mcpConfigPath')}: <span className="font-mono">{codexConfigPath}</span>
                    </p>
                    <Button
                      variant="outline"
                      onClick={() => {
                        void revealConfigPath(codexConfigPath, 'codex');
                      }}
                    >
                      {t('settings.mcpRevealConfig')}
                    </Button>
                  </div>
                  <p className="text-2xs text-text-muted leading-relaxed">
                    {t('settings.mcpConfigInstructionCodex')}
                  </p>
                  <pre className="bg-surface-1 border border-surface-3 rounded-r-card p-3 text-xs text-text-secondary whitespace-pre-wrap wrap-break-word font-mono select-all">
                    {mcpAssistantSnippets.codex}
                  </pre>
                </div>
              </div>
            )}
          </div>
        ) : (
          <p className="text-xs text-text-muted">{t('settings.mcpNotConfigured')}</p>
        )}

        <p className="text-xs text-text-muted">
          {t('settings.mcpSetupHint')}{' '}
          <a
            href="https://github.com/boyugou/ai-native-todo/blob/main/docs/setup/ASSISTANT_MCP_SETUP.md"
            target="_blank"
            rel="noopener noreferrer"
            className="underline text-accent hover:text-accent/80"
          >
            {t('settings.mcpSetupGuide')}
          </a>
        </p>
      </div>
    </SettingsSection>
  );
}
