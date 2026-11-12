// Written out rather than read from Intl, which Hermes may lack Uzbek data for.
const WEEKDAYS = ['Yakshanba', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba'];
const MONTHS = [
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
const DAY_MS = 86_400_000;

const startOfDay = (date: Date): number =>
  new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();

export function formatConversationTime(timestamp: number, now: Date = new Date()): string {
  const date = new Date(timestamp);
  // Compare calendar days, not 24 h spans, so 11 pm yesterday still reads "Kecha".
  const daysAgo = Math.round((startOfDay(now) - startOfDay(date)) / DAY_MS);

  // A 24-hour clock, as Uzbekistan reads the time: "09:05", "15:30".
  if (daysAgo <= 0) {
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${hours}:${minutes}`;
  }
  if (daysAgo === 1) return 'Kecha';
  if (daysAgo <= 6) return WEEKDAYS[date.getDay()];
  // "12-noyabr", and "2025-yil 12-noyabr" for another year.
  const day = `${date.getDate()}-${MONTHS[date.getMonth()]}`;
  return date.getFullYear() === now.getFullYear() ? day : `${date.getFullYear()}-yil ${day}`;
}
