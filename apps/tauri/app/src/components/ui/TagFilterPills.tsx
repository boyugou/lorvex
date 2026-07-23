import { createPortal } from 'react-dom';
import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { useI18n } from '@/lib/i18n';
import { CheckIcon, ChevronDownIcon, XIcon } from './icons';
import { Tooltip } from './Tooltip';
import {
  advanceTagFilterPillsTypeAhead,
  clearTagFilterPillsTypeAhead,
  createBrowserTagFilterPillsDismissRuntimeDeps,
  createBrowserTagFilterPillsTypeAheadTimerHost,
  installTagFilterPillsDismissRuntime,
  resolveSelectedTagFilterPillLabels,
  resolveTagFilterPillsPanelPosition,
  type TagFilterPillsTypeAheadState,
} from './TagFilterPills.runtime';

interface TagFilterPillsProps {
  tags: string[];
  selected: Set<string>;
  onToggle: (tag: string) => void;
  onClear: () => void;
}

const PILL_ACTIVE = 'bg-accent/20 border-accent/40 text-accent';
const tagFilterPillsTypeAheadTimerHost = createBrowserTagFilterPillsTypeAheadTimerHost();

export function TagFilterPills({ tags, selected, onToggle, onClear }: TagFilterPillsProps) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [panelPos, setPanelPos] = useState<{ top: number; left: number } | null>(null);
  const [focusedIndex, setFocusedIndex] = useState(-1);
  const [searchFocused, setSearchFocused] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  // switch from a parallel array indexed by render position to
  // a stable Map keyed by render index. The ref-callback factory below
  // is `useCallback`-stable so React doesn't reinvoke it every render
  // (which a fresh `(el) => { ... }` arrow would). The Map handles
  // unmounts via the `el == null` branch.
  const optionRefs = useRef<Map<number, HTMLDivElement>>(new Map());
  const setOptionRef = useCallback((index: number) => (el: HTMLDivElement | null) => {
    if (el === null) optionRefs.current.delete(index);
    else optionRefs.current.set(index, el);
  }, []);
  const typeAheadRef = useRef<TagFilterPillsTypeAheadState>({ timer: null, buffer: '' });
  const listboxId = useId();
  const optionIdPrefix = useId();

  const closeAndReset = useCallback(() => {
    setOpen(false);
    setSearch('');
    setSearchFocused(false);
  }, []);

  // Clear the type-ahead timer on unmount so a keystroke within the
  // 500ms window followed by unmount doesn't leave a pending timer
  // mutating a detached ref.
  useEffect(() => {
    return () => {
      clearTagFilterPillsTypeAhead(
        // eslint-disable-next-line react-hooks/exhaustive-deps -- read latest ref at cleanup intentionally.
        typeAheadRef.current,
        tagFilterPillsTypeAheadTimerHost.clearTimeout,
      );
    };
  }, []);

  // Close on click outside or external scroll
  useEffect(() => {
    if (!open) return;

    const cleanupDismiss = installTagFilterPillsDismissRuntime(
      createBrowserTagFilterPillsDismissRuntimeDeps({
        getTrigger: () => triggerRef.current,
        getPanel: () => panelRef.current,
        onDismiss: closeAndReset,
      }),
    );

    return () => {
      cleanupDismiss();
    };
  }, [closeAndReset, open]);

  // Focus search input when opening
  useEffect(() => {
    if (open) {
      setFocusedIndex(-1);
      searchRef.current?.focus();
    }
  }, [open]);

  const filteredTags = useMemo(() => {
    if (!search.trim()) return tags;
    const q = search.trim().toLowerCase();
    return tags.filter((tag) => tag.toLowerCase().includes(q));
  }, [tags, search]);

  // Drop entries past the current filtered-list length and clamp the
  // focus index. With a Map-backed ref store the prune is explicit
  // (slice() worked because the prior storage was an array).
  useEffect(() => {
    for (const idx of optionRefs.current.keys()) {
      if (idx >= filteredTags.length) optionRefs.current.delete(idx);
    }
    setFocusedIndex((prev) => (prev >= filteredTags.length ? filteredTags.length - 1 : prev));
  }, [filteredTags.length]);

  const handleToggle = useCallback(
    (tag: string) => {
      onToggle(tag);
    },
    [onToggle],
  );

  const handleOpenToggle = () => {
    if (!open && triggerRef.current) {
      const rect = triggerRef.current.getBoundingClientRect();
      setPanelPos(resolveTagFilterPillsPanelPosition(rect, window.innerWidth));
    }
    setOpen((prev) => !prev);
    setSearch('');
  };

  const handleTypeAhead = (char: string) => {
    const matchIndex = advanceTagFilterPillsTypeAhead({
      state: typeAheadRef.current,
      typedChar: char,
      tags: filteredTags,
      focusedIndex,
      timerHost: tagFilterPillsTypeAheadTimerHost,
    });

    if (matchIndex !== null) {
      setFocusedIndex(matchIndex);
      optionRefs.current.get(matchIndex)?.focus();
    }
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      closeAndReset();
      triggerRef.current?.focus();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (filteredTags.length > 0) {
        const next = 0;
        setFocusedIndex(next);
        optionRefs.current.get(next)?.focus();
      }
    } else if (e.key === 'Enter') {
      // Select first filtered tag when pressing Enter in search
      e.preventDefault();
      if (filteredTags.length > 0) {
        const targetIdx = focusedIndex >= 0 ? focusedIndex : 0;
        const targetTag = filteredTags[targetIdx];
        if (targetTag) handleToggle(targetTag);
      }
    }
  };

  const handleListKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      closeAndReset();
      triggerRef.current?.focus();
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      if (focusedIndex >= 0 && focusedIndex < filteredTags.length) {
        const focusedTag = filteredTags[focusedIndex];
        if (focusedTag) handleToggle(focusedTag);
      }
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      const next = Math.min(focusedIndex + 1, filteredTags.length - 1);
      setFocusedIndex(next);
      optionRefs.current.get(next)?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (focusedIndex <= 0) {
        setFocusedIndex(-1);
        searchRef.current?.focus();
      } else {
        const prev = focusedIndex - 1;
        setFocusedIndex(prev);
        optionRefs.current.get(prev)?.focus();
      }
    } else if (e.key === 'Home') {
      e.preventDefault();
      setFocusedIndex(0);
      optionRefs.current.get(0)?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      const last = filteredTags.length - 1;
      setFocusedIndex(last);
      optionRefs.current.get(last)?.focus();
    } else if (e.key === 'Tab') {
      // Close on Tab to allow natural tab order
      closeAndReset();
    } else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      // Type-ahead: printable character (only when search is not focused)
      e.preventDefault();
      handleTypeAhead(e.key);
    }
  };

  // show pills for every selected tag, even ones absent from
  // the current view's tag list (e.g. when navigating to an empty
  // month in the calendar). Memoize to avoid the O(n) sweep / sort
  // running on every render — `tags` and `selected` change at filter-
  // tweak / view-switch frequency, the parent rerenders on every
  // typed search character. Computed before the early-return so the
  // hook count stays stable.
  const selectedArr = useMemo(
    () => resolveSelectedTagFilterPillLabels(tags, selected),
    [tags, selected],
  );

  if (tags.length === 0 && selected.size === 0) return null;

  const activeDescendantId = open && focusedIndex >= 0 ? `${optionIdPrefix}-${focusedIndex}` : undefined;
  const searchActiveDescendantId = searchFocused ? activeDescendantId : undefined;

  return (
    <div className="flex items-center gap-2 flex-wrap">
      {/* Trigger */}
      <button
        ref={triggerRef}
        type="button"
        onClick={handleOpenToggle}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-controls={open ? listboxId : undefined}
        className={`text-xs px-2.5 py-1 rounded-r-control border transition-colors focus-ring-soft ${
          selected.size > 0
            ? 'border-accent/40 bg-accent/10 text-accent'
            : 'border-surface-3 text-text-muted hover:text-text-primary hover:border-popover'
        }`}
      >
        {t('allTasks.filterByTag')} {selected.size > 0 && `(${selected.size})`}
        <ChevronDownIcon aria-hidden="true" className={`w-3 h-3 ms-1 transition-transform duration-150 ${open ? 'rotate-180' : ''}`} />
      </button>

      {/* Dropdown popover — portalled to escape overflow:hidden ancestors */}
      {open &&
        panelPos &&
        createPortal(
          <div
            ref={panelRef}
            style={{ position: 'fixed', top: panelPos.top, left: panelPos.left }}
            className="z-[var(--z-popover)] w-[var(--popover-w-sm)] bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] overflow-hidden"
          >
            {/* Search */}
            <div className="p-2 border-b border-surface-3">
              {/* search type for SR + soft-keyboard. */}
              <input
                ref={searchRef}
                type="search"
                value={search}
                onChange={(e) => {
                  setSearch(e.target.value);
                  setFocusedIndex(-1);
                }}
                onKeyDown={handleSearchKeyDown}
                onFocus={() => setSearchFocused(true)}
                onBlur={() => setSearchFocused(false)}
                placeholder={t('tags.searchPlaceholder')}
                aria-label={t('tags.searchPlaceholder')}
                role="combobox"
                aria-autocomplete="list"
                aria-expanded={open && filteredTags.length > 0}
                aria-controls={listboxId}
                aria-activedescendant={searchActiveDescendantId}
                className="w-full bg-surface-2 text-text-primary text-xs px-2.5 py-1.5 rounded-r-control border border-surface-3 outline-hidden focus-ring-soft"
              />
            </div>

            {/* Tag list */}
            <div
              className="max-h-48 overflow-y-auto overscroll-contain p-1"
              role="listbox"
              aria-orientation="vertical"
              id={listboxId}
              aria-label={t('allTasks.filterByTag')}
              aria-multiselectable="true"
              aria-activedescendant={activeDescendantId}
              onKeyDown={handleListKeyDown}
            >
              {filteredTags.length === 0 ? (
                <p className="text-text-muted text-xs px-2.5 py-2 text-center">
                  {t('common.noResults')}
                </p>
              ) : (
                filteredTags.map((tag, i) => {
                  const isSelected = selected.has(tag);
                  return (
                    <div
                      ref={setOptionRef(i)}
                      key={tag}
                      id={`${optionIdPrefix}-${i}`}
                      role="option"
                      aria-selected={isSelected}
                      tabIndex={focusedIndex === i ? 0 : -1}
                      onClick={() => handleToggle(tag)}
                      onKeyDown={(e) => {
                        // Parent listbox owns arrow-key navigation;
                        // local Enter/Space toggles when focus is on
                        // an option directly (a11y baseline).
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          handleToggle(tag);
                        }
                      }}
                      onFocus={() => setFocusedIndex(i)}
                      className={`w-full text-start text-xs px-2.5 py-1.5 rounded-r-control transition-colors flex items-center gap-2 focus-ring-soft ${
                        isSelected
                          ? 'bg-accent/10 text-accent'
                          : 'text-text-secondary hover:bg-surface-2'
                      }`}
                    >
                      <span
                        className={`w-3.5 h-3.5 rounded-r-control border flex items-center justify-center shrink-0 ${
                          isSelected ? 'border-accent bg-accent/20' : 'border-surface-3'
                        }`}
                      >
                        {isSelected && <CheckIcon className="text-accent w-2.5 h-2.5" />}
                      </span>
                      <span className="truncate">{tag}</span>
                    </div>
                  );
                })
              )}
            </div>

            {/* Footer: selected count + clear */}
            {selected.size > 0 && (
              <div className="border-t border-surface-3 px-2.5 py-1.5 flex items-center justify-between">
                <span className="text-text-muted text-xs">
                  {selected.size} {t('tags.selected')}
                </span>
                <button
                  type="button"
                  onClick={() => {
                    onClear();
                  }}
                  className="text-xs text-text-muted hover:text-text-primary focus-ring-soft rounded-r-control"
                >
                  {t('allTasks.clearTagFilter')}
                </button>
              </div>
            )}
          </div>,
          document.body,
        )}

      {/* Selected tag pills (inline, compact, removable) */}
      {selectedArr.map((tag) => (
        <Tooltip key={tag} label={t('allTasks.clearTagFilter')}>
          <button
            type="button"
            onClick={() => onToggle(tag)}
            aria-label={`${t('allTasks.clearTagFilter')}: ${tag}`}
            title={tag}
            className={`inline-flex max-w-[min(14rem,100%)] min-w-0 items-center gap-1 text-xs px-2 py-0.5 rounded-full border transition-colors focus-ring-soft ${PILL_ACTIVE}`}
          >
            <span className="min-w-0 truncate">{tag}</span>
            <XIcon className="w-2.5 h-2.5 shrink-0" />
          </button>
        </Tooltip>
      ))}

      {/* Clear all (shown inline when 2+ tags selected) */}
      {selected.size > 1 && (
        <button
          type="button"
          onClick={onClear}
          className="text-xs px-2 py-0.5 text-text-muted hover:text-text-primary focus-ring-soft rounded-r-control"
        >
          {t('allTasks.clearTagFilter')}
        </button>
      )}
    </div>
  );
}
