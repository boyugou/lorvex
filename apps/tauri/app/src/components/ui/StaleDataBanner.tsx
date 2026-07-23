import type { TranslationKey } from '@/lib/i18n';
import { Banner } from '@/components/ui/Banner';
import { Button } from '@/components/ui/Button';

interface StaleDataBannerProps {
  t: (key: TranslationKey) => string;
  onRetry: () => void;
  hintKey?: TranslationKey;
}

export function StaleDataBanner({ t, onRetry, hintKey = 'today.loadFailedHint' }: StaleDataBannerProps) {
  return (
    <Banner
      tone="warning"
      className="mb-3"
      actions={
        <Button variant="outline" onClick={onRetry}>
          {t('error.tryAgain')}
        </Button>
      }
    >
      {t(hintKey)}
    </Banner>
  );
}
