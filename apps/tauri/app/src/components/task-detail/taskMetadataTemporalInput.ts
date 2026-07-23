function isValidTimeInputValue(value: string): boolean {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

function resolveOptionalTemporalInputBlurValue(
  storedValue: string | null,
  inputValue: string,
): string | null | undefined {
  const nextValue = inputValue === '' ? null : inputValue;
  if (nextValue === storedValue) return undefined;
  return nextValue;
}

export function getOptionalTimeInputValue(value: string | null): string {
  if (value === null) return '';
  return isValidTimeInputValue(value) ? value : '';
}

export function resolveOptionalTimeInputBlurValue(
  storedValue: string | null,
  inputValue: string,
): string | null | undefined {
  return resolveOptionalTemporalInputBlurValue(storedValue, inputValue);
}
