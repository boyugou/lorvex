import { safeLocalStorage } from './index';

export interface UIStateStorageHost {
  getStorage: () => Storage | null;
}

export function createBrowserUIStateStorageHost(): UIStateStorageHost {
  return {
    getStorage: () => safeLocalStorage(),
  };
}
