type ActiveElementDocumentLike = Pick<Document, 'activeElement'>;

export function readActiveHTMLElement(
  documentLike: ActiveElementDocumentLike | undefined = typeof document === 'undefined' ? undefined : document,
  elementConstructor: typeof HTMLElement | undefined = typeof HTMLElement === 'undefined' ? undefined : HTMLElement,
): HTMLElement | null {
  if (!documentLike || !elementConstructor) return null;
  const activeElement = documentLike.activeElement;
  return activeElement instanceof elementConstructor ? activeElement : null;
}
