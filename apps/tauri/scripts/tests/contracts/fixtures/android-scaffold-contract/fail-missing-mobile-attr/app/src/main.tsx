import { getMobilePlatform } from './lib/platform/platform';
import { installMainDocumentRuntime } from './main.runtime';

installMainDocumentRuntime({
  documentTarget: document,
  mobilePlatform: getMobilePlatform(),
});
