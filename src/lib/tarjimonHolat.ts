// Gapla (G56): keeps the translator page in place when the keyboard opens it. The app's warm-resume reset sends the
// app Home on every return from the background (app/_layout.tsx, resolveResumeAction); the translator owns its own
// navigation, so the reset skips it while its link is fresh or the page is up — as the Full Access recovery does.

// Long enough to cover launch and navigation, short enough that a link which never lands cannot pin the app.
const DEEP_LINK_FRESH_MS = 10_000;
// A translator left open and abandoned stops holding the app after this long in the background.
const BACKGROUND_STALE_MS = 10 * 60 * 1000;

let deepLinkAtMs: number | null = null;
let active = false;
let backgroundedAtMs: number | null = null;

/** The keyboard's 文A link arrived (src/hooks/useKeyboardHandoff.ts, handleUrl). */
export function markTarjimonDeepLink(): void {
  deepLinkAtMs = Date.now();
}

/** The translator page mounted (true) or closed (false). Mounting claims the link. */
export function setTarjimonActive(on: boolean): void {
  active = on;
  deepLinkAtMs = null;
  backgroundedAtMs = null;
}

export function markTarjimonBackgrounded(): void {
  if (active) backgroundedAtMs = Date.now();
}

/** True while the warm-resume reset must leave the translator on screen. */
export function isTarjimonHolding(): boolean {
  if (deepLinkAtMs !== null && Date.now() - deepLinkAtMs < DEEP_LINK_FRESH_MS) return true;
  if (!active) return false;
  return backgroundedAtMs === null || Date.now() - backgroundedAtMs < BACKGROUND_STALE_MS;
}
