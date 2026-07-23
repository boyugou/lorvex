const BRAND = 'Lorvex';

/**
 * Build a localized page title. The em-dash separator works for `en` and
 * `zh`. If a future locale needs a different convention (e.g. RTL or
 * "View - App" ordering), branch here on the locale rather than at every
 * call site.
 *
 *
 */
export function formatPageTitle(viewName: string): string {
  return `${BRAND} — ${viewName}`;
}
