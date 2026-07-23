interface ScrollRestoreController {
  getLastRestoredKey: () => string | null;
  remember: (key: string, scrollTop: number) => void;
  restore: (key: string, element: { scrollTop: number } | null) => void;
}

export interface ScrollPositionStore {
  get: (key: string) => number | undefined;
  set: (key: string, scrollTop: number) => void;
}

const scrollPositions = new Map<string, number>();

const defaultStore: ScrollPositionStore = {
  get: (key) => scrollPositions.get(key),
  set: (key, scrollTop) => {
    scrollPositions.set(key, scrollTop);
  },
};

export function createScrollRestoreController(
  store: ScrollPositionStore = defaultStore,
): ScrollRestoreController {
  let lastRestoredKey: string | null = null;

  return {
    restore: (key, element) => {
      if (!element || lastRestoredKey === key) return;
      const saved = store.get(key);
      if (saved != null && saved > 0) {
        element.scrollTop = saved;
      }
      lastRestoredKey = key;
    },
    remember: (key, scrollTop) => {
      store.set(key, scrollTop);
    },
    getLastRestoredKey: () => lastRestoredKey,
  };
}
