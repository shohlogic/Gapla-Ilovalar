import { PlatformColor } from 'react-native';

// Gapla ranglari (G54, egasi 2026-11-12: [so'zlari: bilim/gapla-goyalar-royxati.md]; kompyuter ilovasi `5ef477e` bilan bir xil;
// bilim/gapla-brend-loyihasi.md). Ilova faqat kunduzgi ko'rinishda (app.base.json `userInterfaceStyle: light`).
// To'q mandarin: oq yozuv unda 5,05:1, ilova fonida (#F8F6F5) matn sifatida 4,68:1 (WCAG AA).
export const BRAND = '#BC4B1C';
// Havola matni: oq fonda 5,21:1, ilova fonida 4,83:1.
export const BRAND_LINK = '#B84A1C';
// Fokus halqasi va chegara (kompyuterdagi kursor rangi): oq fonda 3,64:1 — halqaga 3:1 yetadi, matnga ishlatilmaydi.
export const BRAND_RING = '#DE5F2A';
// Ilova belgisining foni va undagi kursor rangi (iliq grafit, yorqin mandarin): 7,98:1.
export const GAPLA_GRAPHITE = '#1C1917';
export const GAPLA_CURSOR = '#FF9447';

// To'q mandarin shisha — tugmalar, chat pufakchasi, avatar. Uchala to'xtash joyida oq yozuv kamida 4,74:1.
// Klaviaturadagi `Palette.brandGradientStart` / `brandGradientEnd` bilan bir xil (KeyboardViewController.swift).
// Rendered diagonally (top-left → bottom-right) to match that button.
export const BRAND_GRADIENT = ['#C24F1F', '#BC4B1C', '#B0451A'] as const;

// App-wide page background. Overrides iOS `systemBackground` so the warm tone
// appears uniformly across screens and components that read this token.
export const APP_BACKGROUND = '#F8F6F5';

const ANDROID_FALLBACKS: Record<string, string> = {
  label: '#000000',
  secondaryLabel: '#3C3C434D',
  tertiaryLabel: '#3C3C434D',
  quaternaryLabel: '#3C3C432E',
  systemBackground: APP_BACKGROUND,
  secondarySystemBackground: '#F2F2F7',
  secondarySystemGroupedBackground: '#FFFFFF',
  tertiarySystemFill: '#76768014',
  quaternarySystemFill: '#7676800F',
  separator: '#3C3C4349',
  link: BRAND_LINK,
  systemRed: '#FF3B30',
  systemGreen: '#34C759',
  systemBlue: BRAND,
  systemPurple: '#AF52DE',
  systemOrange: '#FF9500',
  systemIndigo: '#5856D6',
  systemPink: '#FF2D55',
  systemGray2: '#AEAEB2',
};

const IOS_LITERAL_OVERRIDES: Record<string, string> = {
  systemBackground: APP_BACKGROUND,
  secondarySystemGroupedBackground: '#FFFFFF',
  // Tizim ko'ki o'rniga Gapla mandarini (G54): `iosColor('systemBlue')` va `iosColor('link')` ham Gapla rangini beradi.
  systemBlue: BRAND,
  link: BRAND_LINK,
};

export function iosColor(name: string): string {
  if (process.env.EXPO_OS === 'ios') {
    return IOS_LITERAL_OVERRIDES[name] ?? (PlatformColor(name) as unknown as string);
  }
  return ANDROID_FALLBACKS[name] ?? '#000000';
}

// Fixed colors for the Chat tab that have no system token. Text and fills that
// do have one (label, secondaryLabel, ...) use the NativeWind token instead.
export const CHAT_COLORS = {
  darkFill: '#111113',
  hairline: 'rgba(0,0,0,0.08)',
  neutralRing: 'rgba(0,0,0,0.12)',
  neutralTrack: 'rgba(0,0,0,0.06)',
  successForeground: '#1E7A3D',
  successBackground: '#E6F3EA',
  errorForeground: '#B3261E',
  errorBackground: '#FBECEA',
  // BRAND_GRADIENT's middle stop, around the mic while it listens.
  listeningRing: 'rgba(188,75,28,0.22)',
  // Faint enough that text over it keeps its contrast.
  watermark: 'rgba(17,17,19,0.035)',
  onGradient: '#FFFFFF',
  onGradientSubtle: 'rgba(255,255,255,0.55)',
} as const;
