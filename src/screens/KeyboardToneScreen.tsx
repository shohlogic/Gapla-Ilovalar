import React, { useCallback } from 'react';
import { View } from 'react-native';
import { Text } from '@/components/ui/Text';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { SettingsRow, SettingsSection } from '@/components/ui/SettingsSection';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { useConfigStore } from '@/store/useConfigStore';
import { useProcessingModeStore } from '@/store/useProcessingModeStore';
import { KEYBOARD_TONES, DEFAULT_KEYBOARD_TONE, isToneApplicable } from '@/lib/keyboardTone';
import { setKeyboardTone } from '@/lib/keyboardToneSync';
import { safeHaptics } from '@/lib/utils';
import type { KeyboardTone } from '@/types';

export default function KeyboardToneScreen() {
  const config = useConfigStore((state) => state.config);
  const activeMode = useProcessingModeStore((state) => state.activeMode);

  const selected: KeyboardTone = config?.keyboardTone ?? DEFAULT_KEYBOARD_TONE;
  const applicable = isToneApplicable(activeMode, config?.cleanupEnabled);

  const onSelect = useCallback((tone: KeyboardTone): void => {
    safeHaptics('selection');
    setKeyboardTone(tone);
  }, []);

  return (
    <View className="flex-1 bg-systemBackground">
      <SettingsScreen>
        <View className="mx-4 mb-2 px-4">
          <Text className="text-[13px] text-secondaryLabel">
            Klaviaturadagi diktovka matnining uslubini belgilaydi. Faqat klaviaturadagi diktovkaga
            ta'sir qiladi: shaxsiy yozuvlar, yuklangan fayllar va uchrashuvlarga emas.
          </Text>
        </View>

        {!applicable ? (
          <View className="mx-4 mb-3" style={{ borderCurve: 'continuous' }}>
            <View className="rounded-[14px] border border-separator bg-secondarySystemGroupedBackground px-4 py-3">
              <Text className="text-[13px] text-secondaryLabel">
                Ohang faqat «Gapla Bulut» rejimida, Matnni tozalash yoqilganda ishlaydi.
                Tanlovingiz saqlangan, ikkalasi yoqilgach qo'llanadi.
              </Text>
            </View>
          </View>
        ) : null}

        <SettingsSection title="Ohang">
          {KEYBOARD_TONES.map((tone) => (
            <SettingsRow
              key={tone.value}
              iconStyle="line"
              icon="textformat"
              mdIcon="Type"
              title={tone.label}
              description={tone.description}
              onPress={() => onSelect(tone.value)}
              selected={selected === tone.value}
              rightElement={
                selected === tone.value ? (
                  <SystemIcon name="checkmark" mdName="Check" size={18} color="brand" />
                ) : undefined
              }
              showChevron={false}
            />
          ))}
        </SettingsSection>
      </SettingsScreen>
    </View>
  );
}
