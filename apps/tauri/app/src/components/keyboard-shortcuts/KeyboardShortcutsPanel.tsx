import { useEffect, useMemo, useState } from 'react';
import { formatShortcut } from '@/lib/shortcuts';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { isEditableTarget } from '@/lib/editableTarget';
import { isMacRuntime } from '@/lib/platform/platform';
import { Modal } from '../ui/Modal';
import { installKeyboardShortcutsPanelCloseRuntime } from './KeyboardShortcutsPanel.runtime';

interface KeyboardShortcutsPanelProps {
  onClose: () => void;
}

const IS_MAC = isMacRuntime();
const MOD = IS_MAC ? '⌘' : 'Ctrl+';
const SHIFT = IS_MAC ? '⇧' : 'Shift+';
const ALT = IS_MAC ? '⌥' : 'Alt+';

// on non-macOS the Settings and Daily Review
// bindings are remapped server-side (see app_menu.rs) because Ctrl+,
// and Ctrl+0 collide with WebView2 defaults. Keep the panel labels
// in sync so we don't advertise a combo the user can't actually
// press. Someday moved to ⌘4 in so it no longer needs the ⌘⇧0
// fallback — Daily Review inherits it.
const SETTINGS_KEYS = IS_MAC ? `${MOD},` : `${MOD};`;
const DAILY_REVIEW_KEYS = IS_MAC ? `${MOD}0` : `${SHIFT}${MOD}0`;

// Type the i18n keys as `TranslationKey` (not raw `string`) so the
// table is statically validated against the translation registry —
// any drift between this file and `locales/*.ts` surfaces at build
// instead of becoming a runtime miss.
interface ShortcutGroup {
  titleKey: TranslationKey;
  items: { keys: string; labelKey: TranslationKey }[];
}

/**
 * Map from shortcut label to scope hint suffix. Some bare-key chords
 * (`t`, `m`) are intentionally overloaded across the task-list and
 * calendar views — the same physical key drives a different action
 * depending on which surface owns focus. Appending the scope after the
 * label disambiguates the table without expanding the chord glyphs.
 */
const SCOPE_HINT_BY_LABEL: Partial<Record<TranslationKey, TranslationKey>> = {
  'shortcuts.setDueDate': 'shortcuts.scopeHintTasks',
  'shortcuts.moveToList': 'shortcuts.scopeHintTasks',
  'shortcuts.calendarToday': 'shortcuts.scopeHintCalendar',
  'shortcuts.calendarToggleView': 'shortcuts.scopeHintCalendar',
};

// hoisted to module scope so the array (and every group +
// item literal underneath) is allocated once at module load instead
// of on every render. The shortcut tables are i18n-key references,
// not pre-translated strings, so the only locale-sensitive lookup is
// the `t(...)` call at render time — the data itself is invariant.
const GROUPS: readonly ShortcutGroup[] = [
    {
      // keep this list in the same order as
      // `SECONDARY_MODULES` in `app/src/components/sidebar/
      // secondaryModules.tsx`. The user-facing scheme is:
      // ⌘1–⌘4 primary, ⌘5–⌘0 secondary digit row, ⌘⇧-letter for
      // the rest. See the header doc in secondaryModules.tsx for
      // the rationale.
      titleKey: 'shortcuts.navigation',
      items: [
        // Primary ⌘1–⌘4
        { keys: `${MOD}1`, labelKey: 'nav.today' },
        { keys: `${MOD}2`, labelKey: 'nav.upcoming' },
        { keys: `${MOD}3`, labelKey: 'nav.allTasks' },
        { keys: `${MOD}4`, labelKey: 'nav.someday' },
        // Secondary digit row ⌘5–⌘0
        { keys: `${MOD}5`, labelKey: 'nav.calendar' },
        { keys: `${MOD}6`, labelKey: 'nav.eisenhower' },
        { keys: `${MOD}7`, labelKey: 'nav.kanban' },
        { keys: `${MOD}8`, labelKey: 'nav.habits' },
        { keys: DAILY_REVIEW_KEYS, labelKey: 'nav.daily_review' },
        // Secondary ⌘⇧-letter row
        { keys: `${SHIFT}${MOD}M`, labelKey: 'nav.memory' },
        { keys: `${SHIFT}${MOD}D`, labelKey: 'nav.dependencies' },
        { keys: `${SHIFT}${MOD}A`, labelKey: 'nav.changelog' },
        { keys: `${SHIFT}${MOD}W`, labelKey: 'nav.review' },
        { keys: `${SHIFT}${MOD}R`, labelKey: 'nav.recurring' },
      ],
    },
    {
      titleKey: 'shortcuts.actions',
      items: [
        { keys: `${MOD}N`, labelKey: 'shortcuts.quickCapture' },
        { keys: `${MOD}K`, labelKey: 'shortcuts.commandPalette' },
        { keys: `${MOD}Z`, labelKey: 'shortcuts.undoLastAction' },
        { keys: `${SHIFT}${MOD}F`, labelKey: 'shortcuts.focusMode' },
        { keys: SETTINGS_KEYS, labelKey: 'nav.settings' },
        // the shortcut to OPEN this panel was missing
        // from the panel itself. Users had to discover it via the `?`
        // titlebar button (conditional on runtimeProfile). Now self-
        // documenting.
        { keys: '?', labelKey: 'shortcuts.openHelp' },
        { keys: 'Esc', labelKey: 'shortcuts.closePanel' },
      ],
    },
    {
      titleKey: 'shortcuts.taskList',
      items: [
        { keys: 'j / ↓', labelKey: 'shortcuts.nextTask' },
        { keys: 'k / ↑', labelKey: 'shortcuts.prevTask' },
        { keys: '↵', labelKey: 'shortcuts.openTask' },
        { keys: 'Space', labelKey: 'shortcuts.bulkSelectToggle' },
        { keys: 'Esc', labelKey: 'shortcuts.exitBulkSelect' },
        { keys: 'x', labelKey: 'shortcuts.completeToggle' },
        { keys: 'c', labelKey: 'shortcuts.cancelTask' },
        { keys: 's', labelKey: 'shortcuts.deferTomorrow' },
        { keys: 'S', labelKey: 'shortcuts.deferNextWeek' },
        { keys: 'e', labelKey: 'shortcuts.editTitle' },
        { keys: 'd', labelKey: 'shortcuts.dueToday' },
        { keys: 'D', labelKey: 'shortcuts.dueTomorrow' },
        { keys: 'r', labelKey: 'shortcuts.toggleRecurrence' },
        { keys: 'R', labelKey: 'shortcuts.setRecurrence' },
        { keys: 't', labelKey: 'shortcuts.setDueDate' },
        { keys: 'w', labelKey: 'shortcuts.setDuration' },
        { keys: 'a', labelKey: 'shortcuts.promoteToActive' },
        { keys: 'f', labelKey: 'shortcuts.focusTask' },
        { keys: 'y', labelKey: 'shortcuts.duplicate' },
        { keys: 'm', labelKey: 'shortcuts.moveToList' },
        { keys: '1–3', labelKey: 'shortcuts.setPriority' },
        { keys: `. / ${SHIFT}F10`, labelKey: 'shortcuts.contextMenu' },
        { keys: `${ALT}↑↓`, labelKey: 'shortcuts.reorderTask' },
        { keys: `${MOD}←→ (Kanban/Eisenhower) · ${MOD}↑↓ (Eisenhower)`, labelKey: 'shortcuts.moveInView' },
      ],
    },
    {
      titleKey: 'shortcuts.calendar',
      items: [
        { keys: '← →', labelKey: 'shortcuts.calendarNav' },
        { keys: 't', labelKey: 'shortcuts.calendarToday' },
        { keys: 'm', labelKey: 'shortcuts.calendarToggleView' },
      ],
    },
    {
      titleKey: 'shortcuts.commandPalette',
      items: [
        { keys: `${MOD}↵`, labelKey: 'shortcuts.paletteComplete' },
        { keys: `${SHIFT}↵`, labelKey: 'shortcuts.paletteCancel' },
        { keys: `${ALT}↵`, labelKey: 'shortcuts.paletteDefer' },
        { keys: 'Tab', labelKey: 'shortcuts.paletteMoveToList' },
      ],
    },
    {
      titleKey: 'shortcuts.taskDetail',
      items: [
        { keys: `${MOD}↵`, labelKey: 'shortcuts.detailComplete' },
        { keys: `${SHIFT}${MOD}↵`, labelKey: 'shortcuts.detailDefer' },
        { keys: 'Esc', labelKey: 'shortcuts.detailClose' },
      ],
    },
    {
      titleKey: 'shortcuts.focusMode',
      items: [
        { keys: 'Escape', labelKey: 'shortcuts.focusExit' },
        { keys: `${MOD}↵`, labelKey: 'shortcuts.focusDone' },
        { keys: `${SHIFT}${MOD}↵`, labelKey: 'shortcuts.focusDefer' },
        { keys: `${MOD}]`, labelKey: 'shortcuts.focusSkip' },
        { keys: `${MOD}[`, labelKey: 'shortcuts.focusPrev' },
      ],
    },
] as const;

export default function KeyboardShortcutsPanel({ onClose }: KeyboardShortcutsPanelProps) {
  const { t } = useI18n();

  // Close on '?' key (Escape is handled by ModalShell).
  // guard bare-key listener so a `?` typed inside an
  // <input> / <textarea> / contentEditable nested below the panel
  // doesn't silently dismiss the panel. Also gate on modifier keys —
  // the panel toggles on plain `?` only; `⌘?` / `⌥?` etc. should
  // pass through to whatever else is listening.
  useEffect(() => {
    return installKeyboardShortcutsPanelCloseRuntime({
      addWindowKeydownListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            window.addEventListener('keydown', listener);
            return () => window.removeEventListener('keydown', listener);
          },
      isEditableTarget,
      onClose,
    });
  }, [onClose]);

  // Filter-input state. The shortcut table grew large enough that
  // scanning for a specific action (e.g. "context menu", "focus mode")
  // takes longer than typing the action's name. Filtering matches the
  // resolved label `t(item.labelKey)` and the printable key glyph
  // (`item.keys`) — both case-insensitively — so a user who remembers
  // either side of the table can find the row. Whole groups whose
  // items all filter out are hidden so the grid doesn't grow gaps.
  const [filter, setFilter] = useState('');
  const trimmedFilter = filter.trim().toLowerCase();
  const filteredGroups = useMemo(() => {
    if (!trimmedFilter) return GROUPS;
    return GROUPS
      .map((group) => ({
        ...group,
        items: group.items.filter((item) => {
          const label = t(item.labelKey).toLowerCase();
          const keys = item.keys.toLowerCase();
          return label.includes(trimmedFilter) || keys.includes(trimmedFilter);
        }),
      }))
      .filter((group) => group.items.length > 0);
  }, [trimmedFilter, t]);
  const groups = filteredGroups;
  const noMatches = trimmedFilter !== '' && groups.length === 0;

  return (
    <Modal
      open
      onClose={onClose}
      size="xl"
      zIndex="z-[var(--z-modal)]"
      panelClassName="max-h-[80vh] flex flex-col"
      ariaLabel={t('shortcuts.title')}
    >
      <div className="flex items-center justify-between gap-3 px-4 py-4 sm:px-6 border-b border-card">
        <h2 className="text-text-primary text-lg font-light min-w-0 flex-1 break-words">{t('shortcuts.title')}</h2>
        {/* the visible "Esc" label was hardcoded
            ASCII English. The shared `formatShortcut` helper in
            `lib/keyboard.ts` already canonicalizes platform-specific
            key glyphs (⌘/Ctrl, ⌥/Alt, ↵/Enter, etc.); routing the
            close affordance through it keeps the key glyph honest
            on every platform and lets a future locale override the
            key name (some locales render "Esc" as a different
            abbreviation). */}
        <button
          type="button"
          onClick={onClose}
          className="text-text-muted hover:text-text-primary transition-colors text-sm focus-ring-strong rounded-r-control px-2 py-0.5 shrink-0"
          aria-label={t('common.close')}
        >
          {formatShortcut(['Esc'])}
        </button>
      </div>
      {/* eslint-disable jsx-a11y/no-noninteractive-tabindex -- Keyboard users need focus on this scrollable region. */}
      <div className="px-4 sm:px-6 pt-3 pb-2 border-b border-card">
        <label className="block">
          <span className="sr-only">{t('shortcuts.filterLabel')}</span>
          <input
            type="search"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder={t('shortcuts.filterPlaceholder')}
            // mark the search input as inert from the
            // panel's `?`-to-close listener: typing into the input
            // would otherwise dismiss the modal whenever the user
            // hit `?`. The bare-key gate already excludes editable
            // targets, but spelling it out as `data-shortcut-skip`
            // documents intent for future readers.
            data-shortcut-skip="true"
            autoFocus
            className="w-full bg-surface-1 border border-card rounded-r-control px-3 py-1.5 text-sm text-text-primary placeholder:text-text-muted focus-ring-soft"
          />
        </label>
      </div>
      <div
        className="flex-1 overflow-y-auto p-4 sm:p-6"
        // give keyboard-only users access to the scroll
        // viewport. Without `tabIndex={0}` an `overflow-y-auto`
        // container is not in the tab order, so a user who can't
        // arrow-key inside any child element has no way to scroll
        // the panel content. `role="region"` + an `aria-label`
        // surfaces the scrollable area as a landmark to AT.
        tabIndex={0}
        role="region"
        aria-label={t('shortcuts.viewportLabel')}
      >
        {noMatches && (
          <p className="text-text-muted text-sm text-center py-8">
            {t('shortcuts.filterNoResults')}
          </p>
        )}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-6">
          {groups.map((group) => (
            <div key={group.titleKey}>
              <h3 className="text-text-muted text-xs mb-3 font-medium">
                {t(group.titleKey)}
              </h3>
              <div className="space-y-1.5">
                {group.items.map((item) => (
                  <div key={item.labelKey} className="flex items-center justify-between gap-3 min-w-0">
                    <span className="text-text-secondary text-sm min-w-0 flex-1 break-words">
                      {t(item.labelKey)}
                      {SCOPE_HINT_BY_LABEL[item.labelKey] && (
                        <span className="ms-1.5 text-text-muted/80 text-xs font-normal tabular-nums">
                          {t(SCOPE_HINT_BY_LABEL[item.labelKey]!)}
                        </span>
                      )}
                    </span>
                    <kbd className="text-xs text-text-muted bg-surface-3 px-2 py-0.5 rounded-r-control font-mono min-w-8 shrink-0 text-center">
                      {item.keys}
                    </kbd>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
      {/* eslint-enable jsx-a11y/no-noninteractive-tabindex */}
      <div className="px-6 py-3 border-t border-surface-3 text-center">
        <span className="text-text-muted text-xs">
          {t('shortcuts.hint')}
        </span>
      </div>
    </Modal>
  );
}
