import { safeLocalStorage } from './storage';

export interface UndoTokenStorageHost {
  getStorage: () => Storage | null;
}

export function createBrowserUndoTokenStorageHost(): UndoTokenStorageHost {
  return {
    getStorage: () => safeLocalStorage(),
  };
}
