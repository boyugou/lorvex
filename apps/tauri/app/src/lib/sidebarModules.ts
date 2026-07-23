import { tryParseJson } from './security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from './objectGuards';

const SIDEBAR_PRIMARY_MODULES = [
  'today',
  'upcoming',
  'all_tasks',
  'someday',
] as const;

const SIDEBAR_SECONDARY_MODULES = [
  'calendar',
  'eisenhower',
  'kanban',
  'dependencies',
  'habits',
  'daily_review',
  'memory',
  'review',
  'recurring',
  'ai_changelog',
  'focus',
] as const;

export const SIDEBAR_MODULES = [
  ...SIDEBAR_PRIMARY_MODULES,
  ...SIDEBAR_SECONDARY_MODULES,
] as const;

export type SidebarPrimaryModule = (typeof SIDEBAR_PRIMARY_MODULES)[number];
export type SidebarModule = (typeof SIDEBAR_MODULES)[number];
export type SidebarModuleState = 'show' | 'more' | 'hidden';

/** Structured config for sidebar module visibility (3-state). */
export interface SidebarModuleConfig {
  show: SidebarModule[];
  more: SidebarModule[];
}

/** Default 3-state config. Primary modules always default to 'show'. */
export const DEFAULT_SIDEBAR_MODULE_CONFIG: SidebarModuleConfig = {
  show: ['today', 'upcoming', 'all_tasks', 'someday', 'calendar', 'eisenhower', 'focus'],
  more: ['kanban', 'dependencies', 'habits', 'daily_review', 'memory', 'review', 'recurring', 'ai_changelog'],
};

export function cloneSidebarModuleConfig(config: SidebarModuleConfig): SidebarModuleConfig {
  return {
    show: [...config.show],
    more: [...config.more],
  };
}

const MODULE_SET = new Set<string>(SIDEBAR_MODULES);
const PRIMARY_MODULE_SET = new Set<string>(SIDEBAR_PRIMARY_MODULES);
const SIDEBAR_MODULE_CONFIG_KEYS = new Set(['show', 'more']);

function isSidebarModule(value: string): value is SidebarModule {
  return MODULE_SET.has(value);
}

export function isSidebarPrimaryModule(value: string): value is SidebarPrimaryModule {
  return PRIMARY_MODULE_SET.has(value);
}

/** Get the effective state for a module given a `SidebarModuleConfig`. */
export function getModuleState(module: SidebarModule, config: SidebarModuleConfig): SidebarModuleState {
  if (config.show.includes(module)) return 'show';
  if (config.more.includes(module)) return 'more';
  return 'hidden';
}

/** Check if a module should be shown (either 'show' or 'more'). */
export function isModuleVisible(module: SidebarModule, config: SidebarModuleConfig): boolean {
  return config.show.includes(module) || config.more.includes(module);
}

/** Check if a module is in the toolbox ('more' state) according to a config. */
export function isModuleInToolbox(module: SidebarModule, config: SidebarModuleConfig): boolean {
  return config.more.includes(module);
}

/** Serialize a SidebarModuleConfig to a JSON string for storage. */
export function serializeSidebarModuleConfig(config: SidebarModuleConfig): string {
  return JSON.stringify(sidebarModuleConfigPreferenceValue(config));
}

export function sidebarModuleConfigPreferenceValue(config: SidebarModuleConfig): SidebarModuleConfig {
  return {
    show: [...config.show],
    more: [...config.more],
  };
}

function parseModuleArray(value: unknown, options: { allowEmpty: boolean }): SidebarModule[] | null {
  if (!Array.isArray(value)) return null;
  if (!options.allowEmpty && value.length === 0) return null;
  if (!value.every((item): item is SidebarModule => typeof item === 'string' && isSidebarModule(item))) {
    return null;
  }
  return Array.from(new Set(value));
}

/**
 * Normalize a raw config, ensuring at least one primary module in `show`.
 */
function normalizeConfig(config: SidebarModuleConfig): SidebarModuleConfig {
  let show = Array.from(new Set(config.show));
  let more = Array.from(new Set(config.more));
  // Remove duplicates: if something is in both, keep it in show.
  const showSet = new Set(show);
  more = more.filter((m) => !showSet.has(m));

  // Ensure at least one primary module in show. If the user already
  // kept a primary module in "more", promote that one instead of
  // duplicating it across both buckets.
  if (!show.some((m) => PRIMARY_MODULE_SET.has(m))) {
    const promotedPrimary = more.find((m) => PRIMARY_MODULE_SET.has(m)) ?? 'today';
    show = [promotedPrimary, ...show.filter((m) => m !== promotedPrimary)];
    more = more.filter((m) => m !== promotedPrimary);
  }
  return { show, more };
}

/**
 * Parse the stored sidebar_visible_modules preference.
 * Expects format: `{ show: SidebarModule[], more: SidebarModule[] }`.
 */
export function parseSidebarModuleConfig(raw: string | null | undefined): SidebarModuleConfig {
  if (!raw) return cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);

  const parseResult = tryParseJson(raw);
  if (!parseResult.ok) return cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);

  const parsed = parseResult.value;
  if (!isRecord(parsed)) {
    return cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);
  }
  if (!hasOnlyKeys(parsed, SIDEBAR_MODULE_CONFIG_KEYS)) {
    return cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);
  }

  const showArr = parseModuleArray(parsed.show, { allowEmpty: false });
  if (!showArr) return cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);
  const moreArr = parsed.more === undefined ? [] : parseModuleArray(parsed.more, { allowEmpty: true });
  if (!moreArr) return cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG);
  return normalizeConfig({ show: showArr, more: moreArr });
}

/**
 * Returns a flat list of all visible modules (show + more).
 * Used by navigation guards that only need "is this module accessible" checks.
 */
export function parseSidebarVisibleModulesPreference(raw: string | null | undefined): SidebarModule[] {
  const config = parseSidebarModuleConfig(raw);
  return [...config.show, ...config.more];
}
