import { LONG_PRESS_IGNORE_ATTRIBUTE } from '@/lib/useLongPress';
import { CheckIcon } from '../ui/icons';
import { Tooltip } from '../ui/Tooltip';
import type { TaskCardActionHandler, TaskCardDisplayLabels } from './support';

const longPressIgnoreProps = { [LONG_PRESS_IGNORE_ATTRIBUTE]: '' };

/**
 * completion checkmark with a `stroke-dasharray`
 * draw-in. Used in place of the static `CheckIcon` during the
 * `completing` window so the tick appears to be drawn rather than
 * faded in. The dash length covers the longest plausible path through
 * the 12×12 viewBox (~16 units), set to 24 to overshoot so the
 * starting state is fully hidden regardless of stroke linecap.
 *
 * Reduced-motion: the global `*` reset in `accessibility.css` clamps
 * the animation duration, leaving the icon in its final drawn state
 * (`stroke-dashoffset: 0`) — exactly what we want, no manual gating
 * needed here.
 */
function CompletionCheckDraw({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 12 12"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      <path
        d="M2.5 6.2 L5 8.5 L9.5 3.5"
        strokeDasharray="24"
        strokeDashoffset="24"
        style={{ animation: 'var(--animate-check-draw)' }}
      />
    </svg>
  );
}

interface TaskCardActionButtonProps {
  rank?: number | undefined;
  isDone: boolean;
  canQuickReopen: boolean;
  disableComplete: boolean;
  completing: boolean;
  reopening: boolean;
  labels: TaskCardDisplayLabels;
  onComplete: TaskCardActionHandler;
  onReopen: TaskCardActionHandler;
}

export function TaskCardActionButton({
  rank,
  isDone,
  canQuickReopen,
  disableComplete,
  completing,
  reopening,
  labels,
  onComplete,
  onReopen,
}: TaskCardActionButtonProps) {
  if (isDone) {
    return (
      <Tooltip label={labels.reopen}>
        <button
          type="button"
          {...longPressIgnoreProps}
          onClick={event => onReopen(event)}
          disabled={!canQuickReopen || reopening || completing}
          aria-label={labels.reopen}
          className={`relative w-6 h-6 rounded-full border flex items-center justify-center text-sm leading-none transition-colors ${
            canQuickReopen && !reopening
              ? 'border-success/50 text-success hover:bg-[var(--success-tint-sm)] focus-ring-soft'
              : 'border-surface-3 text-text-muted'
          }`}
        >
          {/* 44x44 touch target \u2014 see CircleButton expander note. */}
          <span className="absolute -inset-2.5" aria-hidden="true" />
          {reopening ? '\u2026' : <CheckIcon className="w-3.5 h-3.5" />}
        </button>
      </Tooltip>
    );
  }

  if (rank != null) {
    return (
      <RankButton
        rank={rank}
        completing={completing}
        disabled={disableComplete}
        onComplete={onComplete}
        completeLabel={labels.complete}
      />
    );
  }

  return (
    <CircleButton
      completing={completing}
      disabled={disableComplete}
      onComplete={onComplete}
      completeLabel={labels.complete}
    />
  );
}

function RankButton({
  rank,
  completing,
  disabled,
  onComplete,
  completeLabel,
}: {
  rank: number;
  completing: boolean;
  disabled: boolean;
  onComplete: TaskCardActionHandler;
  completeLabel: string;
}) {
  return (
    <Tooltip label={completeLabel}>
      <button
        type="button"
        {...longPressIgnoreProps}
        onClick={event => onComplete(event)}
        disabled={disabled}
        aria-label={completeLabel}
        className={`group/btn relative w-6 h-6 rounded-full border flex items-center justify-center focus-ring-soft transition-[color,background-color,border-color,transform] duration-150 cursor-pointer active:scale-90 ${
          disabled
            ? 'border-surface-3 text-text-muted opacity-50 cursor-not-allowed'
            : completing
              ? 'bg-success border-success animate-check-pop'
              : 'border-surface-3 text-text-muted hover:border-success hover:bg-[var(--success-tint-sm)] group-hover:border-text-muted/50 focus-ring-soft'
        }`}
      >
        {/* visible button is 24x24. Pair it with a
          22x22 invisible expander (`-inset-2.5`) so the touch target
          measures 24+20 = 44 on every edge — matches WCAG 2.5.5 (AAA)
          / Apple HIG 44x44. The CircleButton sibling already had a
          -inset-2 expander which only delivered 40x40; the RankButton
          ranked variant had no expander at all. Both branches now
          render at the full 44x44 target.
        */}
        <span className="absolute -inset-2.5" aria-hidden="true" />
        <span
          className={`text-xs font-medium transition-opacity duration-100 select-none ${
            completing ? 'opacity-0' : 'opacity-100 group-hover/btn:opacity-0'
          }`}
        >
          {rank}
        </span>
        <span
          className={`absolute inset-0 flex items-center justify-center transition-opacity duration-100 select-none ${
            completing ? 'opacity-100 text-white' : 'opacity-0 group-hover/btn:opacity-100 text-success'
          }`}
        >
          {completing ? (
            <CompletionCheckDraw className="w-3 h-3" />
          ) : (
            <CheckIcon className="w-3 h-3" />
          )}
        </span>
      </button>
    </Tooltip>
  );
}

function CircleButton({
  completing,
  disabled,
  onComplete,
  completeLabel,
}: {
  completing: boolean;
  disabled: boolean;
  onComplete: TaskCardActionHandler;
  completeLabel: string;
}) {
  return (
    <Tooltip label={completeLabel}>
      <button
        type="button"
        {...longPressIgnoreProps}
        onClick={event => onComplete(event)}
        disabled={disabled}
        aria-label={completeLabel}
        className={`group/btn relative w-6 h-6 rounded-full border flex items-center justify-center focus-ring-soft transition-[color,background-color,border-color,transform] duration-150 cursor-pointer active:scale-90 ${
          disabled
            ? 'border-surface-3 opacity-50 cursor-not-allowed'
            : completing
              ? 'bg-success border-success animate-check-pop'
              : 'border-surface-3 hover:border-success hover:bg-[var(--success-tint-sm)] group-hover:border-text-muted/50 focus-ring-soft'
        }`}
      >
        {/* -inset-2 only stretched the 24x24 button
          to 24+16 = 40, two pixels short of the 44x44 minimum touch
          target. -inset-2.5 (10px each side) gives 24+20 = 44.
        */}
        <span className="absolute -inset-2.5" aria-hidden="true" />
        <span
          className={`transition-opacity duration-100 select-none ${
            completing ? 'opacity-100 text-white' : 'opacity-0 group-hover/btn:opacity-80 text-success'
          }`}
        >
          {completing ? (
            <CompletionCheckDraw className="w-3 h-3" />
          ) : (
            <CheckIcon className="w-3 h-3" />
          )}
        </span>
      </button>
    </Tooltip>
  );
}
