import type { ReactNode } from 'react';

import { TaskListSkeleton } from './SkeletonShimmer';

interface ModuleStatePanelProps {
  /**
   * Headline shown for `status` and `error` variants.
   *
   * Ignored for the `loading` variant — loading is a
   * skeleton-first experience, written copy ("Loading…") adds visual
   * noise and shifts when the eventual content swaps in. Loading
   * callers may still pass a value; it becomes the accessible label
   * on the live region rather than visible text.
   */
  title?: string;
  subtitle?: string | undefined;
  icon?: ReactNode | undefined;
  /**
   * optional per-view illustration. When present, replaces
   * the small `icon` glyph with a larger monoline scene that sets a
   * warmer tone for the empty state. Sits above the title with a
   * `mb-5` rather than the icon's `mb-4` so the larger artwork has
   * more breathing room.
   */
  illustration?: ReactNode | undefined;
  actionLabel?: string;
  onAction?: () => void;
  className?: string;
  /** Use "error" for error states (role="alert", aria-live="assertive").
   *  Use "loading" for skeleton shimmer loading states.
   *  Defaults to "status" (role="status", aria-live="polite"). */
  variant?: 'status' | 'error' | 'loading';
}

export default function ModuleStatePanel({
  title,
  subtitle,
  icon,
  illustration,
  actionLabel,
  onAction,
  className = '',
  variant = 'status',
}: ModuleStatePanelProps) {
  if (variant === 'loading') {
    // Loading is skeleton-first; we render only the skeleton
    // shimmer here. The optional `title` becomes an aria-label on the
    // live region so screen readers still hear "loading tasks" while
    // the visual presents the placeholder shape.
    return (
      <div
        className={className}
        role="status"
        aria-live="polite"
        {...(title ? { 'aria-label': title } : {})}
      >
        <TaskListSkeleton />
      </div>
    );
  }

  const isError = variant === 'error';
  return (
    <div
      className={`flex flex-col items-center justify-center py-12 sm:py-24 text-center ${className}`}
      role={isError ? 'alert' : 'status'}
      aria-live={isError ? 'assertive' : 'polite'}
    >
      {illustration ? (
        <div className="mb-5 text-text-muted/55">{illustration}</div>
      ) : (
        icon && <div className="mb-4 text-text-muted/60">{icon}</div>
      )}
      {title && <p className="text-text-secondary text-sm font-medium">{title}</p>}
      {subtitle && <p className="text-text-muted text-xs mt-1.5 max-w-[24rem] leading-relaxed">{subtitle}</p>}
      {actionLabel && onAction && (
        <button
          type="button"
          onClick={onAction}
          className="mt-4 text-xs px-4 py-2 rounded-r-control border border-card text-text-secondary hover:bg-surface-2 hover:border-popover active:scale-[0.97] transition-[color,background-color,border-color,transform] focus-ring-strong"
        >
          {actionLabel}
        </button>
      )}
    </div>
  );
}
