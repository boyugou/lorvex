import { useCallback, useState } from 'react';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { exportDiagnosticsBundle } from '@/lib/ipc/diagnostics';
import { useI18n } from '@/lib/i18n';

/**
 * One-click diagnostic bundle export. Combines error_logs, the
 * last 30 days of ai_changelog, the sync conflict log, and a small
 * system-info JSON into a single ZIP. Uses Tauri's native save dialog
 * so the user picks the destination — no silent writes, no fallback
 * location. Lazy-imports `@tauri-apps/plugin-dialog` so the plugin JS
 * only loads when the user actually clicks the button (same pattern as
 * the data-snapshot exporter).
 */
export function ExportBundleCard() {
  const { t, format } = useI18n();
  const [busy, setBusy] = useState(false);
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  const handleExport = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    setActionMsg(null);
    try {
      // Build a sensible default filename so the user doesn't have to
      // invent one. Uses a UTC timestamp (no colons — they are invalid
      // on Windows filesystems) so rapid repeat exports don't collide.
      const stamp = new Date()
        .toISOString()
        .replace(/[:.]/g, '-')
        .replace(/Z$/, 'Z');
      const defaultName = `lorvex-diagnostics-${stamp}.zip`;

      const { save } = await import('@tauri-apps/plugin-dialog');
      const chosenPath = await save({
        title: t('diagnostics.exportBundle.saveDialogTitle'),
        defaultPath: defaultName,
        filters: [{ name: 'ZIP Archive', extensions: ['zip'] }],
      });
      if (!chosenPath) {
        // User cancelled — surface nothing; the cancel is self-evident.
        setBusy(false);
        return;
      }

      const result = await exportDiagnosticsBundle(chosenPath);
      const summary = format('diagnostics.exportBundle.success', {
        errors: String(result.error_log_count),
        changelog: String(result.changelog_count),
        conflicts: String(result.conflict_log_count),
      });
      setActionMsg(summary);
    } catch (error) {
      setActionMsg(
        `${t('common.error')}: ${toIpcErrorMessage(error)}`,
      );
    } finally {
      setBusy(false);
    }
  }, [busy, format, t]);

  return (
    <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-2">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <p className="text-xs text-text-secondary font-medium">
            {t('diagnostics.exportBundle.title')}
          </p>
          <p className="text-xs text-text-muted mt-0.5">
            {t('diagnostics.exportBundle.desc')}
          </p>
          <p className="text-xs text-text-muted mt-0.5">
            {t('diagnostics.exportBundle.scope')}
          </p>
        </div>
        <button
          type="button"
          onClick={() => {
            void handleExport();
          }}
          disabled={busy}
          className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
        >
          {busy
            ? t('diagnostics.exportBundle.busy')
            : t('diagnostics.exportBundle.button')}
        </button>
      </div>
      {actionMsg && (
        <p className="text-xs text-text-muted wrap-break-word">{actionMsg}</p>
      )}
    </div>
  );
}
