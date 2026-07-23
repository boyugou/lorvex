import {
  createBrowserPortalDropdownDismissRuntimeDeps,
  startPortalDropdownDismissRuntime,
} from '../portalDropdown.runtime';

type ListenerTarget = Pick<Document, 'addEventListener' | 'removeEventListener' | 'body'>;
type WindowTarget = Pick<Window, 'addEventListener' | 'removeEventListener' | 'innerWidth' | 'innerHeight'>;
type PortalTarget = Element | DocumentFragment;

interface AppSelectViewport {
  width: number;
  height: number;
}

interface AppSelectDismissRuntimeArgs {
  getTrigger: () => HTMLElement | null;
  getPanel: () => HTMLElement | null;
  onDismiss: () => void;
}

interface AppSelectRuntimeDeps {
  containsTarget: (container: HTMLElement | null, target: EventTarget | null) => boolean;
  readPortalTarget: () => PortalTarget | null;
  readViewport: () => AppSelectViewport | null;
  startDismissRuntime: (args: AppSelectDismissRuntimeArgs) => () => void;
}

interface BrowserAppSelectRuntimeDepsOptions {
  documentTarget?: ListenerTarget | undefined;
  nodeConstructor?: typeof Node | undefined;
  windowTarget?: WindowTarget | undefined;
}

export function createBrowserAppSelectRuntimeDeps({
  documentTarget = typeof document === 'undefined' ? undefined : document,
  nodeConstructor = typeof Node === 'undefined' ? undefined : Node,
  windowTarget = typeof window === 'undefined' ? undefined : window,
}: BrowserAppSelectRuntimeDepsOptions = {}): AppSelectRuntimeDeps {
  return {
    containsTarget: (container, target) => (
      nodeConstructor !== undefined
      && target instanceof nodeConstructor
      && Boolean(container?.contains(target))
    ),
    readPortalTarget: () => documentTarget?.body ?? null,
    readViewport: () => (
      windowTarget === undefined
        ? null
        : {
            width: windowTarget.innerWidth,
            height: windowTarget.innerHeight,
          }
    ),
    startDismissRuntime: ({ getTrigger, getPanel, onDismiss }) => startPortalDropdownDismissRuntime(
      createBrowserPortalDropdownDismissRuntimeDeps({
        documentTarget,
        windowTarget: documentTarget === undefined ? undefined : windowTarget,
        getTrigger,
        getPanel,
        nodeConstructor,
        onDismiss,
      }),
    ),
  };
}
