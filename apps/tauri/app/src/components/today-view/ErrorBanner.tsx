import type { TranslationKey } from '@/lib/i18n';
import { Banner } from '@/components/ui/Banner';
import { TonalButton } from '@/components/ui/TonalButton';

interface ErrorBannerProps {
  t: (key: TranslationKey) => string;
  onRetry: () => void;
}

export function ErrorBanner({ t, onRetry }: ErrorBannerProps): React.JSX.Element {
  return (
    <Banner
      tone="warning"
      actions={
        // retry action uses the warning-tone `<TonalButton>` so it
        // matches the surrounding banner shell instead of the prior neutral
        // surface-3 outlined button (which fought the warning tonal cue).
        <TonalButton tone="warning" size="md" onClick={onRetry}>
          {t('error.tryAgain')}
        </TonalButton>
      }
    >
      {t('today.loadFailedHint')}
    </Banner>
  );
}
