export type TagAutocompleteEscapeAction = 'close-suggestions' | 'collapse-input' | 'none';

export function resolveTagAutocompleteEscapeAction({
  showDropdown,
  showInput,
}: {
  showDropdown: boolean;
  showInput: boolean;
}): TagAutocompleteEscapeAction {
  if (showDropdown) return 'close-suggestions';
  if (showInput) return 'collapse-input';
  return 'none';
}
