import { useOnboardingStep } from '@/hooks/useOnboardingStep';
import { View } from 'react-native';
import { OnboardingShell } from '@/components/onboarding/OnboardingShell';
import { AnimatedKeyboardPreview } from '@/components/onboarding/AnimatedKeyboardPreview';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { Text } from '@/components/ui/Text';

const TRUST_POINTS = [
  "Ma'lumotlaringiz sotilmaydi",
  'Reklama profili tuzilmaydi',
  "Qayerda ishlov berilishini o'zingiz tanlaysiz",
];

export function WelcomeStep() {
  const { goNext } = useOnboardingStep('welcome');

  return (
    <OnboardingShell
      title="Xavfsiz ovozli yozish"
      titleAccent="Xavfsiz"
      subtitle="iPhone'ning istalgan joyida bemalol gapirib yozing: xatlar, xabarlar, qaydlar va AI chatlar."
      ctaLabel="Sozlash"
      onCta={goNext}
    >
      <View className="flex-1 justify-center gap-5">
        <View className="w-full items-center justify-center overflow-hidden rounded-lg">
          <AnimatedKeyboardPreview />
        </View>
        <View className="gap-2">
          {TRUST_POINTS.map((point) => (
            <View key={point} className="flex-row items-center gap-2">
              <SystemIcon name="checkmark" mdName="Check" size={14} color="systemGreen" />
              <Text className="flex-1 text-[14px] leading-[19px] text-secondaryLabel">{point}</Text>
            </View>
          ))}
        </View>
      </View>
    </OnboardingShell>
  );
}
