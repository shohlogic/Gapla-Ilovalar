import { useOnboardingStep } from '@/hooks/useOnboardingStep';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Linking, View } from 'react-native';
import { OnboardingShell } from '@/components/onboarding/OnboardingShell';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { useOnboardingStore } from '@/store/useOnboardingStore';
import { getExpoAudioModule } from '@/utils/expoAudio';
import { describeOnboardingError } from '@/lib/onboardingErrors';
import { AppGroupStorage } from '../../../../modules/app-group-storage/src';

type PermissionState = 'checking' | 'undetermined' | 'granted' | 'denied' | 'unavailable';

type RecordingPermissionStatus = { granted: boolean; canAskAgain: boolean };

export function MicrophoneStep() {
  const { goNext, progress } = useOnboardingStep('microphone');
  const setPermissionGranted = useOnboardingStore((s) => s.setPermissionGranted);
  const [state, setState] = useState<PermissionState>('checking');
  const [requesting, setRequesting] = useState(false);
  const [advanceError, setAdvanceError] = useState<string | null>(null);
  const requestingRef = useRef(false);
  const advancedRef = useRef(false);

  // Marks the permission as granted and moves on, exactly once — guards against
  // the mount check, the AppState re-check, and the request all racing to advance.
  const advance = useCallback(async () => {
    if (advancedRef.current) return;
    advancedRef.current = true;
    setAdvanceError(null);
    // The native side refuses to warm the dictation mic without permission, so
    // a just-granted permission has to be announced — otherwise warming waits
    // for the next foreground and the keyboard stays "not ready" until then.
    AppGroupStorage.armWarmMic();
    try {
      await setPermissionGranted('microphone', true);
      await goNext();
    } catch (error) {
      advancedRef.current = false;
      setAdvanceError(describeOnboardingError(error, 'Sozlash jarayoni saqlanmadi.'));
    }
  }, [goNext, setPermissionGranted]);

  const applyStatus = useCallback(
    async (status: RecordingPermissionStatus) => {
      if (status.granted) {
        await advance();
        return;
      }
      setState(status.canAskAgain ? 'undetermined' : 'denied');
    },
    [advance],
  );

  // Initial permission check on mount.
  useEffect(() => {
    const audio = getExpoAudioModule();
    if (!audio) {
      setState('unavailable');
      return;
    }
    audio.AudioModule.getRecordingPermissionsAsync()
      .then(applyStatus)
      .catch(() => setState('undetermined'));
  }, [applyStatus]);

  // Re-check whenever the app returns to the foreground so a grant made in
  // Settings advances the flow without the user tapping again. Skipped while our
  // own system prompt is in flight (handled by handleAllow) to avoid a double advance.
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (next) => {
      if (next !== 'active' || requestingRef.current) return;
      const audio = getExpoAudioModule();
      if (!audio) return;
      audio.AudioModule.getRecordingPermissionsAsync()
        .then(applyStatus)
        .catch(() => {});
    });
    return () => subscription.remove();
  }, [applyStatus]);

  const handleAllow = useCallback(async () => {
    const audio = getExpoAudioModule();
    if (!audio) {
      await goNext();
      return;
    }

    setRequesting(true);
    requestingRef.current = true;
    try {
      const result = await audio.AudioModule.requestRecordingPermissionsAsync();

      if (result.granted) {
        await advance();
        return;
      }

      await setPermissionGranted('microphone', false);

      if (!result.canAskAgain) {
        Alert.alert(
          'Mikrofonga ruxsat berilmagan',
          "Gapla'ga ruxsat berish uchun Sozlamalarni oching. Hozircha sozlashni davom ettirishingiz mumkin.",
          [
            { text: 'Sozlamalarni ochish', onPress: () => Linking.openSettings() },
            {
              text: 'Davom etish',
              style: 'cancel',
              onPress: () =>
                goNext().catch((error: unknown) =>
                  Alert.alert(
                    "Davom etib bo'lmadi",
                    describeOnboardingError(error, 'Sozlash jarayoni saqlanmadi.'),
                  ),
                ),
            },
          ],
        );
        return;
      }

      await goNext();
    } finally {
      setRequesting(false);
      requestingRef.current = false;
    }
  }, [advance, goNext, setPermissionGranted]);

  const handleOpenSettings = useCallback(() => {
    Linking.openSettings();
  }, []);

  const handleSkip = useCallback(async () => {
    await goNext();
  }, [goNext]);

  if (advanceError) {
    return (
      <OnboardingShell
        progress={progress}
        title="Mikrofon tayyor"
        subtitle={advanceError}
        ctaLabel="Qayta urinish"
        onCta={advance}
      >
        <View className="flex-1" />
      </OnboardingShell>
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

  if (state === 'denied') {
    return (
      <OnboardingShell
        progress={progress}
        title="Mikrofonga ruxsat yo'q"
        titleAccent="ruxsat yo'q"
        subtitle="Sozlamalarni oching va Gapla'ga mikrofondan foydalanishga ruxsat bering."
        ctaLabel="Sozlamalarni ochish"
        onCta={handleOpenSettings}
        secondaryCtaLabel="Baribir davom etish"
        onSecondaryCta={handleSkip}
      >
        <View className="flex-1 items-center justify-center">
          <View className="h-28 w-28 items-center justify-center rounded-2xl bg-secondarySystemGroupedBackground">
            <SystemIcon name="mic.slash.fill" mdName="MicOff" size={48} color="secondaryLabel" />
          </View>
        </View>
      </OnboardingShell>
    );
  }

  if (state === 'unavailable') {
    return (
      <OnboardingShell
        progress={progress}
        title="Mikrofon mavjud emas"
        subtitle="Bu versiyada ovoz yozib bo'lmaydi. Sozlashni davom ettirishingiz mumkin."
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
      title="Mikrofonga ruxsat bering"
      titleAccent="Mikrofonga"
      subtitle="Mikrofon orqali Gapla nutqingizni matnga aylantiradi."
      ctaLabel="Davom etish"
      ctaLoading={requesting}
      onCta={handleAllow}
    >
      <View className="flex-1 items-center justify-center">
        <View className="h-28 w-28 items-center justify-center rounded-2xl bg-secondarySystemGroupedBackground">
          <SystemIcon name="mic.fill" mdName="Mic" size={48} color="brand" />
        </View>
      </View>
    </OnboardingShell>
  );
}
