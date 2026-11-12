import type { CalendarParticipant } from '@/data/calendarTypes';
import { getHumanParticipants } from '@/lib/calendar/meetingContext';
import { formatClockTime, UZ_MONTHS } from '@/lib/formatNoteRowTime';
import { tryParseNoteTimestamp } from '@/lib/parseNoteTimestamp';

// The default folders are seeded with English names, and sync matches them by name, so the stored
// name stays and only the label the user sees is Uzbek.
const DEFAULT_FOLDER_LABELS: Record<string, string> = {
  personal: 'Shaxsiy',
  meetings: 'Uchrashuvlar',
  videos: 'Videolar',
};

/** The folder name to show: a default folder's label in Uzbek, any other folder as named. */
export function folderDisplayName(folder: { name: string; isDefault?: number | null }): string {
  return (folder.isDefault && DEFAULT_FOLDER_LABELS[folder.name.trim().toLowerCase()]) || folder.name;
}

// The built-in action is seeded in English too (src/db/migrate.ts), so only what the user sees is
// Uzbek: its name, and a short summary in place of its English prompt. Same words as Windows.
const BUILT_IN_ACTION_LABELS: Record<string, { name: string; summary: string }> = {
  'generate notes': {
    name: 'AI xulosa',
    summary: 'Qaydlaringizni tozalaydi, tartibga soladi va yaxshilaydi',
  },
  'clean up notes': {
    name: 'AI xulosa',
    summary: 'Qaydlaringizni tozalaydi, tartibga soladi va yaxshilaydi',
  },
};

const builtInActionLabel = (action: { name: string; isDefault?: number | null }) =>
  action.isDefault === 1 ? BUILT_IN_ACTION_LABELS[action.name.trim().toLowerCase()] : undefined;

/** The action name to show: the built-in action in Uzbek, a user's own action as named. */
export function actionDisplayName(action: { name: string; isDefault?: number | null }): string {
  return builtInActionLabel(action)?.name ?? action.name;
}

/** The line under an action's name: the built-in action's summary, otherwise its prompt. */
export function actionDisplaySummary(action: {
  name: string;
  prompt: string;
  isDefault?: number | null;
}): string {
  return builtInActionLabel(action)?.summary ?? action.prompt;
}

export const isSameDay = (a: Date, b: Date): boolean =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();

/**
 * When the note was taken. Notes pulled before `created_at` synced were stamped with the pull
 * time, which is later than their last edit on the server, so the earlier of the two is the
 * closer answer. Pass the server's last edit: a local edit would move the date to the pull time.
 */
export function noteTakenAt(
  createdAt: string | null | undefined,
  lastEditedAt: string | null | undefined,
): Date | null {
  const created = tryParseNoteTimestamp(createdAt);
  const lastEdited = tryParseNoteTimestamp(lastEditedAt);
  if (!created || !lastEdited) return created ?? lastEdited;
  return created < lastEdited ? created : lastEdited;
}

/**
 * "Bugun 09:27", "Kecha 14:05", "21-sentabr, 09:27", or "2025-yil 21-sentabr, 09:27", with the
 * time shown as the notes list shows it.
 */
export function formatNoteMetaDate(timestamp: string | Date | null | undefined, now: Date): string {
  const date = tryParseNoteTimestamp(timestamp);
  if (!date) return '';

  const time = formatClockTime(date);
  if (isSameDay(date, now)) return `Bugun ${time}`;

  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (isSameDay(date, yesterday)) return `Kecha ${time}`;

  const day = `${date.getDate()}-${UZ_MONTHS[date.getMonth()]}`;
  return date.getFullYear() === now.getFullYear()
    ? `${day}, ${time}`
    : `${date.getFullYear()}-yil ${day}, ${time}`;
}

/**
 * People who haven't declined, without rooms (flagged, or known by their address or name) or
 * repeats, organizer first, otherwise in calendar order.
 */
export function sortAttendees(participants: CalendarParticipant[]): CalendarParticipant[] {
  const people = getHumanParticipants(participants);
  return [
    ...people.filter((participant) => participant.organizer),
    ...people.filter((participant) => !participant.organizer),
  ];
}

/**
 * `self` comes from the calendar of whoever created the note, so on a teammate's note it marks
 * them. There, you are whoever has your address.
 */
export function markViewer(
  participants: CalendarParticipant[],
  { creatorIsViewer, viewerEmail }: { creatorIsViewer: boolean; viewerEmail: string | null },
): CalendarParticipant[] {
  if (creatorIsViewer) return participants;
  const email = viewerEmail?.toLowerCase();
  return participants.map((participant) => ({
    ...participant,
    self: !!email && participant.email?.toLowerCase() === email,
  }));
}

export function attendeeName(participant: CalendarParticipant): string {
  if (participant.self) return 'Siz';
  return participant.displayName?.trim() || participant.email || 'Mehmon';
}

const attendeeFirstName = (participant: CalendarParticipant): string =>
  participant.displayName?.trim().split(/\s+/)[0] || participant.email?.split('@')[0] || 'Mehmon';

/** "Sam +3": the first attendee who isn't you, plus everyone else. Null when nobody attends. */
export function formatAttendeeChipLabel(participants: CalendarParticipant[]): string | null {
  const people = sortAttendees(participants);
  if (people.length === 0) return null;

  const first = people.find((participant) => !participant.self);
  if (!first) return 'Siz';

  const others = people.length - 1;
  const name = attendeeFirstName(first);
  return others > 0 ? `${name} +${others}` : name;
}
