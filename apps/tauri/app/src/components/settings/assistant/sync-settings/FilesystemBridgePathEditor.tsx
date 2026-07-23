import { useId } from 'react';

import { useI18n } from '@/lib/i18n';

interface FilesystemBridgePathEditorProps {
  rootPath: string;
  defaultFilesystemBridgeRootPath: string;
  onFilesystemBridgeRootPathChange: (value: string) => void;
  onUseDefaultFilesystemBridgeRootPath: () => void;
}

export function FilesystemBridgePathEditor({
  rootPath,
  defaultFilesystemBridgeRootPath,
  onFilesystemBridgeRootPathChange,
  onUseDefaultFilesystemBridgeRootPath,
}: FilesystemBridgePathEditorProps) {
  const { t } = useI18n();
  const filesystemRootPathInputId = useId();

  return (
    <div className="space-y-1.5">
      <label
        className="text-xs text-text-secondary font-medium"
        htmlFor={filesystemRootPathInputId}
      >
        {t('settings.syncSharedFolderPath')}
      </label>
      <input
        id={filesystemRootPathInputId}
        value={rootPath}
        onChange={(event) => onFilesystemBridgeRootPathChange(event.target.value)}
        className="w-full bg-surface-1 text-text-primary text-xs px-2.5 py-1.5 rounded-r-control border border-surface-3 outline-hidden focus-ring-soft"
        placeholder={t('settings.syncSharedFolderPathPlaceholder')}
      />
      {defaultFilesystemBridgeRootPath && rootPath !== defaultFilesystemBridgeRootPath && (
        <button
          type="button"
          onClick={onUseDefaultFilesystemBridgeRootPath}
          className="text-xs text-accent hover:text-accent/80 rounded-r-control focus-ring-soft"
        >
          {t('settings.syncUseDefaultPath')}
        </button>
      )}
    </div>
  );
}
