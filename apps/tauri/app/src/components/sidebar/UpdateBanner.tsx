import { useEffect, useRef, useState } from 'react';

import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { TranslationKey } from '@/lib/i18n';
import { installUpdate } from '@/lib/ipc/runtime';
import { toast } from '@/lib/notifications/toast';

import { TonalButton } from '../ui/TonalButton';
import { Tooltip } from '../ui/Tooltip';

interface UpdateBannerProps {
  availableVersion: string;
  onOpenReleaseNotes: () => void;
  t: (key: TranslationKey) => string;
}

/**
 * sidebar update banner. The release-notes link explains what
 * changed; the new "Install" affordance closes the loop by actually
 * applying the update without making the user hunt for an installer.
 *
 * The two affordances sit on a single row: the release-notes link gets
 * the wide left side (label + version), and the "Install" button sits
 * tight on the right with its own focus ring + accent fill so the call
 * to action is obviously distinct from the read-more.
 *
 * `installUpdate` is plumbed through an `AbortController` whose
 * lifetime is tied to the component mount: the effect's cleanup aborts
 * any in-flight call so a banner unmount mid-install does not strand a
 * pending IPC promise that resolves into a toast against an unmounted
 * tree.
 */
export default function UpdateBanner({ availableVersion, onOpenReleaseNotes, t }: UpdateBannerProps) {
  const label = `${t('sidebar.updateTitle')} v${availableVersion}`;
  const [installing, setInstalling] = useState(false);
  const installAbortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    return () => {
      installAbortRef.current?.abort();
    };
  }, []);

  const handleInstall = async () => {
    if (installing) return;
    const ok = await confirm({
      title: t('sidebar.updateInstallConfirmTitle'),
      message: t('sidebar.updateInstallConfirmMessage'),
      confirmLabel: t('sidebar.updateInstallConfirmCta'),
      variant: 'default',
    });
    if (!ok) return;
    setInstalling(true);
    // The successful path replaces the running process before the IPC
    // reply lands. Inform the user we're working in case the
    // download takes long enough that they wonder if anything happened.
    toast.info(t('sidebar.updateInstalling'));
    const ctrl = new AbortController();
    installAbortRef.current = ctrl;
    try {
      await installUpdate(ctrl.signal);
      if (!ctrl.signal.aborted) setInstalling(false);
    } catch (error) {
      if (ctrl.signal.aborted) return;
      reportClientError('sidebar.installUpdate', 'Failed to install app update', error);
      toast.errorWithDetail(error, t('sidebar.updateInstallFailed'));
      setInstalling(false);
    }
  };

  return (
    <div className="px-2 mb-2 flex items-center gap-1.5">
      <Tooltip label={label}>
        <button
          type="button"
          onClick={onOpenReleaseNotes}
          className="flex-1 min-w-0 flex items-center gap-2 px-2 py-1.5 rounded-r-control text-xs text-accent hover:bg-[var(--accent-tint-xs)] active:scale-[0.97] transition-colors text-start focus-ring-soft"
          aria-label={label}
        >
          <span className="h-2 w-2 rounded-full bg-accent shrink-0" />
          <span className="truncate">
            {`${t('sidebar.updateAvailable')} v${availableVersion}`}
          </span>
        </button>
      </Tooltip>
      <TonalButton
        tone="accent"
        onClick={handleInstall}
        disabled={installing}
        aria-label={t('sidebar.updateInstallConfirmCta')}
        className="shrink-0 active:scale-[0.97]"
      >
        {installing ? t('sidebar.updateInstalling') : t('sidebar.updateInstall')}
      </TonalButton>
    </div>
  );
}
