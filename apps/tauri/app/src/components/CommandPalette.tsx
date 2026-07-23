import { useEffect, useRef } from 'react';
import { useI18n, type TranslationKey } from '../lib/i18n';
import { useReducedMotion } from '@/lib/reducedMotion';
import { formatShortcut } from '../lib/shortcuts';
import TaskResult from './command-palette/TaskResult';
import { getPaletteOptionId } from './command-palette/model';
import type { CommandPaletteProps, KeyedResult, PaletteSection } from './command-palette/types';
import { useCommandPaletteController } from './command-palette/useCommandPaletteController';
import { Modal } from './ui/Modal';
import { isTerminalStatus } from '@lorvex/shared/types';

// Render groups of consecutive same-kind results with a sticky heading.
// We deliberately keep the controller's ordering — re-grouping into a
// stable Tasks → Actions → Navigate order would require either a
// secondary fuzzy sort or new scoring; the controller already orders
// matches by relevance. Sections appear in whatever order the results
// arrive, which preserves the "best match first" feel.
function paletteSectionKey(section: PaletteSection): TranslationKey {
  switch (section) {
    case 'task': return 'palette.sectionTasks';
    case 'action': return 'palette.sectionActions';
    case 'nav': return 'palette.sectionNavigate';
    case 'recent': return 'palette.sectionRecents';
    case 'frequent': return 'palette.sectionFrequent';
  }
}

/**
 * Resolve a result's editorial section. Items with an explicit
 * `section` override (recents / frequent surfaced by the
 * empty-query flow) take precedence; everything else falls back to
 * the structural `kind` so the existing live-search grouping stays
 * intact.
 */
function paletteSectionFor(entry: KeyedResult): PaletteSection {
  return entry.section ?? entry.item.kind;
}

/**
 * Inline section-header glyph for each result kind. A small leading
 * icon at the section header lets the reader's eye land on "what kind
 * of thing am I looking at" before it parses any text. Three small SVGs (no
 * dependency on the shared icons.tsx tree) — pinned at 12×12 so they
 * sit on the same optical baseline as the uppercase 2xs section
 * label.
 */
function PaletteSectionIcon({ section }: { section: PaletteSection }) {
  const className = 'w-3 h-3 shrink-0 text-text-muted/60';
  switch (section) {
    case 'task':
      return (
        <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="2.5" y="3.5" width="11" height="9" rx="2" />
          <path d="M5.5 8l1.8 1.8L11 6" />
        </svg>
      );
    case 'action':
      return (
        <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M8 1.5l1.6 4.5h4.7l-3.8 2.8 1.5 4.7L8 10.6l-4 2.9 1.5-4.7L1.7 6h4.7L8 1.5z" />
        </svg>
      );
    case 'nav':
      return (
        <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <circle cx="8" cy="8" r="5.5" />
          <path d="M8 2.5L9.5 8 8 13.5 6.5 8z" />
          <path d="M2.5 8h11" />
        </svg>
      );
    case 'recent':
      return (
        <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <circle cx="8" cy="8" r="5.5" />
          <path d="M8 4.5V8l2.4 1.5" />
        </svg>
      );
    case 'frequent':
      return (
        <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M2.5 12.5h2v-4h-2zM6.5 12.5h2V6h-2zM10.5 12.5h2V3h-2z" />
        </svg>
      );
  }
}

export default function CommandPalette(props: CommandPaletteProps) {
  const { t, format } = useI18n();
  const inputRef = useRef<HTMLInputElement>(null);
  const closeShortcut = formatShortcut(['Esc']);
  const paletteListboxId = 'command-palette-results';
  const {
    activeOptionId,
    activate,
    clearMoveTask,
    handleKeyDown,
    inScopedListMode,
    isSearching,
    keyedResults,
    moveTask,
    movingTaskTitle,
    optionRefs,
    query,
    results,
    selectedScopedList,
    selectedTask,
    setIsComposing,
    setQuery,
    visualSelectedIdx,
  } = useCommandPaletteController(props);
  const reducedMotion = useReducedMotion();

  // Scroll the highlighted option into view when navigating with keyboard.
  // Use `behavior: 'instant'` instead of the implicit `'auto'`
  // (which honors `scroll-behavior: smooth` from any ancestor). With
  // smooth scrolling, holding ↓ to fast-skim a long results list left
  // the highlighted row visually trailing behind the active descendant
  // by several frames — and macOS Safari's smooth scroller compounds
  // queued scrolls, so a long press could end with the listbox parked
  // on a row that no longer matched `activeOptionId`. Instant scroll
  // keeps the listbox locked to the keyboard cursor on every keystroke.
  useEffect(() => {
    if (activeOptionId) {
      optionRefs.current.get(activeOptionId)?.scrollIntoView({ block: 'nearest', behavior: 'instant' });
    }
  }, [activeOptionId, optionRefs]);

  return (
    <Modal
      open
      onClose={props.onClose}
      size="lg"
      align="items-start justify-center pt-[15vh]"
      ariaLabel={t('palette.placeholder')}
      // route focus through Modal's `focusTarget` instead of
      // a local `useEffect(() => inputRef.current?.focus())`. This is the
      // canonical pattern (see `Modal.focusTarget` doc) — eliminates
      // the historical "autoFocus={false} + manual focus effect" pair
      // that has been a recurring deps-bug surface ( in
      // QuickCaptureForm was the same shape).
      focusTarget={inputRef}
    >
      <div className="flex items-center gap-3 px-5 py-3.5 border-b border-card">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" className="text-text-muted shrink-0">
          <circle cx="7" cy="7" r="5" stroke="currentColor" strokeWidth="1.5" />
          <path d="M11 11L14 14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
        {/* search type for SR + soft-keyboard. */}
        <input
          ref={inputRef}
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onCompositionStart={() => setIsComposing(true)}
          onCompositionEnd={() => setIsComposing(false)}
          onKeyDown={handleKeyDown}
          placeholder={t('palette.placeholder')}
          aria-label={t('palette.placeholder')}
          role="combobox"
          aria-autocomplete="list"
          // Per WAI-ARIA combobox pattern, `aria-expanded`
          // reflects whether the listbox is *displayed*, not whether
          // it currently contains options. The previous
          // `keyedResults.length > 0` form flipped expanded → false
          // mid-typing whenever filtering produced an empty set, which
          // AT then announced as "collapsed" even though the listbox
          // panel was still on screen rendering an empty-state row
          // (or a "create task: foo" affordance). The palette is open
          // whenever this component is mounted, so hard-code true.
          aria-expanded={true}
          aria-controls={paletteListboxId}
          aria-activedescendant={activeOptionId ?? undefined}
          className="flex-1 bg-transparent text-text-primary text-base placeholder:text-text-muted/70 outline-hidden"
        />
      </div>
      {moveTask && (
        <div className="px-4 py-2 border-b border-surface-3 bg-accent/5 text-xs text-text-secondary flex items-center justify-between gap-3">
          <span className="truncate">
            {t('task.list')}: <span className="text-text-primary">{movingTaskTitle}</span>
          </span>
          <button
            type="button"
            onClick={clearMoveTask}
            className="text-text-muted hover:text-text-primary transition-colors rounded-r-control focus-ring-soft"
          >
            {t('common.cancel')}
          </button>
        </div>
      )}

      {/* polite aria-live region that announces search
          state changes to screen readers. The visible Searching… /
          No results blocks inside the listbox below drive the UI,
          but screen readers get the narrated count / loading state
          from this status line. Visually hidden via sr-only. */}
      <div role="status" aria-live="polite" aria-atomic="true" className="sr-only">
        {query.length >= 1 && !inScopedListMode && isSearching
          ? t('palette.searching')
          : query.length >= 1 && results.length === 0
            ? t('palette.a11yNoResults')
            : query.length >= 1 && results.length === 1
              ? t('palette.a11yOneResult')
              : query.length >= 1 && results.length > 1
                ? format('palette.a11yResultCount', { count: results.length })
                : ''}
      </div>

      <div
        id={paletteListboxId}
        role="listbox"
        aria-label={t('palette.placeholder')}
        aria-orientation="vertical"
        aria-busy={isSearching && query.length >= 1 && !inScopedListMode}
        className="max-h-80 overflow-y-auto overscroll-contain"
      >
        {query.length === 0 && !moveTask && !inScopedListMode && (
          <div className="px-5 py-3 border-b border-card flex items-center justify-center gap-4 text-text-muted/70 text-2xs select-none">
            <span>{t('palette.tipSearch')}</span>
            <span className="text-surface-3">|</span>
            <span>{t('palette.tipListFilter')}</span>
            <span className="text-surface-3">|</span>
            <span>{t('palette.tipShortcuts')}</span>
          </div>
        )}
        {isSearching && query.length >= 1 && !inScopedListMode ? (
          <div className="px-4 py-8 flex flex-col items-center gap-2 text-text-muted text-sm">
            <svg className={`${reducedMotion ? '' : 'animate-spin'} h-4 w-4 text-accent/50`} viewBox="0 0 24 24" fill="none">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
            {t('palette.searching')}
          </div>
        ) : results.length === 0 && query.length >= 1 ? (
          <div className="px-4 py-6 flex flex-col items-center gap-3">
            <p className="text-text-muted text-sm">{t('common.noResults')} &ldquo;{query}&rdquo;</p>
            <button
              type="button"
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => props.onQuickCapture({ title: query })}
              className="inline-flex items-center gap-2 px-3 py-1.5 rounded-r-card bg-[var(--accent-tint-sm)] hover:bg-[var(--accent-tint-md)] text-accent text-sm font-medium focus-ring-soft transition-colors"
            >
              <span>{format('palette.createTaskCta', { query })}</span>
              <span className="text-2xs text-accent/70 bg-surface-3/60 px-1.5 py-0.5 rounded-r-control font-mono">{formatShortcut(['Enter'])}</span>
            </button>
          </div>
        ) : (
          // <button role="option"> is a WAI-ARIA
          // contradiction — listbox children must be plain options
          // with no implicit role conflict. JAWS / NVDA narrate the
          // native button role *and* the option role, leading to
          // double announcements ("button, option, list item"). Use a
          // <div role="option"> instead; keyboard activation already
          // flows through the input's onKeyDown via
          // aria-activedescendant + handleKeyDown. Pointer activation
          // is wired with onClick + onMouseDown(prevent default) so
          // the search input keeps focus during selection.
          renderSectionedResults(keyedResults, {
            visualSelectedIdx,
            activate,
            optionRefs,
            selectedTask: selectedTask ?? undefined,
            t,
            format,
          })
        )}
      </div>

      <div className="px-5 py-2.5 border-t border-card text-text-muted/60 text-2xs flex flex-wrap gap-4">
        <span>{t('common.navigate')}</span>
        <span>{t('common.select')}</span>
        <span>{closeShortcut} {t('common.close')}</span>
        {moveTask ? (
          <span>{formatShortcut(['Esc'])} {t('common.cancel')}</span>
        ) : inScopedListMode ? (
          <>
            <span>@{t('task.list')}</span>
            {selectedScopedList && (
              <>
                <span>{formatShortcut(['Mod', 'Enter'])} {t('palette.shelveListToSomeday')}</span>
                <span>{formatShortcut(['Shift', 'Enter'])} {t('palette.deleteList')}</span>
              </>
            )}
          </>
        ) : query.length >= 1 && selectedTask ? (
          <>
            <span>{formatShortcut(['Mod', 'Enter'])} {isTerminalStatus(selectedTask.status) ? t('task.reopen') : t('task.complete')}</span>
            {!isTerminalStatus(selectedTask.status) && (
              <>
                <span>{formatShortcut(['Alt', 'Enter'])} {t('focus.notToday')}</span>
                <span>{formatShortcut(['Shift', 'Enter'])} {t('task.cancel')}</span>
                <span>{t('common.tabKey')} {t('task.list')}</span>
              </>
            )}
          </>
        ) : null}
      </div>
    </Modal>
  );
}

// Group consecutive same-kind items, render a sticky heading with the
// count for each group, and decorate the active row with an Enter kbd
// hint on the right. Sections appear in result order (best-match first)
// rather than a fixed Tasks → Lists → Actions → Navigate sequence —
// preserving relevance scoring is more useful than a rigid taxonomy.
function renderSectionedResults(
  keyedResults: KeyedResult[],
  {
    visualSelectedIdx,
    activate,
    optionRefs,
    selectedTask,
    t,
    format,
  }: {
    visualSelectedIdx: number;
    activate: (item: KeyedResult['item']) => void;
    optionRefs: React.MutableRefObject<Map<string, HTMLElement>>;
    selectedTask: import('@/lib/ipc/tasks/models').Task | undefined;
    t: ReturnType<typeof useI18n>['t'];
    format: ReturnType<typeof useI18n>['format'];
  },
): React.ReactNode {
  const groups: { section: PaletteSection; items: KeyedResult[]; startIndex: number }[] = [];
  keyedResults.forEach((entry, i) => {
    const section = paletteSectionFor(entry);
    const lastGroup = groups[groups.length - 1];
    if (lastGroup && lastGroup.section === section) {
      lastGroup.items.push(entry);
    } else {
      groups.push({ section, items: [entry], startIndex: i });
    }
  });
  let runningIndex = 0;
  return groups.map((group) => {
    const sectionLabel = t(paletteSectionKey(group.section));
    // Stable key: derive from the section + the first item's identity key
    // rather than the running start index. The startIndex flips on every
    // keystroke (items drift up/down), causing React to remount the
    // section <div> and thrash the sticky-header IntersectionObserver —
    // visible as section icons strobing when the user holds Down arrow.
    // First-item key is stable across edits that only reorder within a
    // section, which is the dominant case.
    const firstItemKey = group.items[0]?.key ?? `idx-${group.startIndex}`;
    return (
      <div key={`section-${group.section}-${firstItemKey}`} role="presentation">
        <div
          aria-hidden="true"
          className="sticky top-0 z-[var(--z-elevated)] bg-[var(--surface-sticky-bg)] backdrop-blur-sm px-5 py-1.5 text-2xs font-medium text-text-muted/80 uppercase tracking-wider flex items-center justify-between border-b border-card"
        >
          <span className="inline-flex items-center gap-2">
            <PaletteSectionIcon section={group.section} />
            {sectionLabel}
          </span>
          <span className="tabular-nums opacity-70">{format('palette.a11yResultCount', { count: group.items.length })}</span>
        </div>
        {group.items.map(({ item, key }) => {
          const index = runningIndex++;
          const isSelected = index === visualSelectedIdx;
          return (
            // eslint-disable-next-line jsx-a11y/click-events-have-key-events
            <div
              key={key}
              id={getPaletteOptionId(key)}
              ref={(node) => {
                const optionId = getPaletteOptionId(key);
                if (node) {
                  optionRefs.current.set(optionId, node);
                } else {
                  optionRefs.current.delete(optionId);
                }
              }}
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => activate(item)}
              role="option"
              aria-selected={isSelected}
              className={`group/palette w-full flex items-center gap-3 px-5 py-2.5 text-start cursor-pointer transition-colors duration-100 ${
                isSelected ? 'bg-[var(--accent-tint-sm)]' : 'hover:bg-surface-3/60'
              }`}
            >
              {item.kind === 'task' ? (
                <>
                  <span aria-hidden="true" className="w-4 h-4 inline-flex items-center justify-center text-text-muted/70">
                    <svg viewBox="0 0 16 16" width="14" height="14" fill="none">
                      <rect x="2" y="3" width="12" height="10" rx="2" stroke="currentColor" strokeWidth="1.3" />
                      <path d="M5 8l2 2 4-4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </span>
                  <div className="min-w-0 flex-1">
                    <TaskResult task={item.task} />
                  </div>
                </>
              ) : (
                <>
                  <span className="text-base w-6 text-center opacity-70" aria-hidden="true">{item.icon}</span>
                  <span className="text-sm text-text-primary font-medium flex-1 truncate">{item.label}</span>
                  {'shortcut' in item && item.shortcut && (
                    <span className="text-2xs text-text-muted/60 bg-surface-3/50 px-2 py-0.5 rounded-r-control font-mono">{item.shortcut}</span>
                  )}
                </>
              )}
              {/* Enter kbd glyph reveals on hover/active so users learn
                  the keyboard affordance without cluttering the resting
                  state. Tasks also surface their primary chord
                  (⌘↩ for complete) when active. */}
              <span
                className={`ms-1 inline-flex items-center gap-1.5 text-2xs text-text-muted/60 ${
                  isSelected ? 'opacity-100' : 'opacity-0 group-hover/palette:opacity-100'
                } transition-opacity`}
                aria-hidden="true"
              >
                <span className="bg-surface-3/60 px-1.5 py-0.5 rounded-r-control font-mono">{formatShortcut(['Enter'])}</span>
                {item.kind === 'task' && selectedTask && selectedTask.id === item.task.id && !isTerminalStatus(item.task.status) && (
                  <span className="bg-surface-3/60 px-1.5 py-0.5 rounded-r-control font-mono">{formatShortcut(['Mod', 'Enter'])}</span>
                )}
              </span>
            </div>
          );
        })}
      </div>
    );
  });
}

