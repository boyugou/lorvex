// shared allowlist for link protocols the app is willing
// to hand off to the OS opener. Everything not listed (javascript:,
// data:, vbscript:, file:, about:) must be blocked — some webviews
// still treat `javascript:` URIs as same-origin navigation in
// contexts where CSP `script-src` does not cover them, which would
// give any prompt-injected task body or synced note content
// same-origin JS execution with IPC access.

const ALLOWED_LINK_PROTOCOLS = new Set(['http:', 'https:', 'mailto:', 'tel:']);

/**
 * Returns true iff `url` parses as a valid URL and its protocol is in
 * the allowlist. Empty / malformed / relative URLs return false.
 */
export function isAllowedLinkUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  try {
    return ALLOWED_LINK_PROTOCOLS.has(new URL(url.trim()).protocol);
  } catch {
    return false;
  }
}
