import type { KeyboardTone, ProcessingMode } from '@/types';

export const KEYBOARD_TONES: { value: KeyboardTone; label: string; description: string }[] = [
  { value: 'default', label: 'Standart', description: "Odatiy tozalash, ohang o'zgarmaydi" },
  { value: 'formal', label: 'Rasmiy', description: 'Ishchan va puxta' },
  { value: 'casual', label: 'Oddiy', description: 'Erkin, suhbatdagidek' },
  { value: 'very_casual', label: 'Juda oddiy', description: 'Bemalol, norasmiy' },
  { value: 'excited', label: 'Hayajonli', description: "G'ayratli va shijoatli" },
];

export const DEFAULT_KEYBOARD_TONE: KeyboardTone = 'default';

// Tone is a Cloud cleanup option: Private mode's On-Device cleanup takes none, and
// cleanup-off skips the rewrite entirely.
export function isToneApplicable(
  mode: ProcessingMode,
  cleanupEnabled: boolean | undefined,
): boolean {
  return (mode === 'cloud' || mode === 'providers') && (cleanupEnabled ?? true);
}

export function toneLabel(value: KeyboardTone): string {
  return KEYBOARD_TONES.find((tone) => tone.value === value)?.label ?? 'Standart';
}
