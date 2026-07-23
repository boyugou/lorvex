import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';

import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';
import { ModalShell } from './overlay';
import { useTaskPickerMutation } from './useTaskPickerMutation';
import {
  clampListPickerFocusIndex,
  getNextListPickerFocusIndex,
} from './ListPickerOverlay.runtime';

interface ListPickerOverlayProps {
  /** ID of the task to move. */
  taskId: string;
  /** Full task list so we can look up the current task. */
  tasks: Task[];
  /** Called when overlay closes (selection or escape). */
  onClose: () => void;
}

/**
 * Keyboard-driven list picker overlay triggered by the `m` shortcut.
 * Shows a filterable list of user lists; arrow keys navigate, Enter selects, Escape closes.
 */
// Stable id seed so each rendered option carries a
// referenceable id we can hand to `aria-activedescendant` on the
// search input. Per-instance unique-id generation would be overkill —
// the overlay is a singleton mount and the `taskId` prop is unique
// across mounts.
const LISTBOX_ID = 'lorvex-list-picker-listbox';

export function ListPickerOverlay({ taskId, tasks, onClose }: ListPickerOverlayProps) {
  const { t, format } = useI18n();
  const inputRef = useRef<HTMLInputElement>(null);
  const [search, setSearch] = useState('');
  const [focusIdx, setFocusIdx] = useState(0);

  const task = tasks.find((tk) => tk.id === taskId);
  const { commitTaskPickerUpdate } = useTaskPickerMutation(task, onClose);

  const { data: allLists } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  const filteredLists = useMemo(() => {
    if (!allLists) return [];
    const others = allLists.filter((l) => l.id !== task?.list_id);
    if (!search.trim()) return others;
    const lower = search.toLowerCase();
    return others.filter((l) => l.name.toLowerCase().includes(lower));
  }, [allLists, task?.list_id, search]);

  // Clamp focus when list changes
  useEffect(() => {
    setFocusIdx((prev) => clampListPickerFocusIndex(prev, filteredLists.length));
  }, [filteredLists.length]);

  // Auto-focus input on mount
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!task) {
      onClose();
    }
  }, [task, onClose]);

  const moveToList = useCallback(
    (targetList: ListWithCount) => {
      commitTaskPickerUpdate({
        patch: { list_id: targetList.id },
        successMessage: format('listPicker.moveSuccess', { list: targetList.name }),
        errorKey: 'listPicker.move',
        errorMessage: t('listPicker.moveError'),
        extraListIds: [targetList.id],
      });
    },
    [commitTaskPickerUpdate, format, t],
  );

  const handlePanelKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (isImeComposing(e)) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setFocusIdx((prev) => getNextListPickerFocusIndex('ArrowDown', prev, filteredLists.length));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setFocusIdx((prev) => getNextListPickerFocusIndex('ArrowUp', prev, filteredLists.length));
      } else if (e.key === 'Enter') {
        e.preventDefault();
        const target = filteredLists[focusIdx];
        if (target) moveToList(target);
      }
    },
    [filteredLists, focusIdx, moveToList],
  );

  if (!task) {
    return null;
  }

  return (
    <ModalShell
      open
      onClose={onClose}
      panelClassName="bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] w-[var(--popover-w-md)] max-h-80 flex flex-col overflow-hidden"
      ariaLabel={t('listPicker.title')}
      onPanelKeyDown={handlePanelKeyDown}
      autoFocus={false}
    >
      <div className="px-3 pt-3 pb-2">
        <p className="text-text-muted text-xs font-medium mb-1.5">
          {t('listPicker.title')}
        </p>
        {/* Search-driven listbox is a WAI-ARIA
            combobox. Wire role=combobox + aria-controls + aria-expanded
            on the input so AT announces "list, has popup, expanded";
            point aria-activedescendant at the highlighted option's id
            so SR users hear the focused list as they ArrowDown without
            losing typing focus on the search input. */}
        {/* search type for SR + soft-keyboard. */}
        <input
          ref={inputRef}
          type="search"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setFocusIdx(0);
          }}
          placeholder={t('listPicker.searchPlaceholder')}
          aria-label={t('listPicker.searchPlaceholder')}
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={filteredLists.length > 0}
          aria-controls={LISTBOX_ID}
          aria-activedescendant={
            filteredLists.length > 0 && filteredLists[focusIdx]
              ? `${LISTBOX_ID}-${filteredLists[focusIdx].id}`
              : undefined
          }
          className="w-full bg-surface-2/60 border border-card rounded-r-control px-2.5 py-1.5 text-xs text-text-primary placeholder:text-text-muted/50 outline-hidden focus-ring-soft"
        />
      </div>

      <div className="flex-1 overflow-y-auto px-1.5 pb-2">
        {filteredLists.length === 0 ? (
          <p className="text-text-muted text-xs text-center py-4">
            {t('listPicker.noLists')}
          </p>
        ) : (
          <div role="listbox" aria-orientation="vertical" id={LISTBOX_ID} aria-label={t('listPicker.title')}>
            {filteredLists.map((list, idx) => (
              <div
                key={list.id}
                id={`${LISTBOX_ID}-${list.id}`}
                role="option"
                aria-selected={idx === focusIdx}
                tabIndex={-1}
                onClick={() => moveToList(list)}
                onKeyDown={(e) => {
                  // Parent listbox owns navigation via aria-activedescendant;
                  // local Enter/Space keeps activation working if focus
                  // ever lands directly on an option (a11y baseline).
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    moveToList(list);
                  }
                }}
                className={`w-full text-start rounded-r-control px-2.5 py-1.5 text-sm flex items-center gap-2 transition-colors focus-ring-soft ${
                  idx === focusIdx
                    ? 'bg-[var(--accent-tint-sm)] text-accent'
                    : 'text-text-primary hover:bg-surface-2/60'
                }`}
              >
                {list.icon && <span className="text-sm" aria-hidden="true">{list.icon}</span>}
                <span className="truncate">{list.name}</span>
                <span className="ms-auto text-xs text-text-muted">{list.open_count}</span>
              </div>
            ))}
          </div>
        )}
      </div>

    </ModalShell>
  );
}
