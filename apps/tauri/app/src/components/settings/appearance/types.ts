export type ThemePreviewPalette = {
  canvas: string;
  panel: string;
  accent: string;
  text: string;
};

export type ThemePreviewMap = Record<Exclude<import('@/lib/theme').ThemeMode, 'system'>, ThemePreviewPalette>;
