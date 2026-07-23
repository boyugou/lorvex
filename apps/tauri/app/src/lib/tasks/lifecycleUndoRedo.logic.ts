import type { TranslationKey } from '../i18n';
import {
  makeRecentUndoToken,
  type RecentUndoAction,
  type RecentUndoToken,
} from '../undoTokenStore';

type Translator = (key: TranslationKey) => string;

interface LifecycleUndoRedoPersistenceOptions {
  label: string;
  action: RecentUndoAction;
}

interface LifecycleToastActionPlan {
  token: string;
  label: string;
}

interface LifecycleUndoToastPlan {
  action: LifecycleToastActionPlan | null;
  persistedEntry: RecentUndoToken | null;
}

export function hasLifecycleToken(token: string | null | undefined): token is string {
  return typeof token === 'string' && token.length > 0;
}

export function buildLifecycleUndoToastPlan(
  token: string,
  t: Translator,
  persist?: LifecycleUndoRedoPersistenceOptions,
): LifecycleUndoToastPlan {
  if (!hasLifecycleToken(token)) {
    return {
      action: null,
      persistedEntry: null,
    };
  }
  return {
    action: {
      token,
      label: t('common.undo'),
    },
    persistedEntry: persist ? makeRecentUndoToken(token, persist.label, persist.action) : null,
  };
}

export function buildLifecycleRedoToastAction(
  token: string | null | undefined,
  t: Translator,
): LifecycleToastActionPlan | null {
  if (!hasLifecycleToken(token)) {
    return null;
  }
  return {
    token,
    label: t('common.redo'),
  };
}
