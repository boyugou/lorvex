import { createPortal } from 'react-dom';
import { useCallback, useId, useLayoutEffect, useRef, useState } from 'react';
import type { Priority } from '@lorvex/shared/types';
import { BoltIcon, XIcon } from '@/components/ui/icons';
import { PRIORITY_COLORS } from '@/components/task-card/support';
import { ToggleChip } from '@/components/ui/ToggleChip';
import { SelectableListRow } from '@/components/ui/SelectableListRow';
import { pushModalEscapeHandler } from '@/components/ui/overlay';
import { resolveAnchoredPopupPosition } from '@/components/ui/portalDropdown.runtime';
import { QUICK_CAPTURE_PRIORITY_OPTIONS } from '../types';
import type { CompactToolbarTranslate } from './types';
import {
  createBrowserQuickCapturePopoverFocusHost,
  restoreQuickCapturePopoverTriggerFocus,
} from './popoverFocus.runtime';

import { QUICK_CAPTURE_POPOVER_Z_CLASS, QUICK_CAPTURE_POPOVER_SHELL_CLASS } from './popoverLayer';

const PRIORITY_POPUP_WIDTH_PX = 128;
const PRIORITY_POPUP_HEIGHT_PX = 160;
const QUICK_CAPTURE_POPOVER_BACKDROP_Z_CLASS = 'z-[calc(var(--z-modal)+1)]';
const quickCapturePopoverFocusHost = createBrowserQuickCapturePopoverFocusHost();

export function PriorityDropdown({
  priority,
  togglePriority,
  clearPriority,
  t,
}: {
  priority: Priority | null;
  togglePriority: (v: Priority) => void;
  clearPriority: () => void;
  t: CompactToolbarTranslate;
}) {
  const [open, setOpen] = useState(false);
  const [panelPos, setPanelPos] = useState<{ top: number; left: number } | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const optionRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [focusedIdx, setFocusedIdx] = useState(0);
  const menuId = useId();

  const closeMenu = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    if (!restoreFocus) return;
    restoreQuickCapturePopoverTriggerFocus(
      quickCapturePopoverFocusHost,
      () => triggerRef.current,
    );
  }, []);

  useLayoutEffect(() => {
    if (!open) return;
    return pushModalEscapeHandler(() => closeMenu(true));
  }, [closeMenu, open]);

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
          popupWidth: PRIORITY_POPUP_WIDTH_PX,
          popupHeight: PRIORITY_POPUP_HEIGHT_PX,
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

  function handleSelect(v: Priority) {
    togglePriority(v);
    closeMenu(true);
  }

  function resolveInitialFocusIndex(): number {
    if (priority == null) return 0;
    const selectedIndex = QUICK_CAPTURE_PRIORITY_OPTIONS.findIndex((opt) => opt.value === priority);
    return selectedIndex === -1 ? 0 : selectedIndex;
  }

  function openMenu(nextOpen: boolean) {
    if (nextOpen) {
      setFocusedIdx(resolveInitialFocusIndex());
      setOpen(true);
      return;
    }
    closeMenu(false);
  }

  useLayoutEffect(() => {
    if (!open || !panelPos) return;
    const handle = window.requestAnimationFrame(() => {
      optionRefs.current[focusedIdx]?.focus();
    });
    return () => window.cancelAnimationFrame(handle);
  }, [focusedIdx, open, panelPos]);

  function activateIndex(index: number) {
    const option = QUICK_CAPTURE_PRIORITY_OPTIONS[index];
    if (option) {
      handleSelect(option.value);
      return;
    }
    if (priority != null && index === QUICK_CAPTURE_PRIORITY_OPTIONS.length) {
      clearPriority();
      closeMenu(true);
    }
  }

  function moveFocus(direction: -1 | 1) {
    const optionCount = QUICK_CAPTURE_PRIORITY_OPTIONS.length + (priority != null ? 1 : 0);
    if (optionCount <= 0) return;
    const next = (focusedIdx + direction + optionCount) % optionCount;
    setFocusedIdx(next);
  }

  function handleMenuKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      closeMenu(true);
      return;
    }
    if (event.key === 'Tab') {
      closeMenu(false);
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      moveFocus(event.key === 'ArrowDown' ? 1 : -1);
      return;
    }
    if (event.key === 'Home') {
      event.preventDefault();
      setFocusedIdx(0);
      return;
    }
    if (event.key === 'End') {
      event.preventDefault();
      setFocusedIdx(QUICK_CAPTURE_PRIORITY_OPTIONS.length + (priority != null ? 1 : 0) - 1);
      return;
    }
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      activateIndex(focusedIdx);
    }
  }

  return (
    <div className="relative" ref={ref}>
      <ToggleChip
        ref={triggerRef}
        onClick={() => openMenu(!open)}
        selected={priority != null}
        selectedClassName={priority != null ? `bg-[var(--accent-tint-sm)] ${PRIORITY_COLORS[priority]}` : undefined}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
      >
        <BoltIcon className="w-3.5 h-3.5" />
        <span>{priority != null ? `P${priority}` : t('task.priority')}</span>
      </ToggleChip>
      {open && panelPos && createPortal(
        <>
          {/* Invisible backdrop to close on outside click. Hidden
              from assistive tech since it's purely a click target;
              keyboard users dismiss the popover via Esc on the
              focused control. */}
          <div
            className={`fixed inset-0 ${QUICK_CAPTURE_POPOVER_BACKDROP_Z_CLASS}`}
            onClick={(event) => {
              event.stopPropagation();
              closeMenu(true);
            }}
            role="presentation"
            aria-hidden="true"
          />
          <div
            id={menuId}
            style={{ position: 'fixed', top: panelPos.top, left: panelPos.left, minWidth: PRIORITY_POPUP_WIDTH_PX }}
            className={`${QUICK_CAPTURE_POPOVER_Z_CLASS} ${QUICK_CAPTURE_POPOVER_SHELL_CLASS} p-1`}
            role="menu"
            aria-label={t('task.priority')}
            aria-orientation="vertical"
            onClick={(event) => event.stopPropagation()}
            onKeyDown={handleMenuKeyDown}
          >
            {QUICK_CAPTURE_PRIORITY_OPTIONS.map((opt, idx) => (
              <SelectableListRow
                key={opt.value}
                ref={(node) => { optionRefs.current[idx] = node; }}
                size="sm"
                onClick={() => handleSelect(opt.value)}
                onFocus={() => setFocusedIdx(idx)}
                selected={priority === opt.value}
                // Selected row keeps the per-priority colour token rather
                // than the canonical text-accent so users can tell P1
                // (red) from P3 (amber) at a glance.
                selectedClassName={`bg-[var(--accent-tint-sm)] ${opt.color}`}
                className={priority === opt.value ? '' : `text-text-secondary hover:bg-surface-3 ${opt.color}`}
                role="menuitemradio"
                aria-checked={priority === opt.value}
                aria-label={t(opt.ariaLabelKey)}
                tabIndex={focusedIdx === idx ? 0 : -1}
              >
                <BoltIcon className="w-3 h-3" />
                <span>{opt.label}</span>
                {priority === opt.value && <span className="ms-auto text-accent text-3xs">&#10003;</span>}
              </SelectableListRow>
            ))}
            {priority != null && (
              <SelectableListRow
                ref={(node) => { optionRefs.current[QUICK_CAPTURE_PRIORITY_OPTIONS.length] = node; }}
                size="sm"
                onClick={() => { clearPriority(); closeMenu(true); }}
                onFocus={() => setFocusedIdx(QUICK_CAPTURE_PRIORITY_OPTIONS.length)}
                className="text-text-muted hover:bg-surface-3 mt-0.5 border-t border-surface-3"
                role="menuitem"
                tabIndex={focusedIdx === QUICK_CAPTURE_PRIORITY_OPTIONS.length ? 0 : -1}
              >
                <XIcon className="w-3 h-3" />
                <span>{t('common.clear')}</span>
              </SelectableListRow>
            )}
          </div>
        </>,
        document.body,
      )}
    </div>
  );
}
