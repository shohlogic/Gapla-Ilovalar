import * as Network from 'expo-network';
import { notesRepository, type Note } from '@/data';
import { useAuthStore } from '@/store/useAuthStore';
import { useConfigStore } from '@/store/useConfigStore';
import { useNotesStore } from '@/store/useNotesStore';
import { isFolderAwaitingUpload } from '@/lib/notes/folderUpload';
import { createPushScopeResolver, createTeamSpaceFilter } from './pushScope';
import { requestSync, subscribeSyncCompletion } from './syncEngine';
import { useSyncStore } from './useSyncStore';

export const NOTE_UNAVAILABLE_ERROR = 'Bu qayd endi mavjud emas.';
export const NOTE_PRIVATE_ERROR = 'Ulashishdan oldin bu qayd uchun sinxronlashni yoqing.';

function readPublishableNote(noteId: number): Note {
  const note = notesRepository.getNoteById(noteId);
  if (
    !note ||
    note.deletedAt ||
    notesRepository.isRemoteNoteHeldByFolderDelete({
      id: note.remoteId ?? '',
      client_note_id: note.clientNoteId,
    })
  )
    throw new Error(NOTE_UNAVAILABLE_ERROR);
  if (note.isPrivate === 1) throw new Error(NOTE_PRIVATE_ERROR);
  if (note.conflictServerNote) throw new Error('Ulashishdan oldin qayddagi sinxronlash ziddiyatini hal qiling.');
  return note;
}

/** Wait for the existing sync pipeline to acknowledge this note's latest edits. */
export async function ensureNoteSynced(
  noteId: number,
  { signal, timeoutMs = 30_000 }: { signal: AbortSignal; timeoutMs?: number },
): Promise<string> {
  const auth = useAuthStore.getState();
  if (!auth.user || auth.user.isAnonymous || auth.isGuest || auth.isLoading) {
    throw new Error('Ulashishdan oldin hisobingizga kiring.');
  }
  if (signal.aborted) throw new Error('Ulashish bekor qilindi.');
  const original = readPublishableNote(noteId);
  const isTeamNote = createTeamSpaceFilter()(original.spaceId);

  return new Promise<string>((resolve, reject) => {
    let settled = false;
    let completedPass = false;
    let passes = 0;
    let offline = false;
    const unsubscribe: Array<() => void> = [];
    const finish = (value: string | Error): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal.removeEventListener('abort', cancel);
      unsubscribe.forEach((stop) => stop());
      if (value instanceof Error) reject(value);
      else resolve(value);
    };
    const cancel = (): void => finish(new Error('Ulashish bekor qilindi.'));
    const timer = setTimeout(
      () =>
        finish(
          new Error("Qayd hali sinxronlanib bo'lmadi. Internetni tekshirib, qayta urinib ko'ring."),
        ),
      timeoutMs,
    );
    const inspect = (): void => {
      try {
        const current = useAuthStore.getState();
        if (
          current.user?.id !== auth.user?.id ||
          current.sessionCookie !== auth.sessionCookie ||
          current.isLoading ||
          current.isGuest
        )
          throw new Error("Hisobingiz o'zgardi. Ulashishni qaytadan oching.");
        const note = readPublishableNote(noteId);
        if (
          note.clientNoteId !== original.clientNoteId ||
          (original.remoteId && note.remoteId !== original.remoteId)
        )
          throw new Error("Qaydning bulutdagi nusxasi o'zgardi. Ulashishni qaytadan oching.");
        if (!isTeamNote && useConfigStore.getState().config?.cloudBackupEnabled === false) {
          throw new Error("Ulashishdan oldin Hisob → Maxfiylik va ma'lumotlar bo'limida bulutga zaxira nusxani yoqing.");
        }
        // Acknowledgement is repository state: a push clears pendingSync only when the server
        // accepted this exact snapshot, terminal rejections leave a flag, and conflicts or privacy
        // changes are rejected above. It needs no completed pass to observe.
        if (!note.pendingSync) {
          const dirtyTranscript = notesRepository.hasDirtyTranscript(noteId);
          // A rejected create settles with no remote ID, so check before requiring one. A rejection
          // also leaves transcript rows dirty; with those, judge it once a pass has retried them.
          if (notesRepository.isNotePushRejected(noteId) && (!dirtyTranscript || completedPass)) {
            throw new Error(
              "Oxirgi o'zgarishlarni sinxronlash qabul qilmadi. Ulashishdan oldin qaydni tahrirlab, qayta urinib ko'ring.",
            );
          }
          if (note.remoteId && !dirtyTranscript) {
            finish(note.remoteId);
            return;
          }
        }
        // Sync status only reflects this request once a pass has finished with nothing queued.
        if (!completedPass) return;
        if (offline) throw new Error("Internet yo'q. Qaydni ulashish uchun internetga ulaning.");
        const sync = useSyncStore.getState();
        if (sync.policyBlocked) throw new Error('Tashkilotingiz bulutga zaxira nusxaga ruxsat bermaydi.');
        // The subscription check fails closed, so an unreachable server also reads as unsubscribed.
        if (sync.lastError)
          throw new Error("Qaydni sinxronlab bo'lmadi. Internetni tekshirib, qayta urinib ko'ring.");
        if (!isTeamNote && sync.subscriptionRequired) {
          throw new Error('Bu qaydni sinxronlash uchun faol obuna kerak.');
        }
        // The same test pushNotes uses to leave a row queued until its space resolves.
        if (!createPushScopeResolver()(note.spaceId)) {
          throw new Error("Qayd turgan bo'lim hali sinxronlanmagan. Keyinroq qayta urinib ko'ring.");
        }
        // Likewise for a folder that hasn't reached the server yet.
        const folder = notesRepository.getFolders().find(({ id }) => id === note.folderId);
        if (isFolderAwaitingUpload(folder)) {
          throw new Error("Qayd turgan papka hali sinxronlanmagan. Keyinroq qayta urinib ko'ring.");
        }
      } catch (error) {
        finish(error instanceof Error ? error : new Error("Qaydni sinxronlab bo'lmadi."));
      }
    };
    signal.addEventListener('abort', cancel, { once: true });
    unsubscribe.push(
      useAuthStore.subscribe(inspect),
      useNotesStore.subscribe(inspect),
      useConfigStore.subscribe(inspect),
      subscribeSyncCompletion((hasQueuedRun): void => {
        const pass = ++passes;
        completedPass = false;
        if (hasQueuedRun) {
          inspect();
          return;
        }
        // Offline passes end quietly or read as a missing subscription, so the pass only counts
        // once the OS has answered; a newer pass supersedes a slower answer.
        Network.getNetworkStateAsync()
          .then(
            (network) => network.isConnected === false,
            () => false,
          )
          .then((isOffline) => {
            if (pass !== passes) return;
            offline = isOffline;
            completedPass = true;
            inspect();
          });
      }),
    );
    inspect();
    if (!settled) requestSync('manual');
  });
}
