import React, { useState } from 'react';
import { Platform } from 'react-native';
import { router } from 'expo-router';
import { SettingsRow, SettingsSection } from '@/components/ui/SettingsSection';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { SettingsSwitch } from '@/components/ui/SettingsSwitch';
import { SoonBadge } from '@/components/ui/SoonBadge';
import { useConfigStore } from '@/store/useConfigStore';
import { useConfigToggle } from '@/hooks/useConfigToggle';
import { DEFAULT_LANGUAGE, getLanguage } from '@/lib/languages';
import { toneLabel, DEFAULT_KEYBOARD_TONE } from '@/lib/keyboardTone';
import { LiveActivity } from '../../modules/live-activity/src';
import { AppGroupStorage, APP_GROUP_KEYS } from '../../modules/app-group-storage/src';

export default function PreferencesScreen() {
  const config = useConfigStore((state) => state.config);
  const autoLearn = config?.autoLearnCorrections ?? true;
  const language = getLanguage(config?.preferredLanguage ?? DEFAULT_LANGUAGE);
  const keyboardTone = config?.keyboardTone ?? DEFAULT_KEYBOARD_TONE;
  const handleToggleAutoLearn = useConfigToggle('autoLearnCorrections');
  const [dictationMode, setDictationMode] = useState(() => LiveActivity.isDictationModeEnabled());
  // Gapla (G47): the orb's test voice, to put the phone next to the sample page.
  const [orbTestVoice, setOrbTestVoice] = useState(
    () => AppGroupStorage.getItem(APP_GROUP_KEYS.GAPLA_ORB_TEST_VOICE) === '1',
  );

  return (
    <SettingsScreen>
      <SettingsSection title="Umumiy">
        <SettingsRow
          iconStyle="line"
          icon="paintbrush"
          mdIcon="Paintbrush"
          title="Ko'rinish"
          rightElement={<SoonBadge />}
          showChevron={false}
        />
        <SettingsRow
          iconStyle="line"
          icon="globe"
          mdIcon="Globe"
          title="Matnga aylantirish tili"
          subtitle={language.label}
          onPress={() => router.push('/(account)/transcription-language')}
        />
        <SettingsRow
          iconStyle="line"
          icon="text.book.closed"
          mdIcon="BookText"
          title="Tuzatishlardan avtomatik o'rganish"
          description="Matnga aylantirilgan matnda tuzatgan so'zlaringiz lug'atingizga avtomatik qo'shiladi."
          rightElement={<SettingsSwitch value={autoLearn} onValueChange={handleToggleAutoLearn} />}
          showChevron={false}
        />
      </SettingsSection>
      <SettingsSection title="Klaviatura">
        {/* First in the section because it is the prerequisite for everything
            below it, and because the person who needs it most is the one whose
            dictation just died. Routes to the recovery screen rather than
            Linking.openSettings(): iOS only ever lands on Settings > OpenWhispr,
            and Full Access is two levels deeper, so the taps have to be taught. */}
        <SettingsRow
          iconStyle="line"
          icon="lock.shield"
          mdIcon="ShieldCheck"
          title="To'liq kirish"
          description="Klaviaturada diktovka uchun kerak. Sozlash qadamlarini ko'rish uchun bosing."
          onPress={() => router.push('/keyboard-full-access')}
        />
        <SettingsRow
          iconStyle="line"
          icon="keyboard"
          mdIcon="Keyboard"
          title="Klaviatura ohangi"
          description="Faqat klaviaturadagi diktovkaga ta'sir qiladi"
          subtitle={toneLabel(keyboardTone)}
          onPress={() => router.push('/(account)/keyboard-tone')}
        />
        <SettingsRow
          iconStyle="line"
          icon="waveform"
          mdIcon="Activity"
          title="Diktovka rejimi"
          description="Diktovka paytida Gapla Dynamic Island'da ko'rinib turadi"
          rightElement={
            <SettingsSwitch
              value={dictationMode}
              onValueChange={(next) => {
                LiveActivity.setDictationMode(next);
                setDictationMode(next);
              }}
            />
          }
          showChevron={false}
        />
        {Platform.OS === 'ios' ? (
          <SettingsRow
            iconStyle="line"
            icon="command"
            mdIcon="Command"
            title="Tashqi klaviaturada tezkor tugma"
            description="Magic Keyboard yoki boshqa tashqi klaviatura orqali istalgan ilovada diktovka qiling"
            onPress={() => router.push('/(account)/hardware-keyboard')}
          />
        ) : null}
        {Platform.OS === 'ios' ? (
          <SettingsRow
            iconStyle="line"
            icon="sparkles"
            mdIcon="Sparkles"
            title="Animatsiya sinovi"
            description="Yozish paytida shar mikrofon o'rniga namuna sahifasidagi sinov ovozi bilan harakatlanadi. Faqat solishtirish uchun; matn odatdagidek yoziladi."
            rightElement={
              <SettingsSwitch
                value={orbTestVoice}
                onValueChange={(next) => {
                  AppGroupStorage.setItem(APP_GROUP_KEYS.GAPLA_ORB_TEST_VOICE, next ? '1' : '0');
                  setOrbTestVoice(next);
                }}
              />
            }
            showChevron={false}
          />
        ) : null}
      </SettingsSection>
    </SettingsScreen>
  );
}
