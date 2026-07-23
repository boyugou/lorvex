import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';

import { useI18n } from '@/lib/i18n';
import { formatSelectedTaskCountLabel } from '@/lib/dates/i18nCountPhrases';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import { encodeListSelectionValue, decodeListSelectionValue } from '@/lib/listSelection';
import type { BulkAction } from '@/lib/tasks/useTaskSelection';
import { AppSelect } from './AppSelect';

const BTN = 'text-xs font-medium px-3 py-2 rounded-r-control bg-surface-3/80 text-text-secondary hover:bg-surface-3 active:scale-[0.97] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-strong transition-[color,background-color,transform] duration-150';
const BTN_OUTLINE = 'text-xs font-medium px-3 py-2 rounded-r-control border border-card text-text-muted hover:text-text-primary hover:border-popover hover:bg-surface-2/50 active:scale-[0.97] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-strong transition-[color,background-color,border-color,transform] duration-150';

interface BulkActionBarProps {
  selectedCount: number;
  bulkAction: BulkAction;
  onSelectAll: () => void;
  onClearSelection: () => void;
  /**
   * Optional: invert the current selection over the visible rows
   *. Surfaces a "Invert" button next to "Select all" when
   * provided so selecting the complement of a small explicit pick is
   * a single click instead of "Select all → click out N rows."
   */
  onInvertSelection?: (() => void) | undefined;
  onComplete: () => void;
  onDefer: () => void;
  onCancel: () => void;
  onMove: (targetListId: string | null) => void;
  onFocus?: () => void;
  showMove?: boolean;
  showFocus?: boolean;
}

export function BulkActionBar({
  selectedCount,
  bulkAction,
  onSelectAll,
  onClearSelection,
  onInvertSelection,
  onComplete,
  onDefer,
  onCancel,
  onFocus,
  onMove,
  showMove = true,
  showFocus = false,
}: BulkActionBarProps) {
  const { locale, t } = useI18n();
  const [targetListId, setTargetListId] = useState<string | null>(null);
  // Flash the bar when the user presses a non-bulk-mode shortcut
  // while bulk-select is active. The keydown handler in
  // `useTaskListKeyboard.keydown.ts` already announces the hint to
  // screen readers via `announce()`; this ride-along visual flash
  // gives sighted users the same signal — without it the missed key
  // disappeared into the void and users couldn't tell whether the
  // shortcut was rejected or simply unbound.
  const [flashing, setFlashing] = useState(false);
  useEffect(() => {
    const handler = () => {
      setFlashing(true);
      const handle = window.setTimeout(() => setFlashing(false), 320);
      return () => window.clearTimeout(handle);
    };
    window.addEventListener('lorvex:bulk-select-miss', handler);
    return () => window.removeEventListener('lorvex:bulk-select-miss', handler);
  }, []);
  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
    enabled: showMove,
  });

  const disabled = bulkAction !== null;
  const noneSelected = selectedCount === 0;

  return (
    <div
      data-flash={flashing || undefined}
      className="mt-3 bg-surface-2/80 border border-card rounded-r-modal px-4 py-3 flex items-center gap-2.5 flex-wrap shadow-[var(--shadow-popover)] animate-[slide-in-up_0.2s_ease-out] data-[flash]:bg-[var(--warning-tint-md)] data-[flash]:border-warning/40 transition-[background-color,border-color] duration-200"
    >
      <span className="text-xs font-semibold text-text-primary tabular-nums me-1">
        {formatSelectedTaskCountLabel(locale, selectedCount, t)}
      </span>
      <button type="button" onClick={onSelectAll} disabled={disabled} className={BTN_OUTLINE}>
        {t('allTasks.selectAll')}
      </button>
      {onInvertSelection && (
        <button
          type="button"
          onClick={onInvertSelection}
          disabled={disabled}
          className={BTN_OUTLINE}
        >
          {t('allTasks.invertSelection')}
        </button>
      )}
      <button
        type="button"
        onClick={onComplete}
        disabled={disabled || noneSelected}
        className={`${BTN} hover:text-success`}
      >
        {bulkAction === 'complete' ? t('common.saving') : t('allTasks.bulkComplete')}
      </button>
      <button
        type="button"
        onClick={onDefer}
        disabled={disabled || noneSelected}
        className={`${BTN} hover:text-warning`}
      >
        {bulkAction === 'defer' ? t('common.saving') : t('allTasks.bulkDefer')}
      </button>
      <button
        type="button"
        onClick={onCancel}
        disabled={disabled || noneSelected}
        className={`${BTN} hover:text-danger`}
      >
        {bulkAction === 'cancel' ? t('common.saving') : t('allTasks.bulkCancel')}
      </button>
      {showFocus && onFocus && (
        <button
          type="button"
          onClick={onFocus}
          disabled={disabled || noneSelected}
          className={`${BTN} hover:text-accent`}
        >
          {bulkAction === 'focus' ? t('common.saving') : t('allTasks.bulkFocus')}
        </button>
      )}
      {showMove && (
        <>
          <AppSelect
            variant="muted"
            value={encodeListSelectionValue(targetListId)}
            disabled={disabled}
            onChange={(event) => setTargetListId(decodeListSelectionValue(event.target.value))}
            // the BulkActionBar move-target was
            // a bare combobox — its visible content was the placeholder
            // ("Pick list") inside the option list, but no programmatic
            // label was attached to the trigger button. SR users heard
            // a generic "combo box" with no indication that the value
            // selected the destination list for the bulk move action.
            // Forward the canonical "Pick list" label so the trigger
            // announces its purpose.
            aria-label={t('allTasks.pickList')}
          >
            <option value={encodeListSelectionValue(null)}>{t('allTasks.pickList')}</option>
            {lists.map((list) => (
              <option key={list.id} value={encodeListSelectionValue(list.id)}>
                {list.icon ? `${list.icon} ` : ''}{list.name}
              </option>
            ))}
          </AppSelect>
          <button
            type="button"
            onClick={() => onMove(targetListId)}
            disabled={disabled || noneSelected}
            className={`${BTN} hover:text-accent`}
          >
            {bulkAction === 'move' ? t('common.saving') : t('allTasks.bulkMove')}
          </button>
        </>
      )}
      <button
        type="button"
        onClick={onClearSelection}
        disabled={disabled || noneSelected}
        className={BTN_OUTLINE}
      >
        {t('allTasks.clearSelection')}
      </button>
    </div>
  );
}
