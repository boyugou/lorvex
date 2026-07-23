import { describe, expect, it } from 'vitest';

import {
  DEFAULT_SIDEBAR_MODULE_CONFIG,
  parseSidebarModuleConfig,
  parseSidebarVisibleModulesPreference,
} from './sidebarModules';

describe('sidebar module preference parsing', () => {
  it('falls back to the default config for absent or invalid stored values', () => {
    expect(parseSidebarModuleConfig(null)).toEqual(DEFAULT_SIDEBAR_MODULE_CONFIG);
    expect(parseSidebarModuleConfig('not-json')).toEqual(DEFAULT_SIDEBAR_MODULE_CONFIG);
    expect(parseSidebarModuleConfig('[]')).toEqual(DEFAULT_SIDEBAR_MODULE_CONFIG);
    expect(parseSidebarModuleConfig('{"show":[],"more":[]}')).toEqual(DEFAULT_SIDEBAR_MODULE_CONFIG);
  });

  it('normalizes valid config and preserves at least one primary module', () => {
    expect(parseSidebarModuleConfig('{"show":["calendar"],"more":["today","calendar"]}'))
      .toEqual({ show: ['today', 'calendar'], more: [] });
  });

  it('derives the flat visible module list from the same parser', () => {
    expect(parseSidebarVisibleModulesPreference('{"show":["today"],"more":["memory"]}'))
      .toEqual(['today', 'memory']);
  });
});
