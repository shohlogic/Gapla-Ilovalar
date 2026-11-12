import { DEFAULT_MEETING_TITLE } from './meetingConstants';

// Every title a note can be born with, across platforms: mobile's own defaults
// plus the placeholders desktop stamps (see its regenerableNoteTitle.js).
// The English ones stay so notes created before the Uzbek interface (and on desktop) still match.
const PLACEHOLDER_TITLES = new Set(
  [
    'Untitled',
    'Untitled meeting',
    DEFAULT_MEETING_TITLE,
    'Untitled note',
    'New note',
    'Nomsiz',
    'Nomsiz qayd',
    'Yangi qayd',
  ].map((title) => title.toLowerCase()),
);

/**
 * Whether a generated title may replace this one: only while the note is still
 * unnamed or carries a placeholder default, never after the user typed their own.
 */
export function isRegenerableNoteTitle(title: string | null | undefined): boolean {
  const trimmed = title?.trim() ?? '';
  return trimmed === '' || PLACEHOLDER_TITLES.has(trimmed.toLowerCase());
}
