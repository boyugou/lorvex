interface TauriCurrentWindowMetadataLike {
  label?: string | undefined;
}

interface TauriInternalsLike {
  metadata?: {
    currentWindow?: TauriCurrentWindowMetadataLike | undefined;
  } | undefined;
}

interface MainRuntimeWindowLike {
  __TAURI_INTERNALS__?: TauriInternalsLike | undefined;
  __lorvexVisibilityAttrInstalled?: boolean | undefined;
}

interface MainRuntimeDocumentElementLike {
  removeAttribute: (name: string) => void;
  setAttribute: (name: string, value: string) => void;
}

interface MainRuntimeDocumentLike {
  addEventListener: (type: 'visibilitychange', listener: () => void) => void;
  documentElement: MainRuntimeDocumentElementLike;
  visibilityState: string;
}

interface MainDocumentRuntimeDeps {
  desktopPlatform: string;
  documentTarget: MainRuntimeDocumentLike;
  mobilePlatform: string;
  windowTarget: MainRuntimeWindowLike;
}

interface MainDocumentRuntimeResult {
  installedVisibilityListener: boolean;
  windowKind: 'main' | 'overlay';
  windowLabel: string;
}

export function resolveCurrentWindowLabel(windowTarget: MainRuntimeWindowLike): string {
  const label = windowTarget.__TAURI_INTERNALS__?.metadata?.currentWindow?.label;
  return typeof label === 'string' && label.length > 0 ? label : 'main';
}

export function resolveWindowKind(windowLabel: string): 'main' | 'overlay' {
  return windowLabel === 'main' ? 'main' : 'overlay';
}

export function isTransparentOverlayWindow(windowLabel: string): boolean {
  return windowLabel === 'focus'
    || windowLabel === 'popover';
}

export function syncDocumentVisibilityAttr(documentTarget: MainRuntimeDocumentLike): void {
  documentTarget.documentElement.setAttribute('data-visibility', documentTarget.visibilityState);
}

export function installMainDocumentRuntime(deps: MainDocumentRuntimeDeps): MainDocumentRuntimeResult {
  const windowLabel = resolveCurrentWindowLabel(deps.windowTarget);
  const windowKind = resolveWindowKind(windowLabel);

  deps.documentTarget.documentElement.setAttribute('data-window-kind', windowKind);
  if (isTransparentOverlayWindow(windowLabel)) {
    deps.documentTarget.documentElement.setAttribute('data-window-transparent', '');
  } else {
    deps.documentTarget.documentElement.removeAttribute('data-window-transparent');
  }
  deps.documentTarget.documentElement.setAttribute('data-desktop-os', deps.desktopPlatform);
  deps.documentTarget.documentElement.setAttribute('data-mobile-os', deps.mobilePlatform);

  const syncVisibilityAttr = () => syncDocumentVisibilityAttr(deps.documentTarget);
  syncVisibilityAttr();
  if (deps.windowTarget.__lorvexVisibilityAttrInstalled) {
    return { installedVisibilityListener: false, windowKind, windowLabel };
  }

  deps.documentTarget.addEventListener('visibilitychange', syncVisibilityAttr);
  deps.windowTarget.__lorvexVisibilityAttrInstalled = true;
  return { installedVisibilityListener: true, windowKind, windowLabel };
}

declare global {
  interface Window {
    __lorvexVisibilityAttrInstalled?: boolean;
  }
}
