/**
 * toolbar dropdown for managing a view's saved
 * filter presets.
 *
 * v1 scope:
 *  - Shows the list of saved presets for the owning view.
 *  - "Save current filter…" inline input that captures the current
 *    filter state via `onCapture()` and persists it.
 *  - Per-row click → applies the preset via `onApply(filterJson)`.
 *  - Per-row trailing × → deletes the preset.
 *
 * The component is intentionally dumb about filter shape — each
 * view owns its own serialize/deserialize pair and hands this
 * component two callbacks (`onCapture`, `onApply`). That keeps the
 * view-specific filter surfaces free to evolve independently.
 */

import { createPortal } from 'react-dom';
import { useCallback, useEffect, useId, useRef, useState } from 'react';

import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { ChevronDownIcon } from './icons';
import { RevealButton } from './RevealButton';
import { TonalButton } from './TonalButton';
import { useSavedQueries } from '@/lib/hooks/useSavedQueries';
import type { SavedQueryViewType } from '@/lib/ipc/savedQueries';
import { toast } from '@/lib/notifications/toast';
import {
  createBrowserSavedQueriesMenuDismissRuntimeDeps,
  focusSavedQueriesMenuInitialTarget,
  installSavedQueriesMenuDismissRuntime,
  resolveSavedQueriesMenuPosition,
} from './SavedQueriesMenu.runtime';

interface SavedQueriesMenuProps {
  /** Which view this menu persists presets for. */
  viewType: SavedQueryViewType;
  /** Called when the user hits Save — returns the current filter
   *  state serialized to an opaque JSON string. */
  onCapture: () => string;
  /** Called when the user picks a saved preset — receives the
   *  stored filter_json that the view must restore. */
  onApply: (filterJson: string) => void;
}

export function SavedQueriesMenu({ viewType, onCapture, onApply }: SavedQueriesMenuProps) {
  const { t, format } = useI18n();
  const { savedQueries, isLoading, save, remove, isSaving } = useSavedQueries(viewType);
  const [open, setOpen] = useState(false);
  const [panelPos, setPanelPos] = useState<{ top: number; left: number } | null>(null);
  const [newName, setNewName] = useState('');
  const menuId = useId();
  const headingId = useId();
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const newNameInputRef = useRef<HTMLInputElement>(null);
  const firstSavedQueryButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;

    return installSavedQueriesMenuDismissRuntime(
      createBrowserSavedQueriesMenuDismissRuntimeDeps({
        getTrigger: () => triggerRef.current,
        getPanel: () => panelRef.current,
        onDismiss: () => setOpen(false),
      }),
    );
  }, [open]);
  const focusSavedQueriesMenuInitialTargetFromDom = useCallback(() => {
    const panel = panelRef.current;
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: document.activeElement,
      isActiveElementInPanel: (activeElement) => (
        activeElement instanceof HTMLElement
        && panel !== null
        && panel.contains(activeElement)
        && activeElement !== panel
      ),
      isLoading,
      savedQueryCount: savedQueries.length,
      firstItem: firstSavedQueryButtonRef.current,
      nameInput: newNameInputRef.current,
    });
  }, [isLoading, savedQueries.length]);

  useEffect(() => {
    if (!open || !panelPos) return;
    const frame = window.requestAnimationFrame(focusSavedQueriesMenuInitialTargetFromDom);
    return () => window.cancelAnimationFrame(frame);
  }, [focusSavedQueriesMenuInitialTargetFromDom, open, panelPos]);

  // Return focus to the trigger when the menu
  // closes so keyboard users land back on a known anchor instead of
  // body. The `wasOpen` ref tracks the open→close transition so we
  // don't steal focus on the initial mount.
  const wasOpenRef = useRef(false);
  useEffect(() => {
    if (open) {
      wasOpenRef.current = true;
      return;
    }
    if (wasOpenRef.current) {
      wasOpenRef.current = false;
      triggerRef.current?.focus();
    }
  }, [open]);

  const toggle = () => {
    if (!open && triggerRef.current) {
      const rect = triggerRef.current.getBoundingClientRect();
      setPanelPos(resolveSavedQueriesMenuPosition(rect, window.innerWidth));
    }
    setOpen((prev) => !prev);
  };

  const handleSave = async () => {
    const name = newName.trim();
    if (!name) return;
    try {
      const filterJson = onCapture();
      await save(name, filterJson);
      setNewName('');
      toast.success(t('savedQueries.saved'));
    } catch (err) {
      toast.errorWithDetail(err, t('savedQueries.saveFailed'));
    }
  };

  const handleApply = (filterJson: string) => {
    onApply(filterJson);
    setOpen(false);
  };

  const handleDelete = async (id: string, name: string) => {
    try {
      await remove(id);
      // Route through `format()` with a `{name}` placeholder so
      // each locale's `savedQueries.deletedNamed` value owns its
      // own word order and quote style. String concatenation would
      // bake ASCII quotes and English word order into the call
      // site, which renders backwards under RTL locales (the
      // user-supplied name lands on the wrong side of the verb).
      toast.success(format('savedQueries.deletedNamed', { name }));
    } catch (err) {
      toast.errorWithDetail(err, t('savedQueries.deleteFailed'));
    }
  };

  const count = savedQueries.length;
  const hasActive = count > 0;

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={toggle}
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-controls={open ? menuId : undefined}
        className={`text-xs px-2.5 py-1 rounded-r-control border transition-colors focus-ring-soft inline-flex items-center gap-1.5 ${
          hasActive
            ? 'border-accent/40 bg-accent/10 text-accent'
            : 'border-surface-3 text-text-muted hover:text-text-primary'
        }`}
        title={t('savedQueries.trigger')}
      >
        <span aria-hidden="true">★</span>
        <span>{t('savedQueries.trigger')}</span>
        {hasActive && <span className="text-xs opacity-70">({count})</span>}
        {/* Triangle glyph is decorative — its
            meaning is already conveyed by `aria-expanded` on the
            button. Hide from AT to avoid SR reading
            "black-up-pointing-triangle". */}
        <ChevronDownIcon aria-hidden="true" className={`w-3 h-3 ms-0.5 transition-transform duration-150 ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && panelPos && createPortal(
        <div
          id={menuId}
          ref={panelRef}
          data-testid="saved-queries-menu"
          style={{ position: 'fixed', top: panelPos.top, left: panelPos.left, width: 260 }}
          className="z-[var(--z-popover)] bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] overflow-hidden"
          role="dialog"
          aria-labelledby={headingId}
          tabIndex={-1}
        >
          <div className="p-2">
            <div id={headingId} className="text-xs text-text-muted px-1 pb-1.5 font-medium">
              {t('savedQueries.heading')}
            </div>

            {isLoading ? (
              <div
                className="px-2 py-1.5"
                role="status"
                aria-live="polite"
                aria-label={t('common.loading')}
              >
                <div className="h-4 w-2/3 rounded-r-control bg-surface-3/60 animate-pulse" />
              </div>
            ) : savedQueries.length === 0 ? (
              <div className="px-2 py-1.5 text-xs text-text-muted italic">
                {t('savedQueries.empty')}
              </div>
            ) : (
              <ul className="flex list-none flex-col gap-0.5 max-h-64 overflow-y-auto p-0 m-0" aria-labelledby={headingId}>
                {savedQueries.map((q, i) => (
                  <li
                    key={q.id}
                    className="group flex items-center gap-1 rounded-r-control hover:bg-surface-2 transition-colors"
                  >
                    <button
                      ref={i === 0 ? firstSavedQueryButtonRef : undefined}
                      type="button"
                      onClick={() => handleApply(q.filter_json)}
                      className="flex-1 text-start text-xs px-2.5 py-1.5 text-text-secondary focus-ring-soft rounded-r-control truncate"
                      title={q.name}
                    >
                      {q.name}
                    </button>
                    <RevealButton
                      onClick={() => void handleDelete(q.id, q.name)}
                      aria-label={`${t('savedQueries.deleteAria')}: ${q.name}`}
                      size="comfortable"
                      className="text-xs me-1"
                    >
                      {/* ×-glyph would be read as
                          "multiplication sign" by JAWS/NVDA. The
                          `aria-label` above carries the real
                          accessible name; hide the visual character
                          from AT. */}
                      <span aria-hidden="true">×</span>
                    </RevealButton>
                  </li>
                ))}
              </ul>
            )}

            <div className="mt-2 pt-2 border-t border-surface-3">
              <div className="text-xs text-text-muted px-1 pb-1.5">
                {t('savedQueries.saveCurrent')}
              </div>
              <div className="flex items-center gap-1.5">
                <input
                  ref={newNameInputRef}
                  type="text"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder={t('savedQueries.namePlaceholder')}
                  aria-label={t('savedQueries.saveCurrent')}
                  maxLength={200}
                  onKeyDown={(e) => {
                    if (isImeComposing(e)) return;
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      void handleSave();
                    }
                  }}
                  className="flex-1 min-w-0 text-xs px-2 py-1.5 rounded-r-control bg-surface-2 border border-surface-3 text-text-primary placeholder:text-text-muted outline-hidden focus-ring-soft"
                />
                <TonalButton
                  tone="accent"
                  size="lg"
                  onClick={() => void handleSave()}
                  disabled={isSaving || !newName.trim()}
                >
                  {t('common.save')}
                </TonalButton>
              </div>
            </div>
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
