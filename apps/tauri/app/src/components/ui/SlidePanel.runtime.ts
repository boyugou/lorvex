type SlidePanelKeydownTarget = Pick<Document, 'addEventListener' | 'removeEventListener'>;
type SlidePanelBrowserDocumentTarget = SlidePanelKeydownTarget & Pick<Document, 'activeElement'>;

interface SlidePanelTabTrapRuntimeDeps<Panel, ActiveElement> {
  documentTarget?: SlidePanelKeydownTarget | undefined;
  getPanel: () => Panel | null;
  getActiveElement: () => ActiveElement | null;
  isActiveInsidePanel: (panel: Panel, activeElement: ActiveElement) => boolean;
  trapTabFocus: (panel: Panel, event: KeyboardEvent) => void;
}

export function shouldTrapSlidePanelTabKey<Panel, ActiveElement>({
  key,
  panel,
  activeElement,
  isActiveInsidePanel,
}: {
  key: string;
  panel: Panel | null;
  activeElement: ActiveElement | null;
  isActiveInsidePanel: (panel: Panel, activeElement: ActiveElement) => boolean;
}): boolean {
  return key === 'Tab'
    && panel !== null
    && activeElement !== null
    && isActiveInsidePanel(panel, activeElement);
}

export function installSlidePanelTabTrapRuntime<Panel, ActiveElement>({
  documentTarget,
  getPanel,
  getActiveElement,
  isActiveInsidePanel,
  trapTabFocus,
}: SlidePanelTabTrapRuntimeDeps<Panel, ActiveElement>): () => void {
  if (!documentTarget) return () => {};

  const handleKeyDown = (event: KeyboardEvent) => {
    const panel = getPanel();
    const activeElement = getActiveElement();
    if (!shouldTrapSlidePanelTabKey({
      key: event.key,
      panel,
      activeElement,
      isActiveInsidePanel,
    })) {
      return;
    }
    if (panel === null) return;

    trapTabFocus(panel, event);
  };

  documentTarget.addEventListener('keydown', handleKeyDown);
  return () => documentTarget.removeEventListener('keydown', handleKeyDown);
}

interface BrowserSlidePanelTabTrapRuntimeDeps {
  documentTarget?: SlidePanelBrowserDocumentTarget | undefined;
  getPanel: () => HTMLElement | null;
  nodeConstructor?: typeof Node | undefined;
  trapTabFocus: (panel: HTMLElement, event: KeyboardEvent) => void;
}

export function createBrowserSlidePanelTabTrapRuntimeDeps({
  documentTarget = typeof document === 'undefined' ? undefined : document,
  getPanel,
  nodeConstructor = typeof Node === 'undefined' ? undefined : Node,
  trapTabFocus,
}: BrowserSlidePanelTabTrapRuntimeDeps): SlidePanelTabTrapRuntimeDeps<HTMLElement, Element> {
  return {
    documentTarget,
    getPanel,
    getActiveElement: () => (
      documentTarget !== undefined && nodeConstructor !== undefined
        ? documentTarget.activeElement
        : null
    ),
    isActiveInsidePanel: (panel, activeElement) => (
      documentTarget !== undefined
      && nodeConstructor !== undefined
      && activeElement instanceof nodeConstructor
      && panel.contains(activeElement)
    ),
    trapTabFocus,
  };
}
