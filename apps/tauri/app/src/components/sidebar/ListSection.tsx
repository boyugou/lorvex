import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';

import { useI18n, type TranslationKey } from '@/lib/i18n';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { UI_STATE_DRAFT_KEYS } from '@/lib/storage/drafts';
import { getUIStateString, removeUIState, setUIState } from '@/lib/storage/uiState';
import type { View } from '@/lib/types';
import { isImeComposing } from '@/lib/ime';
import { ClipboardIcon } from '../ui/icons';
import { SearchInput } from '../ui/SearchInput';
import { Tooltip } from '../ui/Tooltip';
import { ContextMenu } from '../context-menu/ContextMenu';

import NavItem from './NavItem';
import { useListContextMenu } from './useListContextMenu';

/** persist the inline list-create draft so a stray
 *  blur (clicked another sidebar item, switched windows) doesn't
 *  silently lose typed text. Mirrors the `quickCapture:lastListId`
 *  pattern. Cleared on submit and on explicit cancel via Escape. */
const NEW_LIST_DRAFT_KEY = UI_STATE_DRAFT_KEYS.sidebarNewList;

const MAX_VISIBLE_LISTS = 5;
// Threshold above which the inline search input is surfaced. Below this count
// the section is short enough to scan visually, and a dedicated search control
// would just add clutter.
const SEARCH_THRESHOLD = 10;

const ListNavEntry = memo(function ListNavEntry({
  list,
  active,
  onNavigate,
  onContextMenu,
  onKeyboardOpenContextMenu,
}: {
  list: ListWithCount;
  active: boolean;
  onNavigate: (view: View) => void;
  onContextMenu: (e: React.MouseEvent, listId: string, listName: string) => void;
  /**
   * Keyboard shortcut path for the context menu — Shift+F10 (cross-platform
   * a11y standard) and `.` on macOS (Finder/native macOS convention). The
   * task list at /lib/tasks/useTaskListKeyboard.keydown.ts implements the
   * same chord for tasks; mirroring it on sidebar list rows gives keyboard
   * users parity with the right-click affordance.
   */
  onKeyboardOpenContextMenu: (
    trigger: HTMLElement,
    listId: string,
    listName: string,
  ) => void;
}) {
  const handleClick = useCallback(() => onNavigate({ type: 'list', listId: list.id }), [list.id, onNavigate]);
  const handleItemContextMenu = useCallback(
    (e: React.MouseEvent) => onContextMenu(e, list.id, list.name),
    [list.id, list.name, onContextMenu],
  );
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLButtonElement>) => {
      // Shift+F10: portable a11y context-menu chord.
      const isShiftF10 =
        e.key === 'F10'
        && e.shiftKey
        && !e.metaKey
        && !e.ctrlKey
        && !e.altKey;
      // `.` (bare): macOS context-menu shortcut convention. Only triggers
      // when the row is focused — bubble guard via `e.target === e.currentTarget`
      // so a `.` typed inside a child input (none today, but future-proof)
      // never hijacks the keystroke.
      const isMacDot =
        e.key === '.'
        && !e.shiftKey
        && !e.metaKey
        && !e.ctrlKey
        && !e.altKey
        && !isImeComposing(e)
        && e.target === e.currentTarget;
      if (!isShiftF10 && !isMacDot) return;
      e.preventDefault();
      e.stopPropagation();
      onKeyboardOpenContextMenu(e.currentTarget, list.id, list.name);
    },
    [list.id, list.name, onKeyboardOpenContextMenu],
  );

  return (
    <NavItem
      label={list.name}
      icon={list.icon ?? <ClipboardIcon />}
      badge={list.open_count || null}
      accentColor={list.color || 'var(--color-text-muted)'}
      active={active}
      onClick={handleClick}
      onContextMenu={handleItemContextMenu}
      onKeyDown={handleKeyDown}
    />
  );
});

interface ListSectionProps {
  lists: ListWithCount[];
  currentView: View;
  creatingList: boolean;
  isCreatingList: boolean;
  onNavigate: (view: View) => void;
  handleCreateList: (name: string) => void;
  setCreatingList: (v: boolean) => void;
  t: (key: TranslationKey) => string;
}

export default function ListSection({
  lists,
  currentView,
  creatingList,
  isCreatingList,
  onNavigate,
  handleCreateList,
  setCreatingList,
  t,
}: ListSectionProps) {
  const { format } = useI18n();
  const newListInputRef = useRef<HTMLInputElement>(null);
  /**
   * When the user clicks the "+ create list" affordance, focus must
   * land in the freshly-mounted input. A ref-driven `useEffect` that
   * runs after every commit focuses deterministically the moment the
   * input mounts, without timing assumptions. (A `requestAnimationFrame`
   * fired from the same event handler races the React commit two ways:
   * the rAF may run before the re-render that mounts the input has
   * committed — leaving `ref.current` null — and browsers can flush
   * the rAF ahead of the commit on slower frames with the same
   * result.)
   */
  const pendingFocusOnCreateRef = useRef(false);
  const requestNewListFocus = useCallback(() => {
    pendingFocusOnCreateRef.current = true;
    setCreatingList(true);
  }, [setCreatingList]);
  const [listsExpanded, setListsExpanded] = useState(false);
  const [newListDraft, setNewListDraft] = useState<string>(() =>
    getUIStateString(NEW_LIST_DRAFT_KEY, ''),
  );

  useEffect(() => {
    if (!creatingList || !pendingFocusOnCreateRef.current) return;
    const input = newListInputRef.current;
    if (!input) return;
    pendingFocusOnCreateRef.current = false;
    input.focus();
    // Move the caret to the end so a persisted draft is editable
    // immediately without overwriting the existing text on first
    // keystroke.
    const length = input.value.length;
    try {
      input.setSelectionRange(length, length);
    } catch {
      // setSelectionRange is unsupported on some input types; the focus
      // call alone still gives us the right UX in that case.
    }
  }, [creatingList]);

  // Persist the draft on every keystroke. Clear it on explicit
  // submit or cancel; a blur is not enough to drop the value.
  useEffect(() => {
    if (newListDraft.length === 0) {
      removeUIState(NEW_LIST_DRAFT_KEY);
    } else {
      setUIState(NEW_LIST_DRAFT_KEY, newListDraft);
    }
  }, [newListDraft]);

  // If a non-empty draft existed at mount time, keep the inline create
  // input open so the user lands back where they left off.
  const hasPersistedDraftOnMountRef = useRef(newListDraft.length > 0);
  useEffect(() => {
    if (hasPersistedDraftOnMountRef.current && !creatingList) {
      setCreatingList(true);
    }
    // Only run on mount — re-runs would fight user-driven cancellation.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Local-only search query. Intentionally not persisted — it's a transient
  // find-as-you-type filter, not a preference. Resets on sidebar remount.
  const [searchQuery, setSearchQuery] = useState('');
  const {
    contextMenu,
    contextMenuItems,
    handleContextMenu,
    openContextMenuForElement,
    closeContextMenu,
  } = useListContextMenu(onNavigate, t);

  const activeListId = currentView.type === 'list' ? currentView.listId : null;

  const showSearch = lists.length > SEARCH_THRESHOLD;
  const trimmedQuery = searchQuery.trim();
  const hasQuery = showSearch && trimmedQuery.length > 0;

  const filteredLists = useMemo(() => {
    if (!hasQuery) return lists;
    const needle = trimmedQuery.toLowerCase();
    return lists.filter((list) => list.name.toLowerCase().includes(needle));
  }, [lists, hasQuery, trimmedQuery]);

  // While actively filtering, skip the "+N more" collapse entirely — the user
  // is searching precisely because they want to see matches, not a truncated
  // prefix of the full list.
  const showAll = hasQuery || listsExpanded || filteredLists.length <= MAX_VISIBLE_LISTS;
  // Memoized so unrelated sidebar re-renders (theme, view nav) don't re-walk
  // `filteredLists` to re-derive the same array.
  const visibleLists = useMemo(
    () =>
      showAll
        ? filteredLists
        : filteredLists.filter((list, idx) => idx < MAX_VISIBLE_LISTS || list.id === activeListId),
    [filteredLists, showAll, activeListId],
  );
  const hiddenCount = filteredLists.length - visibleLists.length;

  return (
    <div className="px-2 flex-1 overflow-y-auto space-y-0.5">
      <div className="flex items-center justify-between px-2 mb-0.5">
        <span className="text-xs font-medium text-text-muted">{t('nav.lists')}</span>
        <Tooltip label={t('sidebar.newList')}>
          <button
            type="button"
            onClick={requestNewListFocus}
            className="min-tap p-3 rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-3/70 active:scale-[0.97] flex items-center justify-center text-xs leading-none transition-colors focus-ring-soft"
            aria-label={t('sidebar.newList')}
          >
            +
          </button>
        </Tooltip>
      </div>

      {/* power users with many lists need a fast way to jump to one
          without scrolling. Surface a find-as-you-type filter only when the
          list count exceeds SEARCH_THRESHOLD — below that, visual scanning
          is faster than typing. */}
      {showSearch && (
        <div className="px-2 pb-1.5">
          <SearchInput
            value={searchQuery}
            onChange={setSearchQuery}
            placeholder={t('sidebar.searchLists')}
            className="relative block"
          />
        </div>
      )}

      {visibleLists.map((list) => (
        <ListNavEntry
          key={list.id}
          list={list}
          active={currentView.type === 'list' && currentView.listId === list.id}
          onNavigate={onNavigate}
          onContextMenu={handleContextMenu}
          onKeyboardOpenContextMenu={openContextMenuForElement}
        />
      ))}

      {/* Empty-filter state: the user typed a query but nothing matches.
          Distinct from the zero-lists case below — the remedy here is to
          refine the query, not to create a first list. */}
      {hasQuery && filteredLists.length === 0 && (
        <div
          role="status"
          aria-live="polite"
          className="px-3 py-2 text-xs text-text-muted leading-snug"
        >
          {format('sidebar.searchListsEmpty', { query: trimmedQuery })}
        </div>
      )}

      {/* fresh users land on an empty sidebar with only the
          subtle "+" icon next to the section label. Surface a
          prominent inline CTA when there are zero custom lists AND
          the user hasn't already clicked the + to open the inline
          input — so we invite list creation without stacking two
          affordances once they've started typing. */}
      {lists.length === 0 && !creatingList && (
        <button
          type="button"
          onClick={requestNewListFocus}
          className="w-full mt-1 px-3 py-2.5 rounded-r-control border border-dashed border-surface-3 bg-surface-2/40 text-xs text-text-secondary hover:text-text-primary hover:bg-surface-2 hover:border-accent/40 transition-colors text-start focus-ring-soft"
        >
          <span className="block font-medium">{t('sidebar.createFirstListTitle')}</span>
          <span className="block text-text-muted mt-0.5 leading-snug">
            {t('sidebar.createFirstListHint')}
          </span>
        </button>
      )}

      {hiddenCount > 0 && (
        <button
          type="button"
          onClick={() => setListsExpanded(true)}
          className="w-full px-2 py-1 text-xs text-text-muted hover:text-text-secondary transition-colors rounded-r-control hover:bg-surface-2/50 text-start focus-ring-soft"
        >
          +{hiddenCount} {t('popover.more')}
        </button>
      )}

      {creatingList && (
        <form
          className="px-2 py-1 space-y-1"
          onSubmit={(e) => {
            e.preventDefault();
            const value = newListDraft.trim();
            if (!value) return;
            handleCreateList(value);
            setNewListDraft('');
          }}
        >
          <input
            ref={newListInputRef}
            type="text"
            value={newListDraft}
            onChange={(e) => setNewListDraft(e.target.value)}
            placeholder={t('sidebar.newListPlaceholder')}
            aria-label={t('sidebar.newListPlaceholder')}
            disabled={isCreatingList}
            maxLength={MAX_TITLE_LENGTH}
            data-theme-form-control="true"
            className="w-full text-sm bg-surface-2 border border-surface-3 rounded-r-control px-2 py-1 text-text-primary placeholder:text-text-muted focus-ring-soft disabled:opacity-50"
            onBlur={() => {
              // only collapse if the input is empty.
              // Otherwise keep the form mounted so the typed text isn't
              // lost just because the user clicked elsewhere — they can
              // come back and finish, or hit Escape to cancel.
              if (isCreatingList) return;
              if (newListDraft.trim().length === 0) {
                setNewListDraft('');
                setCreatingList(false);
              }
            }}
            onKeyDown={(e) => {
              if (isImeComposing(e)) return;
              if (e.key === 'Escape') {
                setNewListDraft('');
                setCreatingList(false);
              }
            }}
          />
          {newListDraft.trim().length > 0 && (
            <div className="flex items-center justify-between gap-2 text-3xs text-text-muted px-1">
              <span>{t('sidebar.newListDraftHint')}</span>
              <div className="flex gap-1.5">
                {/* `px-2.5 py-1` + explicit `text-xs` keeps these
                    inline action buttons clearing the WCAG 2.5.5
                    24×24 minimum hit target on both runtimes without
                    visually overpowering the surrounding sidebar
                    chrome. */}
                <button
                  type="button"
                  onClick={() => {
                    setNewListDraft('');
                    setCreatingList(false);
                  }}
                  disabled={isCreatingList}
                  className="text-xs px-2.5 py-1 rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-3 transition-colors disabled:opacity-50"
                >
                  {t('common.cancel')}
                </button>
                <button
                  type="submit"
                  disabled={isCreatingList}
                  className="text-xs px-2.5 py-1 rounded-r-control text-accent hover:bg-accent/10 transition-colors disabled:opacity-50"
                >
                  {t('common.save')}
                </button>
              </div>
            </div>
          )}
        </form>
      )}

      {contextMenu && (
        <ContextMenu
          items={contextMenuItems}
          position={contextMenu.position}
          onClose={closeContextMenu}
          triggerElement={contextMenu.triggerElement}
        />
      )}
    </div>
  );
}
