import { Alert } from 'react-native';
import { router } from 'expo-router';
import { LocalTranscriptionService } from '@/services/transcription/LocalTranscriptionService';

export type PrivateModeStatus = 'ready' | 'missing' | 'unavailable';

export interface PrivateModeReadiness {
  status: PrivateModeStatus;
  /** Display label of the engine the user's language selection routes to (e.g. "Parakeet v2"). */
  modelName: string;
}

/**
 * Whether private mode can transcribe right now: the engine the user's language selection
 * routes to (Parakeet v2/v3 or Whisper) has its model downloaded. The legacy modelName
 * parameter is accepted for call-site compatibility but ignored — readiness is language-aware.
 */
export async function getPrivateModeReadiness(
  _legacyModelName?: string,
): Promise<PrivateModeReadiness> {
  const modelName = LocalTranscriptionService.preferredEngineDescriptor().label;

  if (!LocalTranscriptionService.isAvailable()) {
    return { status: 'unavailable', modelName };
  }

  const ready = await LocalTranscriptionService.isReadyForLanguage();
  return { status: ready ? 'ready' : 'missing', modelName };
}

export function getPrivateModeUnavailableMessage(): string {
  return "Qurilmada matnga aylantirish uchun Gapla'ni iOS modullari bilan to'liq yig'ing.";
}

// Private mode with no on-device model. We never upload automatically — the
// user explicitly chooses to download the model or send this one recording to
// the cloud. onDecline runs for either choice that leaves this recording untranscribed.
export function promptLocalModelFallback(onUseCloudOnce: () => void, onDecline?: () => void): void {
  Alert.alert(
    'Qurilmadagi model mavjud emas',
    "Maxfiy diktovka uchun model yuklab olinmagan, shuning uchun bu yozuvni qurilmada matnga aylantirib bo'lmaydi. Uning o'rniga bulutga yuborilsinmi?",
    [
      { text: 'Bekor qilish', style: 'cancel', onPress: onDecline },
      {
        text: 'Modelni yuklab olish',
        onPress: () => {
          onDecline?.();
          router.push('/(account)/model-download');
        },
      },
      { text: 'Bir marta bulutdan foydalanish', onPress: onUseCloudOnce },
    ],
  );
}
