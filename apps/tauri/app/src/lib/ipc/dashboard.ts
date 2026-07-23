import { PREF_DASHBOARD_LAYOUT } from '../preferences/keys';
import { getPreference } from './settings';
import {
  parseDashboardLayoutPreference,
  type DashboardLayout,
  type DashboardSection,
} from './dashboard.logic';

export type { DashboardLayout, DashboardSection };

export async function getDashboardLayout(signal?: AbortSignal): Promise<DashboardLayout> {
  const raw = await getPreference(PREF_DASHBOARD_LAYOUT, signal);
  return parseDashboardLayoutPreference(raw);
}
