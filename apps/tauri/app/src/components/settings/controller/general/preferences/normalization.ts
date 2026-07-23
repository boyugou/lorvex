import {
  normalizeScheduledTimePreference,
  normalizeScheduledWeekdayPreference,
} from '@/lib/scheduledPreferences.logic';
import { hasOnlyKeys, isPlainRecord as isObjectRecord } from '@/lib/objectGuards';
import { normalizeTimezonePreference } from '@/lib/dates/timezone';

import type { NormalizedAdvancedPreferences } from './types';

export const DEFAULT_WORKING_HOURS_START = '09:00';
export const DEFAULT_WORKING_HOURS_END = '18:00';
export const DEFAULT_WEEKLY_REVIEW_DAY = 'friday';
export const DEFAULT_WEEKLY_REVIEW_TIME = '16:00';
export const DEFAULT_MORNING_BRIEFING_TIME = '08:00';

const WORKING_HOURS_KEYS = new Set(['end', 'start']);
const CANONICAL_HH_MM = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export {
  normalizeScheduledTimePreference,
  normalizeScheduledWeekdayPreference,
};

function hasOnlyWorkingHoursKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, WORKING_HOURS_KEYS);
}

function isCanonicalTimeString(value: unknown): value is string {
  return typeof value === 'string' && CANONICAL_HH_MM.test(value);
}

export function normalizeWorkingHoursPreference(value: unknown): { start: string; end: string } {
  const fallback = {
    start: DEFAULT_WORKING_HOURS_START,
    end: DEFAULT_WORKING_HOURS_END,
  };
  if (!isObjectRecord(value) || !hasOnlyWorkingHoursKeys(value)) return fallback;
  if (!isCanonicalTimeString(value.start) || !isCanonicalTimeString(value.end)) {
    return fallback;
  }
  return {
    start: value.start,
    end: value.end,
  };
}

export function normalizeAdvancedPreferenceDraft(args: {
  timezone: string;
  systemTimezone: string;
  weeklyReviewDay: string;
  weeklyReviewTime: string;
  morningBriefingTime: string;
}): NormalizedAdvancedPreferences {
  return {
    timezone: normalizeTimezonePreference(args.timezone, args.systemTimezone),
    weeklyReviewDay: normalizeScheduledWeekdayPreference(
      args.weeklyReviewDay,
      DEFAULT_WEEKLY_REVIEW_DAY,
    ),
    weeklyReviewTime: normalizeScheduledTimePreference(
      args.weeklyReviewTime,
      DEFAULT_WEEKLY_REVIEW_TIME,
    ),
    morningBriefingTime: normalizeScheduledTimePreference(
      args.morningBriefingTime,
      DEFAULT_MORNING_BRIEFING_TIME,
    ),
  };
}
