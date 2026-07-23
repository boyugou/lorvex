export function readBrowserLocale(): string {
  try {
    const language = globalThis.navigator?.language;
    return typeof language === 'string' && language.trim() !== ''
      ? language
      : 'en-US';
  } catch {
    return 'en-US';
  }
}
