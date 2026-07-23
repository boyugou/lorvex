import type { ReactNode } from 'react';
import { ModalShell } from './overlay';

/**
 * Canonical Modal size scale.
 *
 *   sm: 400px — short confirms (ConfirmDialog)
 *   md: 480px — compact dialogs (HelpMenu)
 *   lg: 560px — standard dialogs (CommandPalette, QuickCapture, WelcomeModal,
 *               HistoryModal)
 *   xl: 640px — wide dialogs (KeyboardShortcutsPanel)
 *
 * Width values resolve from CSS custom properties (`--modal-w-*`) defined
 * in `index.css` so a future tweak to the scale propagates everywhere
 * without touching component code.
 */
type ModalSize = 'sm' | 'md' | 'lg' | 'xl';

const SIZE_WIDTH: Record<ModalSize, string> = {
  sm: 'max-w-[var(--modal-w-sm)]',
  md: 'max-w-[var(--modal-w-md)]',
  lg: 'max-w-[var(--modal-w-lg)]',
  xl: 'max-w-[var(--modal-w-xl)]',
};

interface ModalProps {
  open: boolean;
  onClose: () => void;
  /** Canonical size token. Defaults to "md". */
  size?: ModalSize;
  children: ReactNode;
  /** Extra className applied to the panel — for layout (max-height, flex). */
  panelClassName?: string;
  /** Override the resting backdrop. Defaults to the theme-aware `--color-overlay`. */
  backdropClassName?: string;
  /** Flex alignment within the viewport. Default centers vertically. */
  align?: string;
  /** z-index utility. Defaults to modal layer. */
  zIndex?: string;
  /** Whether to dismiss on backdrop click. Default true. */
  backdropDismiss?: boolean;
  ariaLabel?: string;
  ariaLabelledBy?: string;
  ariaDescribedBy?: string;
  autoFocus?: boolean;
  /**
   * explicit focus target. When provided, Modal focuses
   * this element on mount (in lieu of the panel itself) — eliminates
   * the historical pattern where consumers passed `autoFocus={false}`
   * and shipped their own `useEffect(() => inputRef.current?.focus())`
   * dance, which has been a recurring source of effect-deps bugs (see
   * in QuickCaptureForm).
   */
  focusTarget?: { current: { focus: () => void } | null };
  triggerElement?: HTMLElement | null;
}

/**
 * High-level Modal primitive on top of ModalShell. Owns the canonical
 * panel chrome — width, surface, border, radius, shadow, animation —
 * so consumers only supply the inner content + size token.
 */
export function Modal({
  open,
  onClose,
  size = 'md',
  children,
  panelClassName = '',
  backdropClassName,
  align = 'items-center justify-center',
  zIndex = 'z-[var(--z-modal)]',
  backdropDismiss = true,
  ariaLabel,
  ariaLabelledBy,
  ariaDescribedBy,
  autoFocus,
  focusTarget,
  triggerElement,
}: ModalProps) {
  const panelChrome =
    'w-full ' +
    SIZE_WIDTH[size] +
    // modals use --animate-modal-in (calm easeOutCubic)
    // rather than --animate-toast-in (springy overshoot). Toasts are
    // peripheral and benefit from a tiny "pop" to draw notice; modals
    // are central and a big springy panel reads as wobbly chrome.
    ' bg-surface-1 border border-popover rounded-r-modal shadow-[var(--shadow-modal)] overflow-hidden animate-modal-in';
  // exactOptionalPropertyTypes on the underlying ModalShellProps means
  // we can't pass `ariaLabel: undefined` — only conditionally include
  // it when defined.
  const optional: {
    ariaLabel?: string;
    ariaLabelledBy?: string;
    ariaDescribedBy?: string;
    triggerElement?: HTMLElement | null;
    focusTarget?: { current: { focus: () => void } | null };
  } = {};
  if (ariaLabel !== undefined) optional.ariaLabel = ariaLabel;
  if (ariaLabelledBy !== undefined) optional.ariaLabelledBy = ariaLabelledBy;
  if (ariaDescribedBy !== undefined) optional.ariaDescribedBy = ariaDescribedBy;
  if (triggerElement !== undefined) optional.triggerElement = triggerElement;
  if (focusTarget !== undefined) optional.focusTarget = focusTarget;
  return (
    <ModalShell
      open={open}
      onClose={onClose}
      zIndex={zIndex}
      align={align}
      backdropDismiss={backdropDismiss}
      backdropClassName={
        backdropClassName ??
        // drop `backdrop-blur-xs` from the default
        // backdrop. The liquid_glass appearance profile (see index.css
        // around `:root[data-appearance-profile='liquid_glass']`) draws
        // its own per-surface glass refraction on dialogs, and stacking
        // a second blur on the backdrop turns the background to mush —
        // the glass effect requires *clear* content behind it to
        // refract, not pre-blurred slurry. We rely on `--color-overlay`
        // (per-theme) for the dim wash; the panel's
        // own surface treatment carries the depth cue.
        'bg-[var(--color-overlay)] animate-[fade-in_0.12s_ease-out]'
      }
      panelClassName={`${panelChrome} ${panelClassName}`}
      autoFocus={autoFocus ?? true}
      {...optional}
    >
      {children}
    </ModalShell>
  );
}
