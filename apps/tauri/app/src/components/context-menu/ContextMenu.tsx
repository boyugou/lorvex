import { type MutableRefObject, type ReactNode, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useI18n } from '@/lib/i18n';
import { localeTextDirection, type LocaleTextDirection } from '@/locales/registry';
import {
  installContextMenuKeyboardRuntime,
  restoreContextMenuFocus,
  resolveContextMenuPosition,
  resolveContextSubmenuPosition,
} from './ContextMenu.runtime';

export interface ContextMenuItem {
  key: string;
  label: string;
  icon?: ReactNode | undefined;
  danger?: boolean;
  disabled?: boolean;
  separator?: boolean;
  submenu?: ContextMenuItem[];
  onSelect?: (() => void) | undefined;
}

export interface ContextMenuPosition {
  x: number;
  y: number;
}

interface ContextMenuProps {
  items: ContextMenuItem[];
  position: ContextMenuPosition;
  onClose: () => void;
  triggerElement?: HTMLElement | null;
}

interface SubmenuPanelProps {
  items: ContextMenuItem[];
  onClose: () => void;
  highlightedKey: string | null;
  itemRefs: MutableRefObject<(HTMLButtonElement | null)[]>;
  textDirection: LocaleTextDirection;
}

function SubmenuPanel({ items, onClose, highlightedKey, itemRefs, textDirection }: SubmenuPanelProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [clamped, setClamped] = useState<{ left: number; top: number } | null>(null);
  const actionableItems = useMemo(
    () => items.filter((item) => !item.separator && !item.disabled),
    [items],
  );

  useEffect(() => {
    if (!ref.current) return;
    const el = ref.current;
    const parent = el.parentElement;
    if (!parent) return;
    const parentRect = parent.getBoundingClientRect();
    const rect = el.getBoundingClientRect();
    setClamped(resolveContextSubmenuPosition(
      parentRect,
      rect,
      { width: window.innerWidth, height: window.innerHeight },
      textDirection,
    ));
  }, [textDirection]);

  return (
    <div
      ref={ref}
      role="menu"
      aria-orientation="vertical"
      className="absolute min-w-[var(--menu-min-w-md)] bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] py-1 z-[calc(var(--z-popover)+1)] animate-[fade-in_0.1s_ease-out]"
      style={clamped ? { left: clamped.left, top: clamped.top } : { left: '100%', top: 0, visibility: 'hidden' }}
    >
      {items.map((item) => {
        const actionIdx = actionableItems.indexOf(item);
        return (
          <MenuItemRow
            key={item.key}
            item={item}
            onClose={onClose}
            highlighted={highlightedKey === item.key}
            isSubmenu
            buttonRef={actionIdx === -1
              ? undefined
              : (node) => { itemRefs.current[actionIdx] = node; }}
            tabIndex={highlightedKey === item.key ? 0 : -1}
            textDirection={textDirection}
          />
        );
      })}
    </div>
  );
}

interface MenuItemRowProps {
  item: ContextMenuItem;
  onClose: () => void;
  highlighted: boolean;
  isSubmenu?: boolean;
  // kept-open submenu signal — when the parent row is
  // keyboard-highlighted AND the consumer has elected to open the
  // submenu (ArrowRight / Enter), we render the submenu panel even
  // when the mouse isn't over the row. `submenuOpen` overrides the
  // prior hover-only `showSub` local state.
  submenuOpen?: boolean;
  submenuHighlightedKey?: string | null;
  onPointerOpenSubmenu?: () => void;
  onPointerCloseSubmenu?: () => void;
  buttonRef?: ((node: HTMLButtonElement | null) => void) | undefined;
  tabIndex?: number | undefined;
  submenuItemRefs?: MutableRefObject<(HTMLButtonElement | null)[]> | undefined;
  textDirection: LocaleTextDirection;
}

function MenuItemRow({
  item,
  onClose,
  highlighted,
  isSubmenu = false,
  submenuOpen = false,
  submenuHighlightedKey = null,
  onPointerOpenSubmenu,
  onPointerCloseSubmenu,
  buttonRef,
  tabIndex = -1,
  submenuItemRefs,
  textDirection,
}: MenuItemRowProps) {
  const [hoverShowSub, setHoverShowSub] = useState(false);

  if (item.separator) {
    return (
      <div
        role="separator"
        aria-orientation="horizontal"
        className="my-1 border-t border-surface-3"
      />
    );
  }

  const hasSubmenu = item.submenu && item.submenu.length > 0;
  const isHighlighted = highlighted && !item.disabled;
  const isOpen = hasSubmenu && (submenuOpen || hoverShowSub);

  return (
    // Hover region for submenu pointer-open/close. Keyboard submenu
    // navigation flows through the inner <button role="menuitem">'s
    // own key handlers; this wrapper has no user-action contract.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      className="relative"
      onMouseEnter={() => {
        if (!hasSubmenu) return;
        setHoverShowSub(true);
        onPointerOpenSubmenu?.();
      }}
      onMouseLeave={() => {
        if (!hasSubmenu) return;
        setHoverShowSub(false);
        onPointerCloseSubmenu?.();
      }}
    >
      <button
        ref={buttonRef}
        type="button"
        role="menuitem"
        // expose keyboard-highlight + submenu-
        // open state to assistive tech. `aria-current="true"` mirrors
        // the visual `bg-surface-3` highlight; `aria-haspopup="menu"`
        // and `aria-expanded` (only set when the row owns a submenu)
        // tell SR users this row opens a submenu and whether it is
        // currently open.
        aria-current={isHighlighted ? 'true' : undefined}
        aria-haspopup={hasSubmenu ? 'menu' : undefined}
        aria-expanded={hasSubmenu ? isOpen : undefined}
        disabled={item.disabled}
        tabIndex={tabIndex}
        className={`w-full text-start px-3 py-2 text-sm leading-normal rounded-r-control flex items-center gap-2 transition-colors focus-ring-soft ${
          isHighlighted
            ? item.danger ? 'text-danger bg-[var(--danger-tint-sm)]' : 'text-text-primary bg-surface-3'
            : item.danger
              ? 'text-danger hover:bg-[var(--danger-tint-sm)]'
              : item.disabled
                ? 'text-text-muted cursor-not-allowed'
                : 'text-text-primary hover:bg-surface-3'
        }`}
        onClick={() => {
          if (hasSubmenu) return;
          item.onSelect?.();
          onClose();
        }}
      >
        {item.icon && <span className="w-4 text-center text-xs shrink-0">{item.icon}</span>}
        <span className="flex-1">{item.label}</span>
        {hasSubmenu && <span className="text-text-muted text-xs ms-2">{textDirection === 'rtl' ? '‹' : '›'}</span>}
      </button>
      {hasSubmenu && !isSubmenu && isOpen && (
        <SubmenuPanel
          items={item.submenu!}
          onClose={onClose}
          highlightedKey={submenuHighlightedKey}
          itemRefs={submenuItemRefs!}
          textDirection={textDirection}
        />
      )}
    </div>
  );
}

export function ContextMenu({ items, position, onClose: requestClose, triggerElement = null }: ContextMenuProps) {
  const { t, locale } = useI18n();
  const textDirection = localeTextDirection(locale);
  const menuRef = useRef<HTMLDivElement>(null);
  const menuItemRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const submenuItemRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const triggerElementRef = useRef<HTMLElement | null>(triggerElement);
  triggerElementRef.current = triggerElement;
  const fallbackFocusTargetRef = useRef<HTMLElement | null>(null);
  const didCaptureFallbackFocusRef = useRef(false);
  if (!didCaptureFallbackFocusRef.current) {
    didCaptureFallbackFocusRef.current = true;
    if (typeof document !== 'undefined') {
      const activeElement = document.activeElement;
      fallbackFocusTargetRef.current = activeElement instanceof HTMLElement ? activeElement : null;
    }
  }
  const focusRestoredRef = useRef(false);
  const [pos, setPos] = useState(position);
  const [highlightIdx, setHighlightIdx] = useState(-1);
  // submenu navigation state. `submenuOwnerIdx` is
  // the actionable index of the parent row whose submenu is open via
  // keyboard (-1 = none open by keyboard). Pointer-only hover still
  // triggers the SubmenuPanel render through `MenuItemRow`'s local
  // `hoverShowSub` so we don't regress mouse UX.
  // `submenuHighlightIdx` selects the highlighted child inside the
  // active submenu's actionable list.
  const [submenuOwnerIdx, setSubmenuOwnerIdx] = useState(-1);
  const [submenuHighlightIdx, setSubmenuHighlightIdx] = useState(-1);

  const actionableItems = useMemo(
    () => items.filter((item) => !item.separator && !item.disabled),
    [items],
  );

  // Live ref so the keyboard runtime always sees the latest highlight
  // without re-installing listeners on every change.
  const highlightIdxRef = useRef(highlightIdx);
  highlightIdxRef.current = highlightIdx;
  const submenuOwnerIdxRef = useRef(submenuOwnerIdx);
  submenuOwnerIdxRef.current = submenuOwnerIdx;
  const submenuHighlightIdxRef = useRef(submenuHighlightIdx);
  submenuHighlightIdxRef.current = submenuHighlightIdx;
  const setRovingHighlightIdx = useCallback((updater: (previousIndex: number) => number) => {
    const nextIndex = updater(highlightIdxRef.current);
    highlightIdxRef.current = nextIndex;
    setHighlightIdx(nextIndex);
  }, []);
  const setRovingSubmenuHighlightIdx = useCallback((updater: (previousIndex: number) => number) => {
    const nextIndex = updater(submenuHighlightIdxRef.current);
    submenuHighlightIdxRef.current = nextIndex;
    setSubmenuHighlightIdx(nextIndex);
  }, []);
  const restoreFocus = useCallback(() => {
    if (focusRestoredRef.current) return;
    focusRestoredRef.current = true;
    restoreContextMenuFocus(triggerElementRef.current, fallbackFocusTargetRef.current);
  }, []);
  const closeWithFocusRestore = useCallback(() => {
    restoreFocus();
    requestClose();
  }, [requestClose, restoreFocus]);
  const onClose = closeWithFocusRestore;

  useEffect(() => restoreFocus, [restoreFocus]);

  // Resolve the active submenu's actionable items reactively. Pulled
  // out so the keyboard runtime + render path agree.
  const submenuOwner = submenuOwnerIdx >= 0 ? actionableItems[submenuOwnerIdx] : undefined;
  const submenuActionableItems = useMemo(() => {
    if (!submenuOwner?.submenu) return [];
    return submenuOwner.submenu.filter((item) => !item.separator && !item.disabled);
  }, [submenuOwner]);

  // Whenever the keyboard-opened submenu owner changes, reset the
  // submenu highlight to the first actionable item — that's the WAI-
  // ARIA expectation when ArrowRight / Enter opens the submenu.
  useEffect(() => {
    if (submenuOwnerIdx === -1) {
      setRovingSubmenuHighlightIdx(() => -1);
      return;
    }
    setRovingSubmenuHighlightIdx(() => (submenuActionableItems.length > 0 ? 0 : -1));
  }, [setRovingSubmenuHighlightIdx, submenuOwnerIdx, submenuActionableItems]);

  useLayoutEffect(() => {
    if (!menuRef.current) return;
    setPos(resolveContextMenuPosition(
      position,
      menuRef.current.getBoundingClientRect(),
      { width: window.innerWidth, height: window.innerHeight },
    ));
  }, [position]);

  useLayoutEffect(() => {
    const initialIndex = actionableItems.length > 0 ? 0 : -1;
    setRovingHighlightIdx(() => initialIndex);
    const handle = window.requestAnimationFrame(() => {
      if (initialIndex >= 0) {
        menuItemRefs.current[initialIndex]?.focus();
        return;
      }
      menuRef.current?.focus();
    });
    return () => window.cancelAnimationFrame(handle);
  }, [actionableItems.length, setRovingHighlightIdx]);

  const handleBackdropClick = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    closeWithFocusRestore();
  }, [closeWithFocusRestore]);

  // Live refs onto the resolved submenu list so the keyboard runtime
  // can read latest values without re-installing on every keystroke.
  const submenuActionableItemsRef = useRef(submenuActionableItems);
  submenuActionableItemsRef.current = submenuActionableItems;
  const actionableItemsRef = useRef(actionableItems);
  actionableItemsRef.current = actionableItems;

  useEffect(() => {
    return installContextMenuKeyboardRuntime({
      addWindowKeydownListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            // Use capture phase to intercept before task list keyboard handler.
            window.addEventListener('keydown', listener, true);
            return () => window.removeEventListener('keydown', listener, true);
          },
      getActionableItemCount: () => actionableItemsRef.current.length,
      getHighlightIndex: () => highlightIdxRef.current,
      getHighlightedItem: () => {
        const item = actionableItemsRef.current[highlightIdxRef.current];
        if (!item) return undefined;
        return {
          hasSubmenu: Boolean(item.submenu?.length),
          onSelect: item.onSelect,
        };
      },
      setHighlightIndex: setRovingHighlightIdx,
      focusItemAtIndex: (index) => {
        window.requestAnimationFrame(() => {
          menuItemRefs.current[index]?.focus();
        });
      },
      onClose,
      isSubmenuOpen: () => submenuOwnerIdxRef.current !== -1,
      getSubmenuItemCount: () => {
        if (submenuOwnerIdxRef.current !== -1) {
          return submenuActionableItemsRef.current.length;
        }
        const item = actionableItemsRef.current[highlightIdxRef.current];
        return item?.submenu?.filter((child) => !child.separator && !child.disabled).length ?? 0;
      },
      getSubmenuHighlightIndex: () => submenuHighlightIdxRef.current,
      getSubmenuHighlightedItem: () => {
        const item = submenuActionableItemsRef.current[submenuHighlightIdxRef.current];
        if (!item) return undefined;
        return {
          hasSubmenu: Boolean(item.submenu?.length),
          onSelect: item.onSelect,
        };
      },
      setSubmenuHighlightIndex: setRovingSubmenuHighlightIdx,
      focusSubmenuItemAtIndex: (index) => {
        window.requestAnimationFrame(() => {
          submenuItemRefs.current[index]?.focus();
        });
      },
      openHighlightedSubmenu: () => {
        const idx = highlightIdxRef.current;
        const item = actionableItemsRef.current[idx];
        if (!item?.submenu?.length) return;
        setSubmenuOwnerIdx(idx);
      },
      closeSubmenu: () => setSubmenuOwnerIdx(-1),
      textDirection: () => textDirection,
    });
    // Stable across renders — runtime reads everything via refs.
  }, [onClose, setRovingHighlightIdx, setRovingSubmenuHighlightIdx, textDirection]);

  return createPortal(
    <>
      {/* Invisible backdrop to catch clicks outside */}
      <div
        className="fixed inset-0 z-[calc(var(--z-popover)-1)]"
        role="presentation"
        aria-hidden="true"
        onClick={handleBackdropClick}
        onContextMenu={handleBackdropClick}
      />
      <div
        ref={menuRef}
        role="menu"
        aria-label={t('common.actions')}
        aria-orientation="vertical"
        tabIndex={-1}
        className="fixed min-w-[var(--menu-min-w-lg)] bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] py-1 z-[var(--z-popover)] animate-[fade-in_0.1s_ease-out]"
        style={{ left: pos.x, top: pos.y }}
      >
        {items.map((item) => {
          const actionIdx = actionableItems.indexOf(item);
          const isOwner = actionIdx !== -1 && actionIdx === submenuOwnerIdx;
          const childActionable = item.submenu?.filter((c) => !c.separator && !c.disabled) ?? [];
          const submenuHighlightedKey = isOwner && submenuHighlightIdx >= 0
            ? childActionable[submenuHighlightIdx]?.key ?? null
            : null;
          return (
            <MenuItemRow
              key={item.key}
              item={item}
              onClose={closeWithFocusRestore}
              highlighted={actionIdx === highlightIdx}
              submenuOpen={isOwner}
              submenuHighlightedKey={submenuHighlightedKey}
              buttonRef={actionIdx === -1
                ? undefined
                : (node) => { menuItemRefs.current[actionIdx] = node; }}
              tabIndex={actionIdx === highlightIdx ? 0 : -1}
              submenuItemRefs={submenuItemRefs}
              textDirection={textDirection}
              onPointerOpenSubmenu={() => {
                if (actionIdx !== -1) setSubmenuOwnerIdx(actionIdx);
              }}
              onPointerCloseSubmenu={() => {
                if (isOwner) setSubmenuOwnerIdx(-1);
              }}
            />
          );
        })}
      </div>
    </>,
    document.body,
  );
}
