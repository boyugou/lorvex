import { expect, test } from '@playwright/test';
import { installTauriMock } from './support/tauriMock';

// Regression test for the offline reassurance banner on WelcomeView.
// The app can reopen the same WelcomeView through Help, which gives the
// e2e a stable surface without coupling it to Today empty-state layout.

async function forceOffline(page: import('@playwright/test').Page): Promise<void> {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'onLine', {
      configurable: true,
      get: () => false,
    });
  });
}

async function openWelcomeTour(page: import('@playwright/test').Page): Promise<void> {
  await page.getByRole('button', { name: 'Help & shortcuts' }).click();
  await page.getByRole('button', { name: /Revisit the Welcome tour/ }).click();
  await expect(page.getByRole('dialog', { name: 'Welcome to Lorvex' })).toBeVisible();
}

test.describe('welcome view offline banner (#2443)', () => {
  test('renders the offline banner when navigator.onLine is false', async ({ page }) => {
    await installTauriMock(page, 'en');
    await forceOffline(page);
    await page.goto('/');
    await openWelcomeTour(page);

    await expect(page.getByText('Welcome to Lorvex')).toBeVisible({ timeout: 5000 });

    const banner = page.getByTestId('welcome-offline-banner');
    await expect(banner).toBeVisible();
    await expect(banner).toContainText('offline');
    await expect(banner).toContainText('sync is optional');

    await expect(page.getByTestId('welcome-offline-learn-more')).toBeVisible();
  });

  test('does not render the offline banner when the browser reports online', async ({ page }) => {
    await installTauriMock(page, 'en');
    await page.goto('/');
    await openWelcomeTour(page);

    await expect(page.getByText('Welcome to Lorvex')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('welcome-offline-banner')).toHaveCount(0);
    await expect(page.getByTestId('welcome-offline-learn-more')).toHaveCount(0);
  });
});
