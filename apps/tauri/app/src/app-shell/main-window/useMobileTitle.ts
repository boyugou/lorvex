import { useI18n } from '@/lib/i18n';
import type { View } from '@/lib/types';

import type { ListsData } from './types';
import { resolveMobileTitleKey } from './useMobileTitle.logic';

export function useMobileTitle(view: View, lists: ListsData, mobileListId: string | null): string {
  const { t } = useI18n();

  if (view.type === 'list') {
    const currentMobileList = lists.find((list) => list.id === mobileListId) ?? null;
    return currentMobileList?.name ?? t('nav.lists');
  }

  return t(resolveMobileTitleKey(view.type));
}
