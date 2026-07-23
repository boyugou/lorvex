import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { TranslationKey } from '@/locales';

type Translator = (key: TranslationKey) => string;

export function syncBackendLabel(_backendKind: SyncBackendKind, t: Translator): string {
  return t('settings.syncMethodSharedFolder');
}

export function syncBackendDescription(_backendKind: SyncBackendKind, t: Translator): string {
  return t('settings.syncMethodSharedFolderDesc');
}
