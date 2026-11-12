import { useEffect, useRef, useState } from 'react';
import type React from 'react';
import { Pressable, View } from 'react-native';
import { useHeaderHeight } from '@react-navigation/elements';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Text } from '@/components/ui/Text';
import { Button } from '@/components/ui/Button';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { GradientGlassSurface } from '@/components/ui/GradientGlassSurface';

export interface SpeakerCountPromptProps {
  onSubmit: (count: number | undefined) => void;
  eventSlot?: React.ReactNode;
  selectedEventTitle?: string | null;
  countHint?: number;
  countHintKey?: string | number | null;
}

const MIN_COUNT = 1;
const MAX_COUNT = 9;
const DEFAULT_COUNT = 2;

const AVATAR_GRADIENTS = [
  // Gapla mandarini, moviy-yashil va iliq grafit (G54: eski ko'k-binafsha logo gradienti o'rniga).
  ['#C24F1F', '#B0451A'],
  ['#16b9cf', '#0e8aa0'],
  ['#4A4440', '#1C1917'],
] as const;

const clampCount = (value: number): number => Math.min(MAX_COUNT, Math.max(MIN_COUNT, value));

const Stepper = ({
  count,
  onDecrement,
  onIncrement,
}: {
  count: number;
  onDecrement: () => void;
  onIncrement: () => void;
}): React.JSX.Element => (
  <View
    className="flex-row items-center justify-between rounded-[20px] border border-separator bg-secondarySystemGroupedBackground p-3"
    style={{ borderCurve: 'continuous' }}
  >
    <Pressable
      testID="speaker-count-decrement"
      accessibilityRole="button"
      accessibilityLabel="Kamroq odam"
      onPress={onDecrement}
      disabled={count <= MIN_COUNT}
      className={`h-[52px] w-[52px] items-center justify-center rounded-full bg-tertiarySystemFill active:opacity-70 ${
        count <= MIN_COUNT ? 'opacity-40' : ''
      }`}
    >
      <SystemIcon name="minus" mdName="Minus" size={24} color="brand" />
    </Pressable>
    <View className="items-center">
      <Text className="text-[40px] font-bold leading-none text-label">{count}</Text>
      <Text className="mt-1 text-[12px] font-semibold uppercase tracking-wider text-tertiaryLabel">
        kishi
      </Text>
    </View>
    <Pressable
      testID="speaker-count-increment"
      accessibilityRole="button"
      accessibilityLabel="Ko'proq odam"
      onPress={onIncrement}
      disabled={count >= MAX_COUNT}
      className={`h-[52px] w-[52px] items-center justify-center rounded-full bg-tertiarySystemFill active:opacity-70 ${
        count >= MAX_COUNT ? 'opacity-40' : ''
      }`}
    >
      <SystemIcon name="plus" mdName="Plus" size={24} color="brand" />
    </Pressable>
  </View>
);

// Overlapping avatars summarizing the derived count; the third collapses to "+N" when it overflows.
const AvatarStack = ({ count }: { count: number }): React.JSX.Element => {
  const visibleAvatars = Math.min(count, 3);
  return (
    <View className="flex-row">
      {Array.from({ length: visibleAvatars }, (_, index) => {
        const isOverflowSlot = count > 3 && index === 2;
        return (
          <View
            key={index}
            className="h-9 w-9 items-center justify-center overflow-hidden rounded-full border-2 border-secondarySystemGroupedBackground bg-primary"
            style={{ marginLeft: index === 0 ? 0 : -10 }}
          >
            <GradientGlassSurface shape="circle" colors={AVATAR_GRADIENTS[index]} />
            {isOverflowSlot ? (
              <Text className="text-[12px] font-bold text-white">{`+${count - 2}`}</Text>
            ) : (
              <SystemIcon name="person.fill" mdName="User" size={15} color="#ffffff" />
            )}
          </View>
        );
      })}
    </View>
  );
};

export const SpeakerCountPrompt = ({
  onSubmit,
  eventSlot,
  selectedEventTitle,
  countHint,
  countHintKey = null,
}: SpeakerCountPromptProps): React.JSX.Element => {
  const [count, setCount] = useState(DEFAULT_COUNT);
  const [autoDetect, setAutoDetect] = useState(false);
  const [adjusting, setAdjusting] = useState(false);
  const appliedHintKeyRef = useRef<string | number | null>(null);
  const headerHeight = useHeaderHeight();
  const insets = useSafeAreaInsets();

  useEffect(() => {
    if (countHint == null || countHintKey == null) {
      appliedHintKeyRef.current = null;
      return;
    }
    if (appliedHintKeyRef.current === countHintKey) return;
    setCount(clampCount(countHint));
    appliedHintKeyRef.current = countHintKey;
  }, [countHint, countHintKey]);

  // Collapse transient overrides (Adjust / auto-detect) whenever the selected event changes.
  useEffect(() => {
    setAdjusting(false);
    setAutoDetect(false);
  }, [countHintKey]);

  const decrement = (): void => setCount((current) => Math.max(MIN_COUNT, current - 1));
  const increment = (): void => setCount((current) => Math.min(MAX_COUNT, current + 1));

  const hasEventList = !!eventSlot;
  const hasEvent = !!selectedEventTitle;
  const derivedCount = hasEvent && countHint != null ? clampCount(countHint) : null;

  // A count derived from the event shows a read-only summary; otherwise we ask with the stepper,
  // where auto-detect can replace the manual count. Adjusting reopens the stepper over a derived count.
  const showDerivedSummary = derivedCount != null && !adjusting;
  const showAutoDetect = autoDetect && derivedCount == null;
  const showStepper = !showDerivedSummary && !showAutoDetect;

  const handleStart = (): void => {
    onSubmit(showAutoDetect ? undefined : count);
  };

  const resetToDerived = (): void => {
    if (derivedCount != null) setCount(derivedCount);
    setAdjusting(false);
  };

  return (
    <View
      className="flex-1 bg-systemBackground px-6"
      style={{ paddingTop: headerHeight + 16, paddingBottom: Math.max(insets.bottom + 16, 32) }}
    >
      <Text accessibilityRole="header" className="text-[28px] font-bold leading-tight text-label">
        {hasEventList ? 'Nimani yozib olasiz?' : 'Necha kishi qatnashadi?'}
      </Text>
      <Text className="mt-2 text-base leading-5 text-secondaryLabel">
        {hasEventList
          ? 'Gapiruvchilar avtomatik belgilanishi uchun uchrashuvni tanlang yoki shunchaki yozib oling.'
          : 'Sonini kiritsangiz, gapiruvchilar aniqroq belgilanadi. Avtomatik aniqlashni ham tanlashingiz mumkin.'}
      </Text>

      {hasEventList ? <View className="mt-5">{eventSlot}</View> : null}

      <View className={hasEventList ? 'mt-6' : 'mt-8'}>
        {hasEventList ? (
          <Text className="mb-2 text-[13px] font-semibold uppercase tracking-wider text-secondaryLabel">
            {showStepper ? 'Necha kishi?' : 'Ishtirokchilar'}
          </Text>
        ) : null}

        {showStepper ? (
          <>
            <Stepper count={count} onDecrement={decrement} onIncrement={increment} />
            {derivedCount == null ? (
              <Pressable
                testID="speaker-count-autodetect"
                accessibilityRole="button"
                onPress={() => setAutoDetect(true)}
                className="mt-3 h-9 items-center justify-center active:opacity-70"
              >
                <Text className="text-[15px] font-semibold text-brand">
                  Gapiruvchilarni avtomatik aniqlash
                </Text>
              </Pressable>
            ) : (
              <View className="mt-3 h-9 flex-row items-center justify-center gap-1.5">
                <Text className="text-[13px] font-medium text-secondaryLabel">
                  {`Tadbirda ${derivedCount} kishi edi ·`}
                </Text>
                <Pressable
                  testID="speaker-count-reset"
                  accessibilityRole="button"
                  onPress={resetToDerived}
                  className="active:opacity-70"
                >
                  <Text className="text-[13px] font-semibold text-brand">Asliga qaytarish</Text>
                </Pressable>
              </View>
            )}
          </>
        ) : showDerivedSummary ? (
          <View
            className="flex-row items-center gap-3 rounded-[20px] border border-separator bg-secondarySystemGroupedBackground p-3.5"
            style={{ borderCurve: 'continuous' }}
          >
            <AvatarStack count={count} />
            <View className="min-w-0 flex-1">
              <Text className="text-[16px] font-bold text-label">
                {`${count} kishi`}
              </Text>
              <Text numberOfLines={1} className="text-[12px] font-medium text-secondaryLabel">
                {`Tadbirdan: ${selectedEventTitle}`}
              </Text>
            </View>
            <Pressable
              testID="speaker-count-adjust"
              accessibilityRole="button"
              onPress={() => setAdjusting(true)}
              className="px-1.5 py-1 active:opacity-70"
            >
              <Text className="text-[14px] font-semibold text-brand">O&apos;zgartirish</Text>
            </Pressable>
          </View>
        ) : (
          <View
            className="flex-row items-center gap-3 rounded-[20px] border border-separator bg-secondarySystemGroupedBackground p-3.5"
            style={{ borderCurve: 'continuous' }}
          >
            <View
              className="h-[38px] w-[38px] items-center justify-center rounded-[10px] bg-brand/10"
              style={{ borderCurve: 'continuous' }}
            >
              <SystemIcon name="sparkles" mdName="Sparkles" size={20} color="brand" />
            </View>
            <View className="min-w-0 flex-1">
              <Text className="text-[15px] font-bold text-label">Gapiruvchilarni avtomatik aniqlash</Text>
              <Text className="text-[12px] font-medium text-secondaryLabel">
                Kim gapirganini o&apos;zimiz aniqlaymiz
              </Text>
            </View>
            <Pressable
              testID="speaker-count-setcount"
              accessibilityRole="button"
              onPress={() => setAutoDetect(false)}
              className="px-1.5 py-1 active:opacity-70"
            >
              <Text className="text-[14px] font-semibold text-brand">Sonini kiritish</Text>
            </Pressable>
          </View>
        )}
      </View>

      <View className="mt-auto pt-4">
        <Button testID="speaker-count-confirm" size="lg" onPress={handleStart}>
          Yozishni boshlash
        </Button>
      </View>
    </View>
  );
};
