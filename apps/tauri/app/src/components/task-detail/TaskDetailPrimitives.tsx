import { useState, type ReactNode } from 'react';
import { TASK_STATUS } from '@lorvex/shared/types';

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <p className="text-text-muted/50 text-2xs font-semibold uppercase tracking-wider mb-2">{children}</p>
  );
}

/** Collapsible section group with a subtle header and optional default-collapsed state. */
export function DetailSectionGroup({
  title,
  children,
  defaultExpanded = true,
}: {
  title: string;
  children: ReactNode;
  defaultExpanded?: boolean;
}) {
  const [expanded, setExpanded] = useState(defaultExpanded);

  return (
    <div className="rounded-r-control">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        aria-expanded={expanded}
        className="group flex items-center gap-1.5 w-full text-start text-2xs font-semibold uppercase tracking-wider text-text-muted/50 hover:text-text-muted transition-colors py-1.5 px-1 -mx-1 rounded-r-control hover:bg-surface-2/30 focus-ring-soft"
      >
        <svg
          aria-hidden="true"
          className="w-2.5 h-2.5 transition-transform duration-200 opacity-40 group-hover:opacity-70"
          style={{ transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)' }}
          viewBox="0 0 16 16"
          fill="currentColor"
        >
          <path d="M6 3.5l4.5 4.5L6 12.5" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {title}
      </button>
      {expanded && (
        <div className="mt-1.5 ps-0.5">
          {children}
        </div>
      )}
    </div>
  );
}

interface DepLinkProps {
  id: string;
  title?: string | undefined;
  status?: string | undefined;
  onSelect?: ((id: string) => void) | undefined;
}

export function DepLink({ id, title, status, onSelect }: DepLinkProps) {
  const done = status === TASK_STATUS.completed;
  return (
    <button type="button"
      onClick={() => onSelect?.(id)}
      className="flex items-center gap-2 text-sm text-text-secondary hover:text-accent transition-colors w-full text-start rounded-r-control focus-ring-soft"
    >
      <span className={`w-3 h-3 rounded-full shrink-0 ${
        done ? 'bg-success' : 'border border-surface-3'
      }`} />
      <span className={done ? 'line-through text-text-muted' : ''}>
        {title ?? id.slice(0, 8) + '…'}
      </span>
    </button>
  );
}
