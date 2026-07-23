import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import { useI18n } from '@/lib/i18n';
import { ClockIcon, CheckIcon } from '../ui/icons';
import { formatTimeDisplay } from './SettingsPrimitives.logic';
import {
  createBrowserTimeInputDropdownDismissRuntimeDeps,
  getNextTimeInputFocusIndex,
  getTimeInputInitialFocusIndex,
  installTimeInputDropdownDismissRuntime,
  resolveTimeInputDropdownPosition,
} from './SettingsPrimitives.runtime';

interface SettingsSectionProps {
  title: string;
  description?: string;
  children: ReactNode;
  collapsible?: boolean;
  defaultOpen?: boolean;
  /** Render as a lightweight sub-section (no outer border/bg), or danger for destructive actions. */
  variant?: 'panel' | 'subsection' | 'danger';
}

export function SettingsSection({
  title,
  description,
  children,
  collapsible = false,
  defaultOpen = true,
  variant = 'panel',
}: SettingsSectionProps) {
  const [open, setOpen] = useState(defaultOpen);
  const contentId = useId();
  const contentRef = useRef<HTMLDivElement>(null);
  // Track whether the section has ever been expanded. Heavy panels
  // mount TanStack-Query subtrees, biometric probes, and platform IPC
  // hooks at first render; for a collapsible section that starts
  // closed we defer that work until the first open, then keep
  // children mounted so re-collapsing doesn't tear the subtree down
  // (and so the in-flight transition we set up below has a stable
  // grid-row target). Non-collapsible sections always mount.
  const [mountedOnce, setMountedOnce] = useState(!collapsible || defaultOpen);

  useEffect(() => {
    setOpen(defaultOpen);
  }, [defaultOpen, title]);

  useEffect(() => {
    if (open) setMountedOnce(true);
  }, [open]);

  const toggle = collapsible ? () => setOpen((v) => !v) : undefined;

  const wrapperClass =
    variant === 'subsection'
      ? 'rounded-r-card border border-card bg-surface-2/20 px-4 py-3.5'
      : variant === 'danger'
        ? 'rounded-r-card border border-danger/25 bg-[var(--danger-tint-xs)] px-4 py-3.5'
        // Panel variant uses focus-within elevation, clamped to
        // `--z-elevated` (10). The panel sits inside
        // SettingsScopeTabs' `--z-sticky` (30) header, so taking
        // the sticky tier on focus-within would outrank the page's
        // own sticky chrome. Elevated is enough to lift the panel
        // above its sibling section dividers without colliding
        // with chrome.
        : 'liquid-settings-panel profile-material-panel relative z-0 focus-within:z-[var(--z-elevated)] rounded-r-card border border-surface-3 bg-surface-2/35 px-4 py-3.5';

  const titleClass =
    variant === 'danger'
      ? 'text-danger text-sm font-medium'
      : 'text-text-primary text-sm font-medium';

  return (
    <section className={wrapperClass}>
      {collapsible ? (
        <button
          type="button"
          onClick={toggle}
          className="flex w-full items-center justify-between gap-3 text-start hover:bg-surface-3/40 active:bg-surface-3/60 transition-colors focus-ring-soft rounded-r-control -mx-1 px-1"
          aria-expanded={open}
          aria-controls={contentId}
        >
          <h2 className={titleClass}>{title}</h2>
          <span
            className={`inline-flex h-6 w-6 items-center justify-center rounded-r-control text-text-muted transition-transform duration-150 ${open ? 'rotate-0' : '-rotate-90'}`}
            aria-hidden
          >
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M3 4.5L6 7.5L9 4.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </button>
      ) : (
        <h2 className={titleClass}>{title}</h2>
      )}
      {description && (
        <p className={`text-text-muted text-xs mt-1 ${open ? 'mb-3' : 'mb-0'}`}>{description}</p>
      )}
      {/*
        * grid-template-rows transition. `max-height: 0 ↔ max-height: none`
        * is not a transitionable value pair — `none` resolves to the
        * intrinsic content height as a keyword, so the browser short-
        * circuits the transition and the section snap-opens. The
        * canonical fix is a CSS Grid container collapsing from
        * `0fr` → `1fr` on the single row that holds the content: both
        * sides resolve to length values, so the interpolation animates.
        * We always render `children` (no `open && children` gate) so the
        * collapsed state can fall back gracefully if the grid trick is
        * unsupported and so the children's mount-time work doesn't fire
        * on every open. `aria-hidden` + the inner `invisible` keep
        * collapsed children out of the accessibility tree and focus
        * order without unmounting them.
        */}
      <div
        ref={contentRef}
        id={contentId}
        aria-hidden={!open}
        className={`grid transition-[grid-template-rows,opacity,margin] duration-200 ease-in-out ${
          open
            ? `grid-rows-[1fr] opacity-100 ${description ? 'mt-0' : 'mt-3'}`
            : 'grid-rows-[0fr] opacity-0 mt-0'
        }`}
      >
        <div className={`min-h-0 overflow-hidden ${open ? '' : 'invisible'}`}>
          {mountedOnce ? children : null}
        </div>
      </div>
    </section>
  );
}

// ── Time picker helpers ─────────────────────────────────────────────

/** Generate all 48 half-hour slots as HH:MM strings. */
function generateTimeSlots(): string[] {
  const slots: string[] = [];
  for (let h = 0; h < 24; h++) {
    for (const m of [0, 30]) {
      slots.push(`${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`);
    }
  }
  return slots;
}

const TIME_SLOTS = generateTimeSlots();

interface TimeInputProps {
  value: string;
  onChange: (v: string) => void;
  ariaLabel?: string | undefined;
  ariaLabelledBy?: string | undefined;
}

export function TimeInput({
  value,
  onChange,
  ariaLabel,
  ariaLabelledBy,
}: TimeInputProps) {
  const { locale } = useI18n();
  const listboxId = useId();
  const valueLabelId = useId();
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(() => getTimeInputInitialFocusIndex(value, TIME_SLOTS));
  const triggerRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const optionRefs = useRef<Array<HTMLDivElement | null>>([]);
  const [position, setPosition] = useState<{ top: number; left: number }>({ top: 0, left: 0 });

  const displayValue = formatTimeDisplay(value || '09:00', locale);
  const triggerAriaLabel = ariaLabel && !ariaLabelledBy ? `${ariaLabel}: ${displayValue}` : undefined;
  const triggerAriaLabelledBy = ariaLabelledBy ? `${ariaLabelledBy} ${valueLabelId}` : undefined;
  const selectedFocusIndex = getTimeInputInitialFocusIndex(value, TIME_SLOTS);
  const optionIdPrefix = `${listboxId}-option`;
  const activeDescendantId = open && activeIndex >= 0 ? `${optionIdPrefix}-${activeIndex}` : undefined;

  // Calculate dropdown position when opening
  useEffect(() => {
    if (!open || !triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    setPosition(resolveTimeInputDropdownPosition(rect, {
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
    }));
  }, [open]);

  // Focus and reveal the active option when keyboard navigation opens
  // or moves the popover. Pointer selection still flows through click.
  useEffect(() => {
    if (!open || activeIndex < 0) return;
    const raf = requestAnimationFrame(() => {
      const option = optionRefs.current[activeIndex];
      option?.focus();
      option?.scrollIntoView({ block: 'nearest' });
    });
    return () => cancelAnimationFrame(raf);
  }, [activeIndex, open]);

  const closeDropdown = useCallback((restoreFocus = false) => {
    setOpen(false);
    if (restoreFocus) {
      triggerRef.current?.focus();
    }
  }, []);

  const openDropdown = useCallback((focusIndex = getTimeInputInitialFocusIndex(value, TIME_SLOTS)) => {
    setActiveIndex(focusIndex);
    setOpen(true);
  }, [value]);

  // Close on Escape or outside click
  useEffect(() => {
    if (!open) return;

    return installTimeInputDropdownDismissRuntime(
      createBrowserTimeInputDropdownDismissRuntimeDeps({
        getTrigger: () => triggerRef.current,
        getPanel: () => listRef.current,
        onEscapeDismiss: () => {
          closeDropdown(true);
        },
        onPointerDismiss: () => closeDropdown(false),
        onScrollDismiss: () => closeDropdown(false),
        onResizeDismiss: () => closeDropdown(false),
      }),
    );
  }, [closeDropdown, open]);

  const handleSelect = useCallback((slot: string) => {
    onChange(slot);
    closeDropdown(true);
  }, [closeDropdown, onChange]);

  const focusOption = useCallback((index: number) => {
    setActiveIndex(index);
    optionRefs.current[index]?.focus();
  }, []);

  const handleTriggerClick = useCallback(() => {
    if (open) {
      setOpen(false);
      return;
    }
    openDropdown(selectedFocusIndex);
  }, [open, openDropdown, selectedFocusIndex]);

  const handleTriggerKeyDown = useCallback((event: ReactKeyboardEvent<HTMLButtonElement>) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      if (!open) {
        openDropdown(selectedFocusIndex);
        return;
      }
      const activeSlot = TIME_SLOTS[activeIndex];
      if (activeSlot) handleSelect(activeSlot);
      return;
    }

    if (event.key === 'ArrowDown' || event.key === 'ArrowUp' || event.key === 'Home' || event.key === 'End') {
      event.preventDefault();
      const baseIndex = open ? activeIndex : selectedFocusIndex;
      const nextIndex = getNextTimeInputFocusIndex(event.key, baseIndex, TIME_SLOTS.length);
      if (nextIndex >= 0) {
        setOpen(true);
        focusOption(nextIndex);
      }
      return;
    }

    if (event.key === 'Escape' && open) {
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
    }
  }, [activeIndex, focusOption, handleSelect, open, openDropdown, selectedFocusIndex]);

  const handleListKeyDown = useCallback((event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      closeDropdown(true);
      return;
    }

    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      const activeSlot = TIME_SLOTS[activeIndex];
      if (activeSlot) handleSelect(activeSlot);
      return;
    }

    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp' && event.key !== 'Home' && event.key !== 'End') return;
    event.preventDefault();
    const nextIndex = getNextTimeInputFocusIndex(event.key, activeIndex, TIME_SLOTS.length);
    if (nextIndex >= 0) focusOption(nextIndex);
  }, [activeIndex, closeDropdown, focusOption, handleSelect]);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={handleTriggerClick}
        onKeyDown={handleTriggerKeyDown}
        className={`inline-flex items-center gap-1.5 bg-surface-2 text-text-primary text-sm px-2.5 py-1.5 rounded-r-control border transition-colors outline-hidden focus-ring-soft ${
          open
            // trigger-pressed elevation tokenized
          // to --shadow-tooltip so the open-state depth tracks the
          // canonical "small floating element" tier rather than
          // drifting at the raw Tailwind shadow-[var(--shadow-tooltip)] value.
          ? 'border-accent/40 bg-surface-1 shadow-[var(--shadow-tooltip)]'
            : 'border-surface-3 hover:border-accent/30'
        }`}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listboxId : undefined}
        aria-label={triggerAriaLabel}
        aria-labelledby={triggerAriaLabelledBy}
      >
        <ClockIcon className="w-3.5 h-3.5 text-text-muted" />
        <span id={valueLabelId}>{displayValue}</span>
        <svg
          aria-hidden="true"
          className={`h-3 w-3 text-text-muted transition-transform ${open ? 'rotate-180' : ''}`}
          viewBox="0 0 20 20"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M5 7l5 6 5-6" />
        </svg>
      </button>
      {open && createPortal(
        <div
          ref={listRef}
          id={listboxId}
          role="listbox"
          aria-orientation="vertical"
          tabIndex={-1}
          aria-activedescendant={activeDescendantId}
          aria-label={ariaLabelledBy ? undefined : ariaLabel}
          aria-labelledby={ariaLabelledBy}
          onKeyDown={handleListKeyDown}
          // time-slot listbox is a floating popover —
          // pin it to the canonical --shadow-popover token so its depth
          // matches the rest of the dropdown family instead of the raw
          // shadow-[var(--shadow-popover)] utility.
          className="fixed z-[var(--z-popover)] max-h-60 min-w-[var(--menu-min-w-lg)] overflow-y-auto overscroll-contain rounded-r-card border border-popover bg-surface-1 shadow-[var(--shadow-popover)] p-1"
          style={{ top: position.top, left: position.left }}
        >
          {TIME_SLOTS.map((slot, index) => {
            const isSelected = slot === value;
            return (
              // Keyboard activation is owned by the listbox roving-focus
              // handler; pointer activation stays local to the option row.
              // eslint-disable-next-line jsx-a11y/click-events-have-key-events
              <div
                key={slot}
                ref={(el) => { optionRefs.current[index] = el; }}
                id={`${optionIdPrefix}-${index}`}
                role="option"
                aria-selected={isSelected}
                tabIndex={activeIndex === index ? 0 : -1}
                onFocus={() => setActiveIndex(index)}
                className={`w-full text-start px-2 py-1.5 rounded-r-control text-sm leading-normal transition-colors flex items-center justify-between gap-2 focus-ring-soft ${
                  isSelected
                    ? 'text-accent bg-accent/10'
                    : 'text-text-primary hover:bg-surface-3'
                }`}
                onMouseDown={e => e.preventDefault()}
                onClick={() => handleSelect(slot)}
              >
                <span>{formatTimeDisplay(slot, locale)}</span>
                {isSelected && (
                  <CheckIcon aria-hidden="true" className="text-accent w-3 h-3 shrink-0" />
                )}
              </div>
            );
          })}
        </div>,
        document.body,
      )}
    </>
  );
}

export function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start gap-2 text-xs">
      <span className="text-text-muted w-32 shrink-0">{label}</span>
      <span className="text-text-secondary font-mono text-xs">{value}</span>
    </div>
  );
}
