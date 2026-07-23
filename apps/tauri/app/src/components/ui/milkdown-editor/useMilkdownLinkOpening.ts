import { useEffect, type RefObject } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';

import { reportClientError } from '@/lib/errors/errorLogging';
import { isAllowedLinkUrl } from '@/lib/security/urlSafety';

export function useMilkdownLinkOpening(wrapperRef: RefObject<HTMLDivElement | null>) {
  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const onClick = (e: MouseEvent) => {
      const target = e.target;
      if (!(target instanceof Element)) return;
      const anchor = target.closest('a');
      if (!anchor) return;
      e.preventDefault();
      e.stopPropagation();
      const href = anchor.getAttribute('href');
      if (isAllowedLinkUrl(href)) {
        void openUrl(href!).catch((error) => {
          reportClientError('milkdown.openUrl', 'Failed to open link from Markdown editor', error, `href=${href}`);
        });
      }
    };
    el.addEventListener('click', onClick);
    return () => el.removeEventListener('click', onClick);
  }, [wrapperRef]);
}
