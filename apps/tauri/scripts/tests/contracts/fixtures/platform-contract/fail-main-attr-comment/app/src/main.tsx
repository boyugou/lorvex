import { getDesktopPlatform, getMobilePlatform } from './lib/platform/platform';
import { installMainDocumentRuntime } from './main.runtime';

installMainDocumentRuntime({
  desktopPlatform: getDesktopPlatform(),
  documentTarget: document,
  mobilePlatform: getMobilePlatform(),
});
