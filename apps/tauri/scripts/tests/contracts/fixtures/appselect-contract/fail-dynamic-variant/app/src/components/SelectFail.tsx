import { AppSelect } from '../../../ui/AppSelect';

export function SelectFail({ mode }: { mode: string }) {
  // <AppSelect variant="default" />
  return <AppSelect value="general" onChange={() => {}} options={[]} variant={mode} />;
}
