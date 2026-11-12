import { useOnboardingStep } from '@/hooks/useOnboardingStep';
import { useState } from 'react';
import { Image, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Button } from '@/components/ui/Button';
import { Text } from '@/components/ui/Text';
import { describeOnboardingError } from '@/lib/onboardingErrors';

// Gapla: the app icon stands in for OpenWhispr's mark on the first screen.
const GAPLA_ICON = require('../../../../assets/icon.png');

export function GetStartedStep() {
  const { goNext } = useOnboardingStep('get-started');
  const [error, setError] = useState<string | null>(null);

  const start = (): void => {
    setError(null);
    goNext().catch((cause: unknown) =>
      setError(
        describeOnboardingError(cause, "Sozlash jarayoni saqlanmadi. Qaytadan urinib ko'ring."),
      ),
    );
  };

  return (
    <SafeAreaView className="flex-1 bg-systemBackground" edges={['top', 'bottom']}>
      <View className="flex-1 items-center justify-center gap-5 px-8">
        <Image
          source={GAPLA_ICON}
          accessibilityIgnoresInvertColors
          style={{ width: 72, height: 72, borderRadius: 16 }}
        />
        <Text
          accessibilityRole="header"
          className="text-[34px] font-bold tracking-tight text-label"
        >
          Gapla
        </Text>
        <Text className="text-center text-[17px] leading-[23px] text-secondaryLabel">
          Ovozingiz klaviaturadan 3 barobar tezroq.
        </Text>
      </View>

      <View className="px-6 pb-4">
        {error ? (
          <Text accessibilityRole="alert" className="mb-3 text-center text-[14px] text-systemRed">
            {error}
          </Text>
        ) : null}
        <Button onPress={start} size="lg">
          Boshlash
        </Button>
      </View>
    </SafeAreaView>
  );
}
