import type { AppSelectProps } from './model';

import { AppSelectContent } from './AppSelectContent';
import { useAppSelectController } from './useAppSelectController';

export function AppSelect(props: AppSelectProps) {
  const controller = useAppSelectController(props);
  return <AppSelectContent {...props} controller={controller} />;
}
