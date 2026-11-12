import { View } from 'react-native';
import { Disclosure } from '@/components/onboarding/Disclosure';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { Text } from '@/components/ui/Text';

const REASONS = [
  'Istalgan ilovada matnga aylantirish ishlaydi',
  "Apple qo'shimcha klaviaturalardan shuni talab qiladi",
  'Yozuvlaringizni hech qachon saqlamaymiz va sotmaymiz',
];

/** The "why do you need this?" answer, shown wherever we ask for Full Access. */
export function FullAccessReasons() {
  return (
    <Disclosure title="Gapla'ga nega to'liq kirish kerak?">
      <View className="gap-2">
        {REASONS.map((reason) => (
          <View key={reason} className="flex-row items-start gap-2">
            <View className="mt-px">
              <SystemIcon name="checkmark" mdName="Check" size={13} color="systemGreen" />
            </View>
            <Text className="flex-1 text-[13px] leading-[18px] text-secondaryLabel">{reason}</Text>
          </View>
        ))}
      </View>
    </Disclosure>
  );
}
