import { tryParseJson } from '../security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from '../objectGuards';

type DashboardSectionType =
  | 'ai_briefing'
  | 'focus'
  | 'schedule'
  | 'priority'
  | 'overdue_alert'
  | 'recently_completed'
  | 'upcoming_week'
  | 'someday_peek'
  | 'habits'
  | 'stats';

const DASHBOARD_SECTION_TYPES: DashboardSectionType[] = [
  'ai_briefing',
  'focus',
  'schedule',
  'priority',
  'overdue_alert',
  'recently_completed',
  'upcoming_week',
  'someday_peek',
  'habits',
  'stats',
];

const DASHBOARD_SECTION_TYPE_SET = new Set<string>(DASHBOARD_SECTION_TYPES);
const DASHBOARD_LAYOUT_KEYS = new Set(['sections', 'updated_by']);
const DASHBOARD_SECTION_KEYS = new Set(['type', 'limit']);

export interface DashboardSection {
  type: DashboardSectionType;
  limit?: number;
}

export interface DashboardLayout {
  sections: DashboardSection[];
  updated_by?: string | undefined;
}

export const DEFAULT_DASHBOARD_LAYOUT: DashboardLayout = {
  sections: [
    { type: 'ai_briefing' },
    { type: 'focus' },
    { type: 'habits' },
    { type: 'overdue_alert', limit: 4 },
    { type: 'priority' },
    { type: 'recently_completed' },
  ],
};

function isDashboardSection(value: unknown): value is DashboardSection {
  if (!isRecord(value)) return false;
  if (!hasOnlyKeys(value, DASHBOARD_SECTION_KEYS)) return false;
  if (typeof value.type !== 'string') return false;
  if (!DASHBOARD_SECTION_TYPE_SET.has(value.type)) return false;
  if (value.limit === undefined) return true;
  return typeof value.limit === 'number'
    && Number.isInteger(value.limit)
    && value.limit > 0;
}

export function parseDashboardLayoutPreference(raw: string | null): DashboardLayout {
  if (!raw) return DEFAULT_DASHBOARD_LAYOUT;
  const parseResult = tryParseJson(raw);
  if (!parseResult.ok) return DEFAULT_DASHBOARD_LAYOUT;

  const parsed = parseResult.value;
  if (!isRecord(parsed)) return DEFAULT_DASHBOARD_LAYOUT;
  if (!hasOnlyKeys(parsed, DASHBOARD_LAYOUT_KEYS)) return DEFAULT_DASHBOARD_LAYOUT;
  if (!Array.isArray(parsed.sections) || parsed.sections.length === 0) return DEFAULT_DASHBOARD_LAYOUT;
  if (!parsed.sections.every(isDashboardSection)) return DEFAULT_DASHBOARD_LAYOUT;
  if (parsed.updated_by !== undefined && typeof parsed.updated_by !== 'string') return DEFAULT_DASHBOARD_LAYOUT;
  return {
    sections: parsed.sections,
    updated_by: parsed.updated_by,
  };
}
