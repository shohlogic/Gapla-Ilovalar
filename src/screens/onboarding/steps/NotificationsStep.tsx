import { useOnboardingStep } from '@/hooks/useOnboardingStep';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { Text } from '@/components/ui/Text';
import { OnboardingShell } from '@/components/onboarding/OnboardingShell';
import { SystemIcon, type LucideIconName } from '@/components/ui/SystemIcon';
import { useOnboardingStore } from '@/store/useOnboardingStore';
import { getNotificationStatus, requestNotifications } from '@/lib/notifications';
import { describeOnboardingError } from '@/lib/onboardingErrors';

type PermissionState = 'checking' | 'undetermined' | 'unavailable';

interface Benefit {
  icon: string;
  mdIcon: LucideIconName;
  text: string;
}

const BENEFITS: Benefit[] = [
  { icon: 'lightbulb.fill', mdIcon: 'Lightbulb', text: 'Tezroq diktovka qilish uchun maslahatlar' },
  { icon: 'sparkles', mdIcon: 'Sparkles', text: 'Yangi imkoniyatlar haqida xabarlar' },
];

export function NotificationsStep() {
  const { goNext, progress } = useOnboardingStep('notifications');
  const setPermissionGranted = useOnboardingStore((s) => s.setPermissionGranted);
  const [state, setState] = useState<PermissionState>('checking');
  const [requesting, setRequesting] = useState(false);
  const [advanceError, setAdvanceError] = useState<string | null>(null);
  const grantedRef = useRef(false);
  const checkedRef = useRef(false);

  const advance = useCallback(
    async (granted: boolean): Promise<void> => {
      grantedRef.current = granted;
      setAdvanceError(null);
      try {
        await setPermissionGranted('notifications', granted);
        await goNext();
      } catch (error) {
        setAdvanceError(describeOnboardingError(error, 'Sozlash jarayoni saqlanmadi.'));
      }
    },
    [goNext, setPermissionGranted],
  );

  useEffect(() => {
    if (checkedRef.current) return;
    checkedRef.current = true;

    getNotificationStatus()
      .then((status) => {
        if (status === 'granted' || status === 'denied') {
          return advance(status === 'granted');
        }
        if (status === 'unavailable') {
          setState('unavailable');
          return;
        }
        setState('undetermined');
      })
      .catch(() => setState('undetermined'));
  }, [advance]);

  const handleAllow = useCallback(async () => {
    setRequesting(true);
    try {
      const result = await requestNotifications();
      await advance(result === 'granted');
    } finally {
      setRequesting(false);
    }
  }, [advance]);

  const handleSkip = useCallback(async () => {
    await goNext();
  }, [goNext]);

  if (advanceError) {
    return (
      <OnboardingShell
        progress={progress}
        title="Sozlashni davom ettirish"
        subtitle={advanceError}
        ctaLabel="Qayta urinish"
        onCta={() => advance(grantedRef.current)}
      />
    );
  }

  if (state === 'checking') {
    return (
      <OnboardingShell
        progress={progress}
        title="Ruxsatlar tekshirilmoqda…"
        ctaLabel="Davom etish"
        ctaDisabled
        onCta={handleSkip}
      >
        <View className="flex-1 items-center justify-center">
          <ActivityIndicator />
        </View>
      </OnboardingShell>
    );
  }

  if (state === 'unavailable') {
    return (
      <OnboardingShell
        progress={progress}
        title="Bildirishnomalar mavjud emas"
        subtitle="Bu versiyada bildirishnomalar yoqilmagan. Sozlashni davom ettirishingiz mumkin."
        ctaLabel="Davom etish"
        onCta={handleSkip}
      >
        <View className="flex-1" />
      </OnboardingShell>
    );
  }

  return (
    <OnboardingShell
      progress={progress}
      title="Xabardor bo'ling"
      titleAccent="Xabardor"
      subtitle="Istalgan vaqtda o'chirib qo'yishingiz mumkin."
      ctaLabel="Bildirishnomalarga ruxsat berish"
      ctaLoading={requesting}
      onCta={handleAllow}
      secondaryCtaLabel="Keyinroq"
      onSecondaryCta={handleSkip}
    >
      <View className="flex-1 items-center justify-start">
        <View className="h-28 w-28 items-center justify-center rounded-2xl bg-secondarySystemGroupedBackground">
          <SystemIcon name="bell.badge.fill" mdName="Bell" size={48} color="brand" />
        </View>

        <View className="mt-8 w-full gap-4">
          {BENEFITS.map((benefit) => (
            <View key={benefit.text} className="flex-row items-center">
              <View className="h-6 w-6 items-center justify-center">
                <SystemIcon name={benefit.icon} mdName={benefit.mdIcon} size={18} color="brand" />
              </View>
              <Text className="ml-3 flex-1 text-[15px] leading-[20px] text-label">
                {benefit.text}
              </Text>
            </View>
          ))}
        </View>
      </View>
    </OnboardingShell>
  );
}
