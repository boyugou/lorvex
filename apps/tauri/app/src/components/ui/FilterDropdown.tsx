import { createPortal } from 'react-dom';
import { useEffect, useId, useRef, useState } from 'react';
import { themedSwatch } from '@/lib/colors/themedSwatch';
import { CheckIcon, ChevronDownIcon } from './icons';
import {
  advanceFilterDropdownTypeAhead,
  clearFilterDropdownTypeAhead,
  createBrowserFilterDropdownTypeAheadTimerHost,
  scheduleFilterDropdownInitialFocus,
  type FilterDropdownTypeAheadState,
} from './FilterDropdown.runtime';
import {
  createBrowserPortalDropdownDismissRuntimeDeps,
  resolveAnchoredPopupPosition,
  startPortalDropdownDismissRuntime,
} from './portalDropdown.runtime';

/*
 * estimated panel height for the viewport-bottom flip-up
 * decision. Each option row is ~28px (text-xs px-2.5 py-1.5 +
 * 4px transition padding) plus the panel's 8px vertical padding
 * (`p-1` x2). We cap at 256px to mirror the listbox max-height
 * convention so even option-heavy filters (sort, status) flip
 * predictably. Used only to pick top vs bottom — the actual panel
 * is still allowed to be shorter than the cap.
 */
const FILTER_DROPDOWN_OPTION_ROW_PX = 28;
const FILTER_DROPDOWN_PANEL_PADDING_PX = 8;
const FILTER_DROPDOWN_MAX_PANEL_HEIGHT_PX = 256;

function estimateFilterDropdownPanelHeight(optionCount: number): number {
  const contentHeight =
    optionCount * FILTER_DROPDOWN_OPTION_ROW_PX + FILTER_DROPDOWN_PANEL_PADDING_PX;
  return Math.min(FILTER_DROPDOWN_MAX_PANEL_HEIGHT_PX, contentHeight);
}

export interface FilterOption<T extends string> {
  value: T;
  label: string;
  icon?: string | undefined;
  color?: string | undefined;
}

interface FilterDropdownProps<T extends string> {
  label: string;
  value: T;
  options: FilterOption<T>[];
  onChange: (value: T) => void;
  /** Optional suffix shown after the selected label (e.g. sort direction arrow) */
  suffix?: React.ReactNode;
  /** Optional interactive action rendered adjacent to, not inside, the trigger. */
  trailingAction?: React.ReactNode;
}

const filterDropdownTypeAheadTimerHost = createBrowserFilterDropdownTypeAheadTimerHost();

export function FilterDropdown<T extends string>({
  label,
  value,
  options,
  onChange,
  suffix,
  trailingAction,
}: FilterDropdownProps<T>) {
  const [open, setOpen] = useState(false);
  const [panelPos, setPanelPos] = useState<{ top: number; left: number } | null>(null);
  const [focusedIndex, setFocusedIndex] = useState(0);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const optionRefs = useRef<(HTMLDivElement | null)[]>([]);
  const typeAheadRef = useRef<FilterDropdownTypeAheadState>({ timer: null, buffer: '' });
  const listboxId = useId();
  const optionIdPrefix = useId();

  // Clear the type-ahead timer on unmount so a keystroke within the
  // 500ms window followed by unmount doesn't leave a pending timer
  // mutating a detached ref.
  // We deliberately read `typeAheadRef.current` at cleanup time so we
  // clear whatever timer was last set, not the one present at mount.
  useEffect(() => {
    return () => {
      clearFilterDropdownTypeAhead(
        // eslint-disable-next-line react-hooks/exhaustive-deps
        typeAheadRef.current,
        filterDropdownTypeAheadTimerHost.clearTimeout,
      );
    };
  }, []);

  useEffect(() => {
    if (open) return;
    clearFilterDropdownTypeAhead(
      typeAheadRef.current,
      filterDropdownTypeAheadTimerHost.clearTimeout,
    );
  }, [open]);

  useEffect(() => {
    if (!open) return;
    return startPortalDropdownDismissRuntime(
      createBrowserPortalDropdownDismissRuntimeDeps({
        getTrigger: () => triggerRef.current,
        getPanel: () => panelRef.current,
        onDismiss: () => setOpen(false),
      }),
    );
  }, [open]);

  // Focus first/selected option when panel opens
  useEffect(() => {
    if (!open) return;
    const idx = Math.max(0, options.findIndex((o) => o.value === value));
    setFocusedIndex(idx);
    return scheduleFilterDropdownInitialFocus({
      requestAnimationFrame: (callback) => window.requestAnimationFrame(callback),
      cancelAnimationFrame: (handle) => window.cancelAnimationFrame(handle as number),
      focusOption: () => {
        optionRefs.current[idx]?.focus();
      },
    });
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps -- focus only on open change, not on value/options

  const handleToggle = () => {
    if (!open && triggerRef.current) {
      const rect = triggerRef.current.getBoundingClientRect();
      setPanelPos(
        resolveAnchoredPopupPosition({
          rect,
          viewportWidth: window.innerWidth,
          viewportHeight: window.innerHeight,
          popupWidth: 160,
          popupHeight: estimateFilterDropdownPanelHeight(options.length),
          flipVertically: true,
        }),
      );
    }
    setOpen((prev) => !prev);
  };

  const selectAndClose = (idx: number) => {
    const option = options[idx];
    if (option) {
      onChange(option.value);
      setOpen(false);
      triggerRef.current?.focus();
    }
  };

  const handleTypeAhead = (char: string) => {
    const matchIndex = advanceFilterDropdownTypeAhead({
      state: typeAheadRef.current,
      typedChar: char,
      options,
      focusedIndex,
      timerHost: filterDropdownTypeAheadTimerHost,
    });

    if (matchIndex !== null) {
      setFocusedIndex(matchIndex);
      optionRefs.current[matchIndex]?.focus();
    }
  };

  const handlePanelKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      setOpen(false);
      triggerRef.current?.focus();
      return;
    }
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      selectAndClose(focusedIndex);
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      const next = Math.min(focusedIndex + 1, options.length - 1);
      setFocusedIndex(next);
      optionRefs.current[next]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const prev = Math.max(focusedIndex - 1, 0);
      setFocusedIndex(prev);
      optionRefs.current[prev]?.focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      setFocusedIndex(0);
      optionRefs.current[0]?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      const last = options.length - 1;
      setFocusedIndex(last);
      optionRefs.current[last]?.focus();
    } else if (e.key === 'Tab') {
      // Close on Tab to allow natural tab order
      setOpen(false);
    } else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      // Type-ahead: printable character
      e.preventDefault();
      handleTypeAhead(e.key);
    }
  };

  const selectedOption = options.find((o) => o.value === value);
  const selectedLabel = selectedOption?.label ?? value;
  const hasNonDefault = options.length > 0 && value !== options[0]?.value;
  const activeDescendantId = open && focusedIndex >= 0 ? `${optionIdPrefix}-${focusedIndex}` : undefined;

  return (
    <>
      <span className="inline-flex items-center gap-1">
        <button
          ref={triggerRef}
          type="button"
          onClick={handleToggle}
          aria-expanded={open}
          aria-haspopup="listbox"
          aria-controls={open ? listboxId : undefined}
          className={`text-xs px-2.5 py-1 rounded-r-control border transition-colors focus-ring-soft inline-flex items-center gap-1.5 ${
            hasNonDefault
              ? 'border-accent/40 bg-accent/10 text-accent'
              : 'border-surface-3 text-text-muted hover:text-text-primary hover:border-popover'
          }`}
        >
          <span className="text-text-muted">{label}:</span>
          {selectedOption?.color && (
            <span
              className="w-1.5 h-1.5 rounded-full shrink-0"
              style={{ backgroundColor: themedSwatch(selectedOption.color, 'dot') }}
            />
          )}
          {selectedOption?.icon && <span>{selectedOption.icon}</span>}
          <span>{selectedLabel}</span>
          {suffix}
          <ChevronDownIcon aria-hidden="true" className={`w-3 h-3 ms-0.5 transition-transform duration-150 ${open ? 'rotate-180' : ''}`} />
        </button>
        {trailingAction}
      </span>

      {open &&
        panelPos &&
        createPortal(
          <div
            ref={panelRef}
            style={{ position: 'fixed', top: panelPos.top, left: panelPos.left }}
            className="z-[var(--z-popover)] min-w-[var(--menu-min-w-sm)] max-h-64 overflow-y-auto bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)]"
            role="listbox"
            aria-orientation="vertical"
            id={listboxId}
            aria-label={label}
            aria-activedescendant={activeDescendantId}
            onKeyDown={handlePanelKeyDown}
          >
            <div className="p-1">
              {options.map((option, i) => {
                const isSelected = option.value === value;
                return (
                  <div
                    ref={(el) => { optionRefs.current[i] = el; }}
                    key={option.value}
                    id={`${optionIdPrefix}-${i}`}
                    role="option"
                    aria-selected={isSelected}
                    tabIndex={focusedIndex === i ? 0 : -1}
                    onClick={() => {
                      onChange(option.value);
                      setOpen(false);
                      triggerRef.current?.focus();
                    }}
                    onKeyDown={(e) => {
                      // Parent listbox owns navigation via
                      // aria-activedescendant; local Enter/Space keeps
                      // activation working when focus is on an option
                      // directly (a11y baseline).
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        onChange(option.value);
                        setOpen(false);
                        triggerRef.current?.focus();
                      }
                    }}
                    onFocus={() => setFocusedIndex(i)}
                    className={`w-full text-start text-xs px-2.5 py-1.5 rounded-r-control transition-colors flex items-center gap-2 focus-ring-soft ${
                      isSelected
                        ? 'bg-accent/10 text-accent'
                        : 'text-text-secondary hover:bg-surface-2'
                    }`}
                  >
                    {option.color && (
                      <span
                        className="w-1.5 h-1.5 rounded-full shrink-0"
                        style={{ backgroundColor: themedSwatch(option.color, 'dot') }}
                      />
                    )}
                    {option.icon && <span>{option.icon}</span>}
                    <span className="truncate">{option.label}</span>
                    {isSelected && <CheckIcon className="ms-auto text-accent w-2.5 h-2.5 shrink-0" />}
                  </div>
                );
              })}
            </div>
          </div>,
          document.body,
        )}
    </>
  );
}
