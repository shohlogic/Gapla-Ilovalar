import { Linking } from 'react-native';
import { showPermissionAlert } from '@/components/ui/PermissionAlert';

// `nativePromptShown` distinguishes "iOS just displayed its system dialog and
// the user tapped Deny" from "permission was already resolved before this
// attempt, so iOS showed no UI at all" (iOS only ever prompts once per
// install — see `getRecordingPermissionsAsync` check in useAudioRecording).
// Apple rejects apps that show a custom Settings-redirect in place of the
// system prompt, so callers must only show one when nativePromptShown is
// false — never as a substitute for a prompt that could still appear.
export class MicPermissionError extends Error {
  readonly canAskAgain: boolean;
  readonly nativePromptShown: boolean;

  constructor(message: string, options: { canAskAgain: boolean; nativePromptShown: boolean }) {
    super(message);
    this.name = 'MicPermissionError';
    this.canAskAgain = options.canAskAgain;
    this.nativePromptShown = options.nativePromptShown;
  }
}

export function isMicPermissionError(err: unknown): err is MicPermissionError {
  return err instanceof MicPermissionError;
}

// Gapla: Uzbek on screen; isNoSpeechError matches it and the English server wording.
export const NO_SPEECH_ERROR_MESSAGE = 'Gap eshitilmadi';

export function isNoSpeechError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : '';
  const lower = message.toLowerCase();
  return (
    lower.includes('no speech') ||
    lower.includes(NO_SPEECH_ERROR_MESSAGE.toLowerCase()) ||
    lower.includes('audio_too_short') ||
    lower.includes('audio too short') ||
    lower.includes('minimum audio length') ||
    lower.includes('recording file is empty')
  );
}

export function showMicPermissionAlert(): void {
  showPermissionAlert({
    title: 'Mikrofonga ruxsat kerak',
    message: "Diktovka uchun Gapla'ga mikrofonga ruxsat kerak. Davom etish uchun uni Sozlamalarda yoqing.",
    primaryLabel: 'Sozlamalarni ochish',
    onPrimary: () => Linking.openSettings(),
  });
}
