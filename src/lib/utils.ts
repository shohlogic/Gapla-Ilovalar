import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';
import * as Haptics from 'expo-haptics';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function getErrorMessage(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

// Gapla: Uzbek names are written by hand; Hermes may have no `uz` Intl data.
const UZ_MONTHS = [
  'yanvar',
  'fevral',
  'mart',
  'aprel',
  'may',
  'iyun',
  'iyul',
  'avgust',
  'sentabr',
  'oktabr',
  'noyabr',
  'dekabr',
];
const UZ_WEEKDAYS = ['Yakshanba', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba'];

function uzDayMonth(date: Date): string {
  return `${date.getDate()}-${UZ_MONTHS[date.getMonth()]}`;
}

function uzTime(date: Date): string {
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

export function formatRelativeTime(
  timestamp: number | string,
  mode: 'short' | 'long' = 'long',
): string {
  const date =
    typeof timestamp === 'string'
      ? new Date(timestamp.endsWith('Z') ? timestamp : timestamp + 'Z')
      : new Date(timestamp);
  if (isNaN(date.getTime())) return '';

  if (mode === 'short') {
    const days = Math.floor((Date.now() - date.getTime()) / 86_400_000);
    if (days === 0) return uzTime(date);
    if (days === 1) return 'Kecha';
    if (days < 7) return UZ_WEEKDAYS[date.getDay()];
    return uzDayMonth(date);
  }

  const minutes = Math.floor((Date.now() - date.getTime()) / 60_000);
  if (minutes < 1) return 'Hozirgina';
  if (minutes < 60) return `${minutes} daqiqa oldin`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} soat oldin`;
  const days = Math.floor(hours / 24);
  if (days === 1) return 'Kecha';
  if (days < 7) return `${days} kun oldin`;
  return uzDayMonth(date);
}

type HapticType = 'light' | 'medium' | 'heavy' | 'selection' | 'success' | 'warning' | 'error';

export function safeHaptics(type: HapticType): void {
  try {
    switch (type) {
      case 'light':
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        return;
      case 'medium':
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
        return;
      case 'heavy':
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
        return;
      case 'selection':
        Haptics.selectionAsync();
        return;
      case 'success':
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        return;
      case 'warning':
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
        return;
      case 'error':
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
        return;
    }
  } catch {}
}

export function formatLargeNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function makeContentHash(content: string): string {
  return String(content.length) + '-' + content.slice(0, 50);
}
