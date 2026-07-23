import {
  buildRuntimeProfile,
  detectDesktopPlatform,
  detectMobilePlatform,
  type DesktopPlatform,
  type MobilePlatform,
  type RuntimeProfile,
} from './platform.logic';

export type { DesktopPlatform, MobilePlatform, RuntimeProfile } from './platform.logic';

export function getDesktopPlatform(): DesktopPlatform {
  return detectDesktopPlatform(null);
}

export function getMobilePlatform(): MobilePlatform {
  return detectMobilePlatform(null);
}

export function getRuntimeProfile(): RuntimeProfile {
  return buildRuntimeProfile('macos');
}
