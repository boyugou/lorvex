import { useCallback, useRef } from 'react';
import { useI18n } from '@/lib/i18n';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';
import { XIcon } from './icons';
import { handleSearchInputKeyDown } from './SearchInput.runtime';

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  className?: string;
}

/**
 * Consistent search input with clear button and Escape-to-clear.
 * Wraps itself in `relative flex-1` for toolbar layout compatibility.
 */
export function SearchInput({ value, onChange, placeholder, className }: SearchInputProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const { t } = useI18n();
  const runtimeProfile = useRuntimeProfile();
  const isMobile = runtimeProfile.runtimeClass === 'mobile';
  const inlineEndPaddingClass = value ? (isMobile ? 'pe-14' : 'pe-10') : 'pe-3';

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      handleSearchInputKeyDown(e, () => onChange(''), () => inputRef.current?.blur());
    },
    [onChange],
  );

  return (
    <div className={className ?? 'relative flex-1'}>
      {/* use type="search" so Apple platforms surface
          the dedicated software-keyboard "search" return key, screen
          readers announce "search, edit text" instead of "edit text",
          and the UA's clear button (where applicable) is exposed —
          we still render our own clear button below for visual
          consistency across browsers. */}
      <input
        ref={inputRef}
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        aria-label={placeholder}
        // opt-in marker for ember/midnight theme form-control
        // radius/border treatment.
        data-theme-form-control="true"
        className={`w-full bg-surface-2 text-text-primary text-sm ps-3 ${inlineEndPaddingClass} py-1.5 rounded-r-control border border-surface-3 outline-hidden focus-ring-soft focus:border-accent/40 placeholder:text-text-muted/70 transition-colors duration-150 appearance-none [&::-webkit-search-decoration]:appearance-none [&::-webkit-search-cancel-button]:appearance-none [&::-webkit-search-cancel-button]:hidden`}
      />
      {value && (
        // enforce a minimum hit target on the clear button
        // so it stays comfortably tappable on touch devices (44×44 CSS px,
        // matching Apple HIG / WCAG 2.5.5 Level AAA) while staying compact
        // on desktop (24×24, large enough for cursor accuracy without
        // bleeding into the input's right edge). The icon stays the same
        // small visual size — only the hit area expands.
        <button
          type="button"
          onClick={() => onChange('')}
          className={`absolute end-1 top-1/2 -translate-y-1/2 inline-flex items-center justify-center rounded-r-control text-text-muted hover:text-text-secondary hover:bg-surface-3/60 active:scale-95 transition-[color,background-color,transform] focus-ring-soft ${isMobile ? 'min-h-11 min-w-11' : 'min-h-6 min-w-6'}`}
          aria-label={t('common.clear')}
        >
          <XIcon className="w-3.5 h-3.5" />
        </button>
      )}
    </div>
  );
}
