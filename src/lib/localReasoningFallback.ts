import { Alert } from 'react-native';
import { router } from 'expo-router';
import {
  clearLocalReasoningReadinessCache,
  getLocalReasoningUnavailableMessage,
} from '@/lib/localReasoning';
import { useConfigStore } from '@/store/useConfigStore';
import type { LocalReasoningReadiness } from '@/types';

type FallbackCallback = () => void | Promise<void>;

interface PromptLocalReasoningFallbackOptions {
  readiness: LocalReasoningReadiness;
  signedIn: boolean;
  onEnableLocal?: FallbackCallback;
  onUseCloudOnce?: FallbackCallback;
  // The user's own provider, when that is where this request would go instead of Cloud.
  destinationName?: string;
}

function run(callback: FallbackCallback | undefined): void {
  if (!callback) return;
  Promise.resolve(callback()).catch(() => {});
}

export function promptLocalReasoningFallback({
  readiness,
  signedIn,
  onEnableLocal,
  onUseCloudOnce,
  destinationName,
}: PromptLocalReasoningFallbackOptions): void {
  const message = getLocalReasoningUnavailableMessage(readiness);
  const canEnableLocal = readiness.status === 'disabled' && onEnableLocal;
  // A provider takes the user's own key, so it needs no OpenWhispr account.
  const canUseCloud = (signedIn || !!destinationName) && onUseCloudOnce;
  const buttons = [
    { text: 'Bekor qilish', style: 'cancel' as const },
    ...(canEnableLocal
      ? [
          {
            text: "Lokal AI'ni yoqish",
            onPress: () => {
              useConfigStore
                .getState()
                .updateConfig({ appleLocalIntelligenceEnabled: true })
                .then(() => {
                  clearLocalReasoningReadinessCache();
                  run(onEnableLocal);
                })
                .catch(() => {
                  Alert.alert(
                    "Sozlamani o'zgartirib bo'lmadi",
                    "Lokal Apple Intelligence'ni Hisob sozlamalaridan yoqib ko'ring.",
                  );
                });
            },
          },
        ]
      : []),
    ...(canUseCloud
      ? [
          {
            text: `Bir marta ${destinationName ?? 'bulut'} orqali`,
            onPress: () => run(onUseCloudOnce),
          },
        ]
      : [
          {
            text: 'Hisob',
            onPress: () => router.push('/(account)'),
          },
        ]),
  ];

  Alert.alert(
    'Lokal AI mavjud emas',
    canUseCloud
      ? `${message} Bu safar qayd ${destinationName ?? 'bulutdagi AI'} orqali ishlansinmi?`
      : `${message} Bulutdagi AI'dan foydalanish uchun hisobga kiring yoki keyinroq qayta urinib ko'ring.`,
    buttons,
  );
}
