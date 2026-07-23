import {
  useEffect,
  useRef,
  useState,
  useCallback,
  useId,
  useMemo,
  type KeyboardEvent as ReactKeyboardEvent,
} from 'react';
import { createPortal } from 'react-dom';
import { LANGUAGE_OPTIONS, type Locale, useI18n } from '@/lib/i18n';
import { Button } from '@/components/ui/Button';
import {
  createBrowserLanguagePickerDeferredFocusTimerHost,
  createBrowserLanguagePickerDismissRuntimeDeps,
  getNextLanguagePickerFocusIndex,
  getNextLanguagePickerSearchFocusIndex,
  installLanguagePickerDismissRuntime,
  resolveLanguagePickerDropdownPosition,
  scheduleLanguagePickerSearchFocusRuntime,
} from './LanguagePicker.runtime';

const languagePickerDeferredFocusTimerHost = createBrowserLanguagePickerDeferredFocusTimerHost();

interface LanguagePickerProps {
  value: Locale;
  usingSystem: boolean;
  onChange: (v: Locale) => void;
  onUseSystem: () => void;
}

export function LanguagePicker({
  value,
  usingSystem,
  onChange,
  onUseSystem,
}: LanguagePickerProps) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const buttonRef = useRef<HTMLButtonElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const optionRefs = useRef<(HTMLDivElement | null)[]>([]);
  const [dropdownPos, setDropdownPos] = useState({ top: 0, left: 0 });
  const [focusedIndex, setFocusedIndex] = useState(-1);
  const [searchFocused, setSearchFocused] = useState(false);
  const listboxId = useId();
  const optionIdPrefix = useId();

  const filtered = useMemo(() => (
    LANGUAGE_OPTIONS.filter(opt =>
      opt.label.toLowerCase().includes(query.toLowerCase()),
    )
  ), [query]);
  const languageOptions = useMemo(() => [
    {
      key: 'system',
      label: t('settings.useSystem'),
      selected: usingSystem,
      onSelect: onUseSystem,
    },
    ...filtered.map((opt) => ({
      key: opt.value,
      label: opt.label,
      selected: !usingSystem && opt.value === value,
      onSelect: () => onChange(opt.value),
    })),
  ], [filtered, onChange, onUseSystem, t, usingSystem, value]);
  const current = LANGUAGE_OPTIONS.find(opt => opt.value === value);
  const currentLabel = current?.label ?? value;
  const activeDescendantId = open && focusedIndex >= 0
    ? `${optionIdPrefix}-${focusedIndex}`
    : undefined;
  const searchActiveDescendantId = searchFocused ? activeDescendantId : undefined;

  const updateDropdownPos = useCallback(() => {
    if (!buttonRef.current) return;
    const rect = buttonRef.current.getBoundingClientRect();
    setDropdownPos(resolveLanguagePickerDropdownPosition(rect, {
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
    }));
  }, []);

  const closeDropdown = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    setSearchFocused(false);
    if (restoreFocus) {
      buttonRef.current?.focus();
    }
  }, []);

  useEffect(() => {
    if (!open) {
      setQuery('');
      setFocusedIndex(-1);
      return;
    }
    setFocusedIndex(-1);
    updateDropdownPos();

    const cleanupFocus = scheduleLanguagePickerSearchFocusRuntime({
      focusSearchInput: () => searchRef.current?.focus(),
      ...languagePickerDeferredFocusTimerHost,
    });
    const cleanupDismiss = installLanguagePickerDismissRuntime(
      createBrowserLanguagePickerDismissRuntimeDeps({
        getTrigger: () => buttonRef.current,
        getPanel: () => dropdownRef.current,
        onDismiss: () => closeDropdown(false),
      }),
    );

    return () => {
      cleanupFocus();
      cleanupDismiss();
    };
  }, [closeDropdown, open, updateDropdownPos]);

  useEffect(() => {
    optionRefs.current = optionRefs.current.slice(0, languageOptions.length);
    setFocusedIndex((currentFocus) => (
      currentFocus >= languageOptions.length ? languageOptions.length - 1 : currentFocus
    ));
  }, [languageOptions.length]);

  const selectLanguageOption = useCallback((index: number) => {
    const option = languageOptions[index];
    if (!option) return;
    option.onSelect();
    closeDropdown(true);
  }, [closeDropdown, languageOptions]);

  const focusLanguageOption = useCallback((index: number) => {
    if (index < 0 || index >= languageOptions.length) return;
    setFocusedIndex(index);
    optionRefs.current[index]?.focus();
  }, [languageOptions.length]);

  const handleLanguageListKeyDown = (e: ReactKeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      closeDropdown(true);
      return;
    }
    if (e.key === 'Enter' || e.key === ' ') {
      if (focusedIndex < 0) return;
      e.preventDefault();
      selectLanguageOption(focusedIndex);
      return;
    }
    const nextIndex = getNextLanguagePickerFocusIndex(e.key, focusedIndex, languageOptions.length);
    if (nextIndex !== focusedIndex) {
      e.preventDefault();
      focusLanguageOption(nextIndex);
    }
  };

  const handleSearchKeyDown = (e: ReactKeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      closeDropdown(true);
      return;
    }
    if (e.key === 'Enter' || e.key === ' ') {
      e.stopPropagation();
      return;
    }
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') {
      e.stopPropagation();
      return;
    }
    const nextIndex = getNextLanguagePickerSearchFocusIndex(e.key, languageOptions.length);
    if (nextIndex >= 0) {
      e.preventDefault();
      e.stopPropagation();
      focusLanguageOption(nextIndex);
    }
  };

  return (
    <div className="inline-block">
      {/* outline-variant chip. The trigger is wider than a
          stock chip (min-w-36) and uses `text-sm` so the language label
          reads at body-copy weight; the chevron-bearing Settings list-row
          alignment depends on this exact rhythm. The override stack is
          intentionally inline (not promoted to a Button size variant)
          because no other call site needs this combination — adding a
          one-shot `size` would proliferate the primitive surface. The
          monoChip size in Button.tsx (#3814) is the canonical example
          of "promote when ≥2 sites need it"; LanguagePicker is the
          "stay inline when unique" counterexample. */}
      <Button
        ref={buttonRef}
        variant="outline"
        onClick={() => setOpen(o => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listboxId : undefined}
        className="text-sm px-3 py-1.5 min-w-36 gap-2 text-text-primary hover:border-accent/50"
      >
        <span className="flex-1 text-start">
          {usingSystem ? `${t('settings.useSystem')} · ${currentLabel}` : currentLabel}
        </span>
        <svg
          className={`w-3 h-3 text-text-muted shrink-0 transition-transform duration-150 ${open ? 'rotate-180' : ''}`}
          viewBox="0 0 12 12"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
        >
          <path d="M2 4l4 4 4-4" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </Button>

      {open && createPortal(
        // Popover container — the embedded search <input> and listbox
        // each have their own role + key handlers; this wrapper only
        // forwards Escape / arrow keys at the popover boundary.
        // eslint-disable-next-line jsx-a11y/no-static-element-interactions
        <div
          ref={dropdownRef}
          className="fixed w-[var(--popover-w-xs)] bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] overflow-hidden z-[var(--z-popover)]"
          style={{ top: dropdownPos.top, left: dropdownPos.left }}
          onKeyDown={handleLanguageListKeyDown}
        >
          <div className="p-2 border-b border-surface-3">
            <input
              ref={searchRef}
              type="search"
              value={query}
              onChange={e => {
                setQuery(e.target.value);
                setFocusedIndex(-1);
              }}
              onKeyDown={handleSearchKeyDown}
              placeholder={t('settings.languageSearch')}
              aria-label={t('settings.languageSearch')}
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={open && languageOptions.length > 0}
              aria-controls={listboxId}
              aria-activedescendant={searchActiveDescendantId}
              onFocus={() => {
                setSearchFocused(true);
                setFocusedIndex(-1);
              }}
              onBlur={() => setSearchFocused(false)}
              className="w-full bg-surface-2 text-text-primary text-xs px-2.5 py-1.5 rounded-r-control outline-hidden focus-ring-soft placeholder:text-text-muted"
            />
          </div>
          <div
            id={listboxId}
            className="max-h-52 overflow-y-auto overscroll-contain p-1"
            role="listbox"
            aria-orientation="vertical"
            aria-label={t('settings.language')}
            aria-activedescendant={activeDescendantId}
          >
            {languageOptions.length === 1 && filtered.length === 0 && (
              <p className="text-text-muted text-xs px-3 py-2">{t('common.noResults')}</p>
            )}
            {/* Listbox option. Keyboard activation flows through the
                popover's onKeyDown (Enter/Space/ArrowKeys handled at
                the parent listbox level via roving tabIndex); this
                option only handles pointer activation. */}
            {languageOptions.map((opt, i) => (
              // eslint-disable-next-line jsx-a11y/click-events-have-key-events
              <div
                ref={(el) => { optionRefs.current[i] = el; }}
                key={opt.key}
                id={`${optionIdPrefix}-${i}`}
                role="option"
                aria-selected={opt.selected}
                tabIndex={focusedIndex === i ? 0 : -1}
                onClick={() => selectLanguageOption(i)}
                onFocus={() => setFocusedIndex(i)}
                className={`w-full text-start px-3 py-1.5 rounded-r-control text-sm transition-colors flex items-center gap-2 focus-ring-soft ${
                  opt.selected
                    ? 'bg-accent/15 text-accent'
                    : 'text-text-secondary hover:bg-surface-2'
                }`}
              >
                {opt.selected && (
                  <svg className="w-3 h-3 shrink-0" viewBox="0 0 12 12" fill="currentColor">
                    <path
                      d="M1.5 6.5l3 3 6-6"
                      stroke="currentColor"
                      strokeWidth="1.5"
                      fill="none"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                )}
                {!opt.selected && <span className="w-3 shrink-0" />}
                {opt.label}
              </div>
            ))}
          </div>
        </div>,
        document.body,
      )}
    </div>
  );
}
