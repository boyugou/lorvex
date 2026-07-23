/**
 * Consistent SVG icon components for UI chrome.
 *
 * All icons use `currentColor` so they inherit text color from their parent.
 * Pass `className` for Tailwind sizing/color overrides.
 * Default viewBox is 16x16; each icon is designed to work at 16-20px.
 */

import type { SVGProps } from 'react';

type IconProps = SVGProps<SVGSVGElement>;

const defaults: IconProps = {
  width: 16,
  height: 16,
  viewBox: '0 0 16 16',
  fill: 'none',
  xmlns: 'http://www.w3.org/2000/svg',
};

function icon(props: IconProps, overrides?: Partial<IconProps>): IconProps {
  return { ...defaults, ...overrides, ...props };
}

// ── Navigation icons ────────────────────────────────────────────────

/** Sun icon for Today view */
export function SunIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <circle cx="8" cy="8" r="3" stroke="currentColor" strokeWidth="1.5" />
      <path d="M8 1.5V3M8 13v1.5M1.5 8H3M13 8h1.5M3.17 3.17l1.06 1.06M11.77 11.77l1.06 1.06M3.17 12.83l1.06-1.06M11.77 4.23l1.06-1.06" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Calendar icon for Upcoming view */
export function CalendarUpcomingIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="2" y="3" width="12" height="11" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M2 6.5h12" stroke="currentColor" strokeWidth="1.5" />
      <path d="M5 1.5v3M11 1.5v3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Clipboard/list icon for All Tasks */
export function ClipboardIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="3" y="2" width="10" height="12" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M6 6h4M6 9h3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Thought bubble for Someday view */
export function ThoughtBubbleIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M4 11.5c-1.5-.5-2.5-2-2.5-3.75C1.5 5.1 3.9 3 8 3s6.5 2.1 6.5 4.75c0 2.65-2.4 4.75-6.5 4.75-.6 0-1.2-.05-1.75-.14L4 13.5v-2z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

/** Calendar with day marker for Calendar view */
export function CalendarDayIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="2" y="3" width="12" height="11" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M2 6.5h12" stroke="currentColor" strokeWidth="1.5" />
      <path d="M5 1.5v3M11 1.5v3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <rect x="6" y="8.5" width="4" height="3" rx="0.5" fill="currentColor" />
    </svg>
  );
}

/** 2x2 grid for Eisenhower view */
export function GridIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="2" y="2" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.5" />
      <rect x="9" y="2" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.5" />
      <rect x="2" y="9" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.5" />
      <rect x="9" y="9" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

/** Columns for Kanban view */
export function KanbanIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="1.5" y="2" width="3.5" height="12" rx="1" stroke="currentColor" strokeWidth="1.3" />
      <rect x="6.25" y="2" width="3.5" height="9" rx="1" stroke="currentColor" strokeWidth="1.3" />
      <rect x="11" y="2" width="3.5" height="7" rx="1" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  );
}

/** Chain link for Dependencies view */
export function LinkIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M6.5 9.5l3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M9 7l1.8-1.8a2.1 2.1 0 0 0-3-3L6 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M7 9l-1.8 1.8a2.1 2.1 0 0 0 3 3L10 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Flame for Habits view */
export function FlameIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M8 1.5C8 1.5 4 5.5 4 9a4 4 0 0 0 8 0c0-3.5-4-7.5-4-7.5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M8 14a2 2 0 0 0 2-2c0-1.5-2-3.5-2-3.5S6 10.5 6 12a2 2 0 0 0 2 2z" fill="currentColor" />
    </svg>
  );
}

/** Notebook for Journal view */
export function NotebookIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="3.5" y="1.5" width="10" height="13" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M6.5 5h4M6.5 8h3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M3.5 4h-1M3.5 7h-1M3.5 10h-1" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Pencil icon */
export function PencilIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M11.5 2.5l2 2-8.5 8.5H3v-2l8.5-8.5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M9.5 4.5l2 2" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

/** Sparkle/star for Memory view */
export function SparkleIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M8 1l1.8 4.2L14 7l-4.2 1.8L8 13l-1.8-4.2L2 7l4.2-1.8L8 1z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round" />
    </svg>
  );
}

/** Bar chart for Review view */
export function ChartIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="2" y="9" width="3" height="5" rx="0.5" stroke="currentColor" strokeWidth="1.3" />
      <rect x="6.5" y="5" width="3" height="9" rx="0.5" stroke="currentColor" strokeWidth="1.3" />
      <rect x="11" y="2" width="3" height="12" rx="0.5" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  );
}

/** Lightning bolt for Changelog view */
export function BoltIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M9 1.5L4 9h4l-1 5.5L12 7H8l1-5.5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

/** Gear for Settings view */
export function GearIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <circle cx="8" cy="8" r="2.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M8 1v1.5M8 13.5V15M1 8h1.5M13.5 8H15M2.93 2.93l1.06 1.06M11.77 11.77l1.06 1.06M13.07 2.93l-1.06 1.06M4.23 11.77l-1.06 1.06" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

/** Target/crosshair for Focus mode */
export function TargetIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <circle cx="8" cy="8" r="6" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="8" cy="8" r="2.5" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="8" cy="8" r="0.75" fill="currentColor" />
    </svg>
  );
}

// ── Action/palette icons ────────────────────────────────────────────

/** Plus icon for Add actions */
export function PlusIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M8 3v10M3 8h10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Arrow-into-box for Move action */
export function MoveIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M4 8h8M9 5l3 3-3 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M2 3v10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Box/archive icon */
export function ArchiveIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="1.5" y="2" width="13" height="3.5" rx="1" stroke="currentColor" strokeWidth="1.5" />
      <path d="M3 5.5v7.5a1.5 1.5 0 0 0 1.5 1.5h7a1.5 1.5 0 0 0 1.5-1.5V5.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M6.5 9h3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Trash can for Delete actions */
export function TrashIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M3 4.5h10M6 4.5V3a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M4.5 4.5l.5 8.5a1.5 1.5 0 0 0 1.5 1.5h3a1.5 1.5 0 0 0 1.5-1.5l.5-8.5" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

/** Warning triangle */
export function WarningIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M8 2L1.5 13.5h13L8 2z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M8 6.5v3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <circle cx="8" cy="11.5" r="0.75" fill="currentColor" />
    </svg>
  );
}

/** Magnifying glass for Search */
export function SearchIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <circle cx="7" cy="7" r="4.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M10.5 10.5L14 14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

// ── Content/contextual icons ────────────────────────────────────────

/** Checkmark */
export function CheckIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M3.5 8.5L6.5 11.5L12.5 4.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Undo/reopen arrow */
export function UndoIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M4 7h5.5a3.5 3.5 0 0 1 0 7H8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M7 4L4 7l3 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Play/resume triangle */
export function PlayIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M4.5 2.5l9 5.5-9 5.5V2.5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

/** Clock/alarm */
export function ClockIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <circle cx="8" cy="8" r="6" stroke="currentColor" strokeWidth="1.5" />
      <path d="M8 4.5V8l2.5 1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Recurrence/refresh arrows */
export function RecurrenceIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M12 5.5A5 5 0 0 0 3.5 7M4 10.5A5 5 0 0 0 12.5 9" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M12 2.5v3h-3M4 13.5v-3h3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Timer/stopwatch for Duration */
export function TimerIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <circle cx="8" cy="9" r="5.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M8 6v3l2 1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M6.5 1.5h3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Flag for Priority */
export function FlagIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M3 14V2.5l9.5 3.75L3 10" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

/** Right arrow for Move to list */
export function ArrowRightIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M3 8h10M9 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** External/open in new */
export function ExternalIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M6 3H3v10h10v-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M9 2h5v5M14 2L7 9" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** X/close for Cancel */
export function XIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/** Lightbulb for learnings */
export function LightbulbIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M6 12.5h4M6.5 14h3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
      <path d="M5.5 10c-1.2-1-2-2.5-2-4a4.5 4.5 0 0 1 9 0c0 1.5-.8 3-2 4v1h-5v-1z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

/** Construction barrier for blockers */
export function BarrierIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <rect x="1.5" y="5" width="13" height="5" rx="1" stroke="currentColor" strokeWidth="1.5" />
      <path d="M5 5l-3 5M9 5l-3 5M13 5l-3 5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M3.5 10v3M12.5 10v3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/**
 * Down-pointing chevron used for expand/collapse affordances and dropdown
 * triggers. Replaces the `▼` Unicode glyph that
 * couldn't flip for RTL, rendered at sub-pixel sizes on Windows
 * ClearType, and didn't honor the icon stroke weight of the rest of the
 * UI. Rotate via Tailwind `-rotate-90` (collapsed) / `rotate-180` (open
 * in dropdowns) so a single asset covers all directions.
 */
export function ChevronDownIcon(props: IconProps) {
  return (
    <svg {...icon(props)} aria-hidden="true">
      <path d="M4 6.5L8 10.5L12 6.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
