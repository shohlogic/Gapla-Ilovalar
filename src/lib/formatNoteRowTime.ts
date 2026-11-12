import type { DateBucketKey } from './groupNotesByDate';
import { parseNoteTimestamp } from './parseNoteTimestamp';

const WEEKDAYS = [
  'Yakshanba',
  'Dushanba',
  'Seshanba',
  'Chorshanba',
  'Payshanba',
  'Juma',
  'Shanba',
];

/** Month names as they read inside a sentence: "21-sentabr". Hermes has no `uz` locale data. */
export const UZ_MONTHS = [
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

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/** "14:05", the clock time the notes list shows. */
export function formatClockTime(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

export function formatNoteRowTime(
  updatedAt: string | number | Date | null | undefined,
  bucket: DateBucketKey,
): string {
  const d = parseNoteTimestamp(updatedAt);
  if (isNaN(d.getTime())) return '';

  if (bucket === 'today') {
    return formatClockTime(d);
  }
  if (bucket === 'yesterday') {
    return 'Kecha';
  }
  if (bucket === 'prev7') {
    return WEEKDAYS[d.getDay()];
  }
  // "21.09.2025", the Uzbek numeric date, whatever the device locale.
  return `${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${d.getFullYear()}`;
}
