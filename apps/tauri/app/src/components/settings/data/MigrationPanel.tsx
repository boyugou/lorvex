import { useCallback, useEffect, useState } from 'react';

import { revealItemInDir } from '@tauri-apps/plugin-opener';

import { Banner } from '@/components/ui/Banner';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { exportInterchange, importInterchange } from '@/lib/ipc/settings';
import { useI18n } from '@/lib/i18n';

const BUTTON_CLASS =
  'text-xs px-3 py-1.5 rounded-r-control bg-[var(--accent-tint-sm)] border border-accent/25 ' +
  'text-accent hover:bg-[var(--accent-tint-md)] disabled:opacity-50 disabled:cursor-not-allowed ' +
  'transition-colors focus-ring-strong';

const INPUT_CLASS =
  'flex-1 min-w-0 text-xs px-2.5 py-1.5 rounded-r-control border border-surface-3 bg-surface-1 ' +
  'text-text-primary placeholder:text-text-muted focus-ring-strong';

/**
 * Whole-database migration via the lean `lorvex-interchange` format: export the
 * essential current data to one portable `.zip`, or import such a file into this
 * store. Self-contained (own state + direct IPC) — it does not flow through the
 * data settings controller, since migration is a discrete, infrequent action.
 */
export function MigrationPanel() {
  const { t, format } = useI18n();
  const [busy, setBusy] = useState(false);
  const [exportPath, setExportPath] = useState<string | null>(null);
  const [importPath, setImportPath] = useState('');
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lists, setLists] = useState<ListWithCount[]>([]);
  const [selectedListIds, setSelectedListIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    let active = true;
    void getAllLists()
      .then((result) => {
        if (active) setLists(result);
      })
      .catch(() => {
        /* the picker is optional; full export still works */
      });
    return () => {
      active = false;
    };
  }, []);

  const onExport = useCallback(async () => {
    setBusy(true);
    setError(null);
    setStatus(null);
    try {
      const result = await exportInterchange({ listIds: Array.from(selectedListIds) });
      setExportPath(result.export_path);
      setStatus(format('settings.migration.exported', { path: result.export_path }));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }, [format, selectedListIds]);

  const toggleList = useCallback((id: string) => {
    setSelectedListIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const onImport = useCallback(async () => {
    const path = importPath.trim();
    if (!path) return;
    setBusy(true);
    setError(null);
    setStatus(null);
    try {
      const result = await importInterchange(path);
      const records = Object.values(result.row_counts).reduce((a, b) => a + b, 0);
      setStatus(
        format('settings.migration.imported', { records }),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }, [importPath, format]);

  return (
    <div className="space-y-3">
      {lists.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs text-text-muted">{t('settings.exportScopeScopedHint')}</p>
          <div className="flex flex-wrap gap-2">
            {lists.map((list) => (
              <label
                key={list.id}
                className="flex items-center gap-1.5 rounded-r-control border border-surface-3 bg-surface-1 px-2.5 py-1.5 text-xs text-text-secondary"
              >
                <input
                  type="checkbox"
                  checked={selectedListIds.has(list.id)}
                  onChange={() => toggleList(list.id)}
                  disabled={busy}
                />
                {list.name}
              </label>
            ))}
          </div>
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <button type="button" onClick={() => void onExport()} disabled={busy} className={BUTTON_CLASS}>
          {busy ? t('common.saving') : t('settings.migration.export')}
        </button>
        {exportPath && (
          <button
            type="button"
            onClick={() => void revealItemInDir(exportPath)}
            className="text-xs px-3 py-1.5 rounded-r-control border border-surface-3 bg-surface-1 text-text-secondary hover:bg-surface-3 transition-colors"
          >
            {t('settings.revealInFolder')}
          </button>
        )}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <input
          type="text"
          value={importPath}
          onChange={(event) => setImportPath(event.target.value)}
          placeholder={t('settings.snapshotZipHelper')}
          disabled={busy}
          className={INPUT_CLASS}
        />
        <button
          type="button"
          onClick={() => void onImport()}
          disabled={busy || importPath.trim().length === 0}
          className={BUTTON_CLASS}
        >
          {busy ? t('common.saving') : t('settings.migration.import')}
        </button>
      </div>

      {status && <Banner tone="success">{status}</Banner>}
      {error && <Banner tone="danger">{error}</Banner>}
    </div>
  );
}
