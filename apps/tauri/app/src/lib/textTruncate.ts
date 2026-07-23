export function truncateGraphemes(
  input: string,
  maxChars: number,
  appendEllipsis: boolean = true,
): string {
  if (maxChars <= 0) return '';
  // Intl.Segmenter is ES2022 but shipped in Safari 14.1+, all Chromium,
  // and Firefox 125+. Every Tauri webview on macOS/Windows/Linux we
  // ship on supports it. Optional-chain the constructor so the code is
  // still defensive in exotic test environments.
  try {
    if (typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function') {
      const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
      const segments: string[] = [];
      for (const { segment } of segmenter.segment(input)) {
        segments.push(segment);
        if (segments.length > maxChars) break;
      }
      if (segments.length <= maxChars) return input;
      return segments.slice(0, maxChars).join('') + (appendEllipsis ? '…' : '');
    }
  } catch {
    // fall through to codepoint slice
  }
  const codepoints = Array.from(input);
  if (codepoints.length <= maxChars) return input;
  return codepoints.slice(0, maxChars).join('') + (appendEllipsis ? '…' : '');
}
