import { useCallback } from 'react';

import { revealItemInDir } from '@tauri-apps/plugin-opener';
import type { ExportSnapshotResult, ImportSnapshotResult, SnapshotExportCategory } from '@/lib/ipc/settings';
import type { TranslationKey } from '@/lib/i18n';
import { useI18n } from '@/lib/i18n';
import { StatGrid } from '@/components/ui/StatGrid';
import { Banner } from '@/components/ui/Banner';
import type { SnapshotPanelProps } from './snapshot-panel/types';

/** Static lookup for export scope category i18n keys — avoids dynamic template literal construction. */
const EXPORT_SCOPE_CATEGORY_LABEL_KEYS: Record<SnapshotExportCategory, TranslationKey> = {
  tasks: 'settings.exportScopeCategory.tasks',
  lists: 'settings.exportScopeCategory.lists',
  calendar: 'settings.exportScopeCategory.calendar',
  habits: 'settings.exportScopeCategory.habits',
  daily_reviews: 'settings.exportScopeCategory.daily_reviews',
  memory: 'settings.exportScopeCategory.memory',
  preferences: 'settings.exportScopeCategory.preferences',
  focus: 'settings.exportScopeCategory.focus',
  subscriptions: 'settings.exportScopeCategory.subscriptions',
  audit: 'settings.exportScopeCategory.audit',
};

const EXPORT_SCOPE_CATEGORY_ORDER: SnapshotExportCategory[] = [
  'tasks',
  'lists',
  'calendar',
  'habits',
  'daily_reviews',
  'memory',
  'preferences',
  'focus',
  'subscriptions',
  'audit',
];

function isImportResult(result: SnapshotPanelProps['lastSnapshotResult']): result is ImportSnapshotResult {
  return result != null && 'entities_created' in result;
}

function isExportResult(result: SnapshotPanelProps['lastSnapshotResult']): result is ExportSnapshotResult {
  return result != null && 'export_path' in result;
}

export function SnapshotPanel({
  snapshotBusy,
  lastSnapshotResult,
  snapshotErrorDetail,
  snapshotStatus,
  lastExportPath,
  snapshotPreview,
  exportScopeMode,
  exportScopeCategories,
  onExportSnapshot,
  onSetExportScopeMode,
  onToggleExportScopeCategory,
  onLoadSnapshotFile,
  onImportSnapshot,
}: SnapshotPanelProps) {
  const { t } = useI18n();

  const handleRevealExport = useCallback(() => {
    if (lastExportPath) {
      void revealItemInDir(lastExportPath);
    }
  }, [lastExportPath]);

  return (
    <div className="space-y-4">
      {/* -- Export -- */}
      <div className="space-y-2">
        {/* Export scope + Export button collapse onto one row when
            "full" is selected; expanding to "scoped" reveals an inline
            category grid below. No card chrome — the parent
            SettingsSection already owns the panel frame, so the prior
            nested-card look has been flattened. */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-medium text-text-secondary me-1">
            {t('settings.exportScopeLabel')}
          </span>
          <button
            type="button"
            onClick={() => onSetExportScopeMode('full')}
            disabled={snapshotBusy}
            className={`text-xs px-3 py-1.5 rounded-r-control border transition-colors ${
              exportScopeMode === 'full'
                ? 'bg-[var(--accent-tint-sm)] border-accent/30 text-accent'
                : 'bg-surface-1 border-surface-3 text-text-secondary hover:bg-surface-3'
            }`}
          >
            {t('settings.exportScopeFull')}
          </button>
          <button
            type="button"
            onClick={() => onSetExportScopeMode('scoped')}
            disabled={snapshotBusy}
            className={`text-xs px-3 py-1.5 rounded-r-control border transition-colors ${
              exportScopeMode === 'scoped'
                ? 'bg-[var(--accent-tint-sm)] border-accent/30 text-accent'
                : 'bg-surface-1 border-surface-3 text-text-secondary hover:bg-surface-3'
            }`}
          >
            {t('settings.exportScopeScoped')}
          </button>
          <div className="ms-auto">
            <button
              type="button"
              onClick={() => { void onExportSnapshot(); }}
              disabled={snapshotBusy}
              className="text-xs px-3 py-1.5 rounded-r-control bg-[var(--accent-tint-sm)] border border-accent/25 text-accent hover:bg-[var(--accent-tint-md)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-ring-strong"
            >
              {snapshotBusy ? t('common.saving') : t('settings.dataExport')}
            </button>
          </div>
        </div>

        {exportScopeMode === 'scoped' && (
          <div className="space-y-2">
            <p className="text-xs text-text-muted">{t('settings.exportScopeScopedHint')}</p>
            {/* Routed through the shared StatGrid primitive
                with `gap="tight"` so this scope-picker keeps its
                closer 8px spacing while staying in lockstep with the
                Today / DailyReview breakpoints. */}
            <StatGrid density="compact" gap="tight">
              {EXPORT_SCOPE_CATEGORY_ORDER.map((category) => {
                const checked = exportScopeCategories.includes(category);
                return (
                  <label
                    key={category}
                    className="flex items-center gap-2 rounded-r-control border border-surface-3 bg-surface-1 px-2.5 py-2 text-xs text-text-secondary"
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={snapshotBusy}
                      onChange={() => onToggleExportScopeCategory(category)}
                    />
                    <span>{t(EXPORT_SCOPE_CATEGORY_LABEL_KEYS[category])}</span>
                  </label>
                );
              })}
            </StatGrid>
          </div>
        )}

        <p className="text-xs text-text-muted">{t('settings.exportZipHelper')}</p>
      </div>

      {/* -- Import -- */}
      <div className="space-y-2 pt-3 border-t border-card">
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => { void onLoadSnapshotFile(); }}
            disabled={snapshotBusy}
            className="text-xs px-3 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-ring-soft"
          >
            {t('settings.dataImport')}
          </button>
          {/* When a file is selected, the "Import" CTA appears next to
              "Choose file" rather than in its own card below — keeps
              the import flow on one row. */}
          {snapshotPreview.fileName !== null && (
            <>
              <span className="text-xs text-text-muted truncate max-w-[18rem]" title={snapshotPreview.fileName}>
                {snapshotPreview.fileName}
              </span>
              <button
                type="button"
                onClick={() => { void onImportSnapshot(); }}
                disabled={snapshotBusy}
                className="text-xs px-3 py-1.5 rounded-r-control bg-accent text-on-accent hover:bg-accent/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-ring-strong ms-auto"
              >
                {snapshotBusy ? t('common.saving') : t('settings.importConfirm')}
              </button>
            </>
          )}
        </div>
        <p className="text-xs text-text-muted">{t('settings.snapshotZipHelper')}</p>
      </div>

      {/* -- Status feedback -- */}
      {snapshotStatus && (
        <div
          className={`text-xs rounded-r-card border px-3 py-2.5 ${
            snapshotStatus.tone === 'success'
              ? 'tonal-surface-success-sm text-success'
              : snapshotStatus.tone === 'error'
                ? 'tonal-surface-danger-sm text-danger'
                : 'bg-[var(--accent-tint-xs)] border-accent/30 text-accent'
          }`}
        >
          <div className="flex items-center justify-between gap-2">
            <span className="select-text">{snapshotStatus.message}</span>
            {snapshotStatus.tone === 'success' && lastExportPath && (
              <button
                type="button"
                onClick={handleRevealExport}
                className="shrink-0 text-xs px-2 py-0.5 rounded-r-control chip-success chip-success-interactive border border-success/25 focus-ring-soft-success"
              >
                {t('settings.revealInFolder')}
              </button>
            )}
          </div>
          {snapshotErrorDetail && (
            <p className="mt-1 text-xs opacity-70 select-text">{snapshotErrorDetail}</p>
          )}
        </div>
      )}

      {/* Import result summary */}
      {isExportResult(lastSnapshotResult) && (
        <div className="text-xs text-text-muted bg-surface-2/60 rounded-r-card border border-surface-3 px-3 py-2.5">
          {t('settings.exportResultSummary')}: {lastSnapshotResult.scope_kind === 'full'
            ? t('settings.exportScopeFull')
            : `${t('settings.exportScopeScoped')} (${lastSnapshotResult.scope_categories.map((category) => t(EXPORT_SCOPE_CATEGORY_LABEL_KEYS[category])).join(', ')})`}
        </div>
      )}

      {isImportResult(lastSnapshotResult) && (
        <div className="space-y-2">
          <div className="text-xs text-text-muted bg-surface-2/60 rounded-r-card border border-surface-3 px-3 py-2.5">
            {t('settings.importResultSummary')}: {lastSnapshotResult.entities_created} {t('settings.importCreated')}, {lastSnapshotResult.entities_updated} {t('settings.importUpdated')}
            {lastSnapshotResult.entities_skipped > 0 && ` (${lastSnapshotResult.entities_skipped} ${t('settings.importSkipped')})`}
            {lastSnapshotResult.blobs_hash_mismatch > 0 && ` - ${t('settings.importBlobsHashMismatch')}: ${lastSnapshotResult.blobs_hash_mismatch}`}
          </div>
          {lastSnapshotResult.validation_findings.length > 0 && (
            <Banner tone="danger">
              <div className="space-y-1">
                {lastSnapshotResult.validation_findings.map((finding) => (
                  <p key={`${finding.code}:${finding.message}`} className="select-text">
                    {finding.message}
                  </p>
                ))}
              </div>
            </Banner>
          )}
        </div>
      )}
    </div>
  );
}
