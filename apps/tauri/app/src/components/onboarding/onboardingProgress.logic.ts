/**
 * onboardingProgress.logic — pure functions that compute the onboarding
 * checklist state from the existing signals already available to the
 * Tauri app frontend (MCP server status, sync preferences, task stats,
 * and notification permission).
 *
 * the previous WelcomeView was a single-shot empty-state
 * banner: it appeared when the Today pool was empty and disappeared as
 * soon as anything landed. That's three lines of static copy in front
 * of a multi-step setup flow that requires installing an MCP binary,
 * pasting config into an external assistant, optionally choosing a
 * sync folder, and granting OS notifications.
 * The user had no progress signal and no scaffolded path.
 *
 * This file lives separately (logic-only, no React, no IO) so the
 * vitest harness — which targets `.logic.ts` modules in a Node
 * environment — can exercise the rules in isolation. The component
 * (`OnboardingChecklist.tsx`) imports these helpers and provides the
 * UI layer + i18n.
 */

import type { TranslationKey } from '@/lib/i18n';

/** All onboarding steps the checklist tracks, in display order. */
export const ONBOARDING_STEPS = [
  'mcp',
  'sync',
  'firstTask',
  'notifications',
] as const;

export type OnboardingStepId = (typeof ONBOARDING_STEPS)[number];

/**
 * Inputs derived from existing app-wide signals. We accept everything
 * as a plain shape so the logic file stays IO-free; the React component
 * is responsible for hooking up `useMcpServerStatus`, `usePreference`,
 * `getOverview` etc. and threading the values in.
 */
export interface OnboardingSignals {
  /** `mcpServerStatus.resolved`. `null` when the host runtime can't host MCP. */
  mcpResolved: boolean | null;
  /** Raw `PREF_SYNC_BACKEND_KIND` preference value (e.g. `'filesystem_bridge'`, `null`). */
  syncBackendKind: string | null;
  /** True when the user has at least one task (open or completed). Derived from stats. */
  hasAnyTask: boolean;
  /** True when the OS has granted notification permission. */
  notificationsGranted: boolean | null;
}

export interface OnboardingStepState {
  id: OnboardingStepId;
  /** True when the step's success criterion is satisfied. */
  done: boolean;
  /** True when the step has fundamentally regressed (sync turned off, MCP binary disappeared, …). */
  regressed: boolean;
}

export interface OnboardingProgress {
  steps: OnboardingStepState[];
  /** Number of steps marked done. */
  completed: number;
  /** Total number of steps tracked. */
  total: number;
  /**
   * `true` when every step is done. The checklist auto-hides in this
   * state unless the user opens it explicitly from the help menu.
   */
  allDone: boolean;
  hasRegression: boolean;
}

/**
 * Compute the per-step state and the aggregate counters. Pure: same
 * inputs always yield the same output, no clocks, no Tauri.
 */
export function computeOnboardingProgress(
  signals: OnboardingSignals,
  previouslyDone: ReadonlySet<OnboardingStepId> = new Set(),
): OnboardingProgress {
  const stepDone: Record<OnboardingStepId, boolean> = {
    mcp: signals.mcpResolved === true,
    sync: typeof signals.syncBackendKind === 'string' && signals.syncBackendKind.trim() !== '',
    firstTask: signals.hasAnyTask === true,
    notifications: signals.notificationsGranted === true,
  };

  const steps: OnboardingStepState[] = ONBOARDING_STEPS.map((id) => ({
    id,
    done: stepDone[id],
    regressed: !stepDone[id] && previouslyDone.has(id),
  }));

  const completed = steps.filter((s) => s.done).length;
  const total = steps.length;
  return {
    steps,
    completed,
    total,
    allDone: completed === total,
    hasRegression: steps.some((s) => s.regressed),
  };
}

/**
 * Whether the checklist should be visible right now. Hidden when the
 * user has dismissed it AND every step is satisfied AND nothing
 * regressed. We re-surface on regression so the user gets guidance
 * back if (e.g.) they turn sync off after dismissing the card.
 */
export function shouldShowOnboardingChecklist(
  progress: OnboardingProgress,
  dismissed: boolean,
): boolean {
  if (progress.hasRegression) return true;
  if (progress.allDone) return false;
  return !dismissed;
}

/**
 * i18n key + deep-link metadata per step. Returned as data (not JSX) so
 * the logic file remains pure and the same metadata can drive the
 * Help-menu summary, the sidebar card, and the empty-state suggestions
 * without each surface re-deriving the translation keys.
 */
export interface OnboardingStepMeta {
  id: OnboardingStepId;
  /** Translation key for the step's title. */
  titleKey: TranslationKey;
  /** Translation key for the action button label. */
  actionKey: TranslationKey;
  /** Translation key for the help-text shown under the title. */
  hintKey: TranslationKey;
  /**
   * Settings sectionId or pseudo-route the action should navigate to.
   * `'mcp'` → Settings → Assistant MCP, `'sync'` → Settings → Sync,
   * `'notifications'` → Settings → General notification controls,
   * `'quickCapture'` → triggers Quick Capture overlay.
   */
  action:
    | { kind: 'settings'; sectionId: string }
    | { kind: 'quickCapture' };
}

export const ONBOARDING_STEP_META: Record<OnboardingStepId, OnboardingStepMeta> = {
  mcp: {
    id: 'mcp',
    titleKey: 'onboarding.step.mcp.title',
    actionKey: 'onboarding.step.mcp.action',
    hintKey: 'onboarding.step.mcp.hint',
    action: { kind: 'settings', sectionId: 'settings-section-mcp' },
  },
  sync: {
    id: 'sync',
    titleKey: 'onboarding.step.sync.title',
    actionKey: 'onboarding.step.sync.action',
    hintKey: 'onboarding.step.sync.hint',
    action: { kind: 'settings', sectionId: 'settings-section-sync' },
  },
  firstTask: {
    id: 'firstTask',
    titleKey: 'onboarding.step.firstTask.title',
    actionKey: 'onboarding.step.firstTask.action',
    hintKey: 'onboarding.step.firstTask.hint',
    action: { kind: 'quickCapture' },
  },
  notifications: {
    id: 'notifications',
    titleKey: 'onboarding.step.notifications.title',
    actionKey: 'onboarding.step.notifications.action',
    hintKey: 'onboarding.step.notifications.hint',
    action: { kind: 'settings', sectionId: 'settings-section-general' },
  },
};

export function parsePreviouslyDoneState(raw: string | null): Set<OnboardingStepId> {
  if (!raw) return new Set();
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    const result = new Set<OnboardingStepId>();
    for (const id of parsed) {
      if (typeof id !== 'string') continue;
      if ((ONBOARDING_STEPS as readonly string[]).includes(id)) {
        result.add(id as OnboardingStepId);
      }
    }
    return result;
  } catch {
    return new Set();
  }
}

export function buildPreviouslyDoneState(
  progress: OnboardingProgress,
  previouslyDone: ReadonlySet<OnboardingStepId> = new Set(),
): OnboardingStepId[] {
  const ids: OnboardingStepId[] = [];
  for (const step of ONBOARDING_STEPS) {
    if (previouslyDone.has(step) || progress.steps.find((s) => s.id === step)?.done) {
      ids.push(step);
    }
  }
  return ids;
}

/**
 * Serialize the current done-set so we can detect regression next
 * launch. Stable ordering (matches `ONBOARDING_STEPS`) so the device
 * state blob is deterministic across runs.
 */
export function serializePreviouslyDoneState(
  progress: OnboardingProgress,
  previouslyDone: ReadonlySet<OnboardingStepId> = new Set(),
): string {
  return JSON.stringify(buildPreviouslyDoneState(progress, previouslyDone));
}
