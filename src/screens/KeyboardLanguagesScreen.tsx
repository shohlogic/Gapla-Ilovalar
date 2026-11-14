// Gapla (G58): which languages the Gapla keyboard has. O'zbekcha is always on; the others can be
// turned off. The keyboard reads the choice the next time it comes up (src/lib/keyboardLanguages.ts).
import React from 'react';
import { View } from 'react-native';
import { Text } from '@/components/ui/Text';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { SettingsRow, SettingsSection } from '@/components/ui/SettingsSection';
import { SettingsSwitch } from '@/components/ui/SettingsSwitch';
import { KEYBOARD_LANGUAGES, useKeyboardLanguages } from '@/lib/keyboardLanguages';
import { safeHaptics } from '@/lib/utils';

export default function KeyboardLanguagesScreen() {
  const [enabled, setLanguageOn] = useKeyboardLanguages();

  return (
    <SettingsScreen>
      <View className="mx-4 mb-2 px-4">
        <Text className="text-[13px] text-secondaryLabel">
          Klaviaturadagi til tugmasi yoqilgan tillar orasida almashtiradi. Tugmani bosib tursangiz,
          tillar ro'yxati ochiladi.
        </Text>
      </View>

      <SettingsSection title="Tillar">
        {KEYBOARD_LANGUAGES.map((language) => {
          const alwaysOn = language.id === 'uz';
          return (
            <SettingsRow
              key={language.id}
              iconStyle="line"
              icon="keyboard"
              mdIcon="Keyboard"
              title={language.name}
              description={
                alwaysOn
                  ? 'Doim yoqilgan'
                  : language.id === 'rq'
                    ? "Harflar lotin klaviaturasidagi o'rnida"
                    : undefined
              }
              rightElement={
                <SettingsSwitch
                  value={alwaysOn || enabled.includes(language.id)}
                  disabled={alwaysOn}
                  onValueChange={(next) => {
                    safeHaptics('selection');
                    setLanguageOn(language.id, next);
                  }}
                />
              }
              showChevron={false}
            />
          );
        })}
      </SettingsSection>

      <View className="mx-4 mt-1 px-4">
        <Text className="text-[13px] text-secondaryLabel">
          So'z tavsiyalari faqat o'zbekchada chiqadi. O'zgarish klaviatura keyingi safar ochilganda
          ko'rinadi.
        </Text>
      </View>
    </SettingsScreen>
  );
}
