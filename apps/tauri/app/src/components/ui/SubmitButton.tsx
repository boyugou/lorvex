import { type ButtonHTMLAttributes, type ReactNode } from 'react';

import { useI18n } from '@/lib/i18n';
import { useReducedMotion } from '@/lib/reducedMotion';

/**
 * In-button progress affordance for slow-IPC submits.
 *
 * Renders a leading inline spinner + cross-fade text whenever
 * `isSaving` is true. The spinner animation is disabled when the user
 * has `prefers-reduced-motion: reduce` set so the affordance still
 * communicates "in flight" via the aria-busy + label swap, without
 * triggering a vestibular response.
 *
 * Use this in place of the bare `<button disabled={isSaving}>` +
 * label-swap pattern. The component does NOT supply visual chrome
 * (color, padding) — pass `className` to control appearance so the
 * primitive remains drop-in across both compact toolbar buttons and
 * primary action affordances.
 */
interface SubmitButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'disabled' | 'children'> {
  /** True while the submit IPC is in flight. Drives spinner + cross-fade. */
  isSaving: boolean;
  /** Independent disable signal (validation, etc.). When `isSaving` is also true, the button stays disabled. */
  disabled?: boolean;
  /** Idle label content. Use a translation string. */
  children: ReactNode;
  /**
   * Optional override for the saving-state label. Defaults to
   * `t('common.saving')`. Pass when the component has a more specific
   * verb (e.g. "Adding…" vs "Saving…").
   */
  savingLabel?: string;
}

export function SubmitButton({
  isSaving,
  disabled = false,
  children,
  savingLabel,
  className = '',
  type = 'submit',
  ...rest
}: SubmitButtonProps) {
  const { t } = useI18n();
  const reducedMotion = useReducedMotion();
  const label = isSaving ? (savingLabel ?? t('common.saving')) : children;
  return (
    <button
      // Wrapper forwards a defaulted `type` prop ('submit'); the rule
      // wants a static string but the wrapper guarantees a safe default
      // while still allowing callers to opt into 'button'.
      // eslint-disable-next-line react/button-has-type
      type={type}
      {...rest}
      disabled={disabled || isSaving}
      aria-busy={isSaving || undefined}
      data-saving={isSaving || undefined}
      className={`relative inline-flex items-center justify-center gap-1.5 transition-[color,background-color,box-shadow,opacity,transform] duration-150 ${className}`}
    >
      {isSaving && (
        <SubmitSpinner reducedMotion={reducedMotion} />
      )}
      <span
        className={`transition-opacity duration-150 ${isSaving ? 'opacity-90' : 'opacity-100'}`}
      >
        {label}
      </span>
    </button>
  );
}

function SubmitSpinner({ reducedMotion }: { reducedMotion: boolean }) {
  // 14px circular SVG spinner. When reduced-motion is on, render the
  // static ring (no rotation) — the parent's aria-busy + label swap
  // still communicate the in-flight state.
  return (
    <svg
      aria-hidden="true"
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      className={reducedMotion ? '' : 'animate-spin'}
    >
      <circle
        cx="12"
        cy="12"
        r="9"
        stroke="currentColor"
        strokeOpacity="0.25"
        strokeWidth="3"
      />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="currentColor"
        strokeWidth="3"
        strokeLinecap="round"
      />
    </svg>
  );
}
