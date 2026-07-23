import { createPortal } from 'react-dom';
import { useCallback, useId, useLayoutEffect, useRef, useState } from 'react';
import { ClockIcon, XIcon } from '@/components/ui/icons';
import { CompactNumberInput } from '@/components/ui/CompactNumberInput';
import { useI18n } from '@/lib/i18n';
import { MAX_ESTIMATED_MINUTES, resolveEstimatedMinutesDraftState } from '@/lib/estimatedMinutes';
import { formatDurationCompact } from '@/components/today-view/primitives';
import { ToggleChip } from '@/components/ui/ToggleChip';
import { pushModalEscapeHandler } from '@/components/ui/overlay';
import { resolveAnchoredPopupPosition } from '@/components/ui/portalDropdown.runtime';
import { DURATION_PRESET_VALUES } from '../types';
import type { CompactToolbarTranslate } from './types';
import {
  createBrowserQuickCapturePopoverFocusHost,
  restoreQuickCapturePopoverTriggerFocus,
} from './popoverFocus.runtime';
import { QUICK_CAPTURE_POPOVER_Z_CLASS, QUICK_CAPTURE_POPOVER_SHELL_CLASS } from './popoverLayer';

/** Compact chip labels for the duration picker dropdown. */
const DURATION_CHIP_VALUES = [
  { minutes: 15, label: '15m' },
  { minutes: 30, label: '30m' },
  { minutes: 60, label: '1h' },
  { minutes: 120, label: '2h' },
] as const;

const DURATION_POPUP_WIDTH_PX = 180;
const DURATION_POPUP_HEIGHT_PX = 216;
const QUICK_CAPTURE_POPOVER_BACKDROP_Z_CLASS = 'z-[calc(var(--z-modal)+1)]';
const quickCapturePopoverFocusHost = createBrowserQuickCapturePopoverFocusHost();

export function DurationDropdown({
  estimatedMinutes,
  toggleDuration,
  setEstimatedMinutes,
  clearDuration,
  t,
}: {
  estimatedMinutes: string;
  toggleDuration: (m: number) => void;
  setEstimatedMinutes: (v: string) => void;
  clearDuration: () => void;
  t: CompactToolbarTranslate;
}) {
  const [open, setOpen] = useState(false);
  const [panelPos, setPanelPos] = useState<{ top: number; left: number } | null>(null);
  const { formatNumber, format } = useI18n();
  const ref = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const durationControlRefs = useRef<(HTMLElement | null)[]>([]);
  const [focusedControlIdx, setFocusedControlIdx] = useState(0);
  const dialogId = useId();

  const closePanel = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    if (!restoreFocus) return;
    restoreQuickCapturePopoverTriggerFocus(
      quickCapturePopoverFocusHost,
      () => triggerRef.current,
    );
  }, []);

  useLayoutEffect(() => {
    if (!open) return;
    return pushModalEscapeHandler(() => closePanel(true));
  }, [closePanel, open]);

  useLayoutEffect(() => {
    if (!open) {
      setPanelPos(null);
      return;
    }

    const updatePanelPosition = () => {
      const rect = ref.current?.getBoundingClientRect();
      if (!rect) return;
      setPanelPos(
        resolveAnchoredPopupPosition({
          rect,
          viewportWidth: window.innerWidth,
          viewportHeight: window.innerHeight,
          popupWidth: DURATION_POPUP_WIDTH_PX,
          popupHeight: DURATION_POPUP_HEIGHT_PX,
          flipVertically: true,
        }),
      );
    };

    updatePanelPosition();
    window.addEventListener('resize', updatePanelPosition);
    document.addEventListener('scroll', updatePanelPosition, { capture: true, passive: true });
    return () => {
      window.removeEventListener('resize', updatePanelPosition);
      document.removeEventListener('scroll', updatePanelPosition, true);
    };
  }, [open]);

  // a11y: drive aria-invalid off parsed-value sanity
  // (same predicate the toast uses) so screen readers announce the
  // validation failure instead of only the sighted toast.
  const durationErrorId = 'quickcapture-duration-error';
  const {
    parsed: parsedDuration,
    invalid: durationInvalid,
    hasValidValue: hasValidDuration,
  } = resolveEstimatedMinutesDraftState(estimatedMinutes);
  const durationErrorMessage = durationInvalid
    ? format('capture.durationInvalid', { max: formatNumber(MAX_ESTIMATED_MINUTES) })
    : null;

  const currentMinutes = parsedDuration;
  const isPreset = currentMinutes != null && DURATION_PRESET_VALUES.some((v) => v === currentMinutes);

  function displayLabel(): string {
    if (!currentMinutes || currentMinutes <= 0) return t('capture.durationPlaceholder');
    return formatDurationCompact(currentMinutes, t('common.hourShort'), t('common.min'), formatNumber);
  }

  function handlePreset(minutes: number) {
    toggleDuration(minutes);
    closePanel(true);
  }

  function resolveInitialDurationFocusIndex(): number {
    if (currentMinutes != null && isPreset) {
      const selectedIndex = DURATION_CHIP_VALUES.findIndex((item) => item.minutes === currentMinutes);
      return selectedIndex === -1 ? 0 : selectedIndex;
    }
    if (estimatedMinutes.trim()) {
      return DURATION_CHIP_VALUES.length;
    }
    return 0;
  }

  function openPanel(nextOpen: boolean) {
    if (nextOpen) {
      setFocusedControlIdx(resolveInitialDurationFocusIndex());
      setOpen(true);
      return;
    }
    closePanel(false);
  }

  useLayoutEffect(() => {
    if (!open || !panelPos) return;
    const handle = window.requestAnimationFrame(() => {
      durationControlRefs.current[focusedControlIdx]?.focus();
    });
    return () => window.cancelAnimationFrame(handle);
  }, [focusedControlIdx, open, panelPos]);

  function moveDurationFocus(direction: -1 | 1) {
    const controlCount = DURATION_CHIP_VALUES.length + 1 + (estimatedMinutes ? 1 : 0);
    const next = (focusedControlIdx + direction + controlCount) % controlCount;
    setFocusedControlIdx(next);
  }

  function handlePanelKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      closePanel(true);
      return;
    }
    if (event.key === 'Tab') {
      closePanel(false);
      return;
    }
    if (event.target instanceof HTMLInputElement) return;
    if (
      event.key === 'ArrowDown'
      || event.key === 'ArrowRight'
      || event.key === 'ArrowUp'
      || event.key === 'ArrowLeft'
    ) {
      event.preventDefault();
      moveDurationFocus(event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : -1);
      return;
    }
    if (event.key === 'Home') {
      event.preventDefault();
      setFocusedControlIdx(0);
      return;
    }
    if (event.key === 'End') {
      event.preventDefault();
      setFocusedControlIdx(DURATION_CHIP_VALUES.length + (estimatedMinutes ? 1 : 0));
    }
  }

  // Surface invalid state on the chip itself, not only inside the
  // open dropdown. This keeps feedback attached to the value even
  // after the user closes the popover.
  const chipInvalidStateClass = durationInvalid
    ? 'ring-1 ring-danger/60 chip-danger chip-danger-interactive'
    : hasValidDuration
      ? 'bg-[var(--accent-tint-sm)] text-accent'
      : 'text-text-muted hover:text-text-secondary hover:bg-surface-3';

  return (
    <div className="relative" ref={ref}>
      <ToggleChip
        ref={triggerRef}
        onClick={() => openPanel(!open)}
        selected={hasValidDuration || durationInvalid}
        selectedClassName={chipInvalidStateClass}
        inactiveClassName={chipInvalidStateClass}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? dialogId : undefined}
        aria-invalid={durationInvalid || undefined}
        aria-describedby={durationInvalid ? durationErrorId : undefined}
        title={durationErrorMessage || undefined}
      >
        <ClockIcon className="w-3.5 h-3.5" />
        <span>{displayLabel()}</span>
      </ToggleChip>
      {open && panelPos && createPortal(
        <>
          <div
            className={`fixed inset-0 ${QUICK_CAPTURE_POPOVER_BACKDROP_Z_CLASS}`}
            onClick={(event) => {
              event.stopPropagation();
              closePanel(true);
            }}
            role="presentation"
            aria-hidden="true"
          />
          <div
            id={dialogId}
            style={{ position: 'fixed', top: panelPos.top, left: panelPos.left, minWidth: DURATION_POPUP_WIDTH_PX }}
            className={`${QUICK_CAPTURE_POPOVER_Z_CLASS} ${QUICK_CAPTURE_POPOVER_SHELL_CLASS} p-2`}
            role="dialog"
            aria-label={t('capture.durationPlaceholder')}
            onClick={(event) => event.stopPropagation()}
            onKeyDown={handlePanelKeyDown}
          >
            {/* Compact preset chips */}
            <div className="flex items-center gap-1.5 flex-wrap mb-1.5">
              {DURATION_CHIP_VALUES.map(({ minutes, label }, idx) => (
                <button
                  key={minutes}
                  ref={(node) => { durationControlRefs.current[idx] = node; }}
                  type="button"
                  onClick={() => handlePreset(minutes)}
                  onFocus={() => setFocusedControlIdx(idx)}
                  className={`text-xs px-2.5 py-1 rounded-full transition-colors active:scale-[0.97] focus-ring-strong ${
                    estimatedMinutes === String(minutes)
                      ? 'bg-accent text-on-accent'
                      : 'bg-surface-3/60 text-text-secondary hover:bg-surface-3 hover:text-text-primary'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            {/* Custom input row */}
            {/* associate the visible "min" unit
                with the number input via aria-describedby so SR users
                hear "duration, edit text, minutes" instead of just
                the placeholder echo. The id on the unit span is what
                consumers read; it's stable per render because it is
                a literal string. */}
            <div className="flex items-center gap-1.5 px-0.5 py-1.5 border-t border-surface-3">
              <CompactNumberInput
                ref={(node) => { durationControlRefs.current[DURATION_CHIP_VALUES.length] = node; }}
                min={1}
                max={MAX_ESTIMATED_MINUTES}
                step={1}
                value={isPreset ? '' : estimatedMinutes}
                onChange={(e) => setEstimatedMinutes(e.target.value)}
                placeholder={t('capture.customDuration')}
                aria-label={t('capture.durationPlaceholder')}
                aria-describedby="capture-duration-unit"
                aria-invalid={durationInvalid}
                aria-errormessage={durationInvalid ? durationErrorId : undefined}
                onClick={(e) => e.stopPropagation()}
                onFocus={() => setFocusedControlIdx(DURATION_CHIP_VALUES.length)}
              />
              <span id="capture-duration-unit" className="text-text-muted text-xs">{t('common.min')}</span>
            </div>
            {/* visible error inside the dropdown.
                The id-bearing copy lives outside this branch (see
                the `sr-only` paragraph after the dropdown) so the
                chip's `aria-describedby` keeps resolving once the
                user closes the popover. This visible copy
                duplicates the message text without the id so the
                two announcements don't collide. */}
            {durationErrorMessage && (
              <p
                role="alert"
                className="text-3xs text-danger mt-1 px-0.5"
              >
                {durationErrorMessage}
              </p>
            )}
            {estimatedMinutes && (
              <button
                ref={(node) => { durationControlRefs.current[DURATION_CHIP_VALUES.length + 1] = node; }}
                type="button"
                onClick={() => { clearDuration(); closePanel(true); }}
                onFocus={() => setFocusedControlIdx(DURATION_CHIP_VALUES.length + 1)}
                className="w-full flex items-center gap-2 text-xs px-0.5 py-1.5 rounded-r-control text-text-muted hover:bg-surface-3 transition-colors mt-0.5 border-t border-surface-3"
              >
                <XIcon className="w-3 h-3" />
                <span>{t('common.clear')}</span>
              </button>
            )}
          </div>
        </>,
        document.body,
      )}
      {/* persistent error description for the chip.
          Rendered visually-hidden so the danger ring on the chip is
          the primary visual signal (matches the existing chip-level
          color treatment used for date/priority), but the live alert
          + the `id` referenced by `aria-describedby` stay mounted
          regardless of dropdown state so AT users hear the failure
          on focus. The dropdown still surfaces the same copy in a
          visible `<p role="alert">` adjacent to the input when
          open - that's the sighted user's confirmation path. */}
      {durationInvalid && durationErrorMessage && (
        <p id={durationErrorId} role="alert" className="sr-only">
          {durationErrorMessage}
        </p>
      )}
    </div>
  );
}
