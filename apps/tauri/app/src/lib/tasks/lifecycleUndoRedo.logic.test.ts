import { describe, expect, it } from 'vitest';

import type { TranslationKey } from '../i18n';
import { buildLifecycleRedoToastAction } from './lifecycleUndoRedo.logic';

const t = (key: TranslationKey) => key;

describe('buildLifecycleRedoToastAction', () => {
  it('suppresses redo affordance when backend returns no redo token', () => {
    expect(buildLifecycleRedoToastAction(null, t)).toBeNull();
    expect(buildLifecycleRedoToastAction(undefined, t)).toBeNull();
    expect(buildLifecycleRedoToastAction('', t)).toBeNull();
  });

  it('builds redo action for concrete redo tokens', () => {
    expect(buildLifecycleRedoToastAction('redo-token', t)).toEqual({
      token: 'redo-token',
      label: 'common.redo',
    });
  });
});
