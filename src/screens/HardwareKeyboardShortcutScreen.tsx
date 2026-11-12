import React, { useCallback, useEffect, useState } from 'react';
import { AppState, Linking, View } from 'react-native';
import {
  SettingsRow,
  SettingsSection,
  SettingsTextFieldRow,
} from '@/components/ui/SettingsSection';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { SettingsSwitch } from '@/components/ui/SettingsSwitch';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { Text } from '@/components/ui/Text';
import {
  getNotificationStatus,
  requestNotifications,
  type NotificationStatus,
} from '@/lib/notifications';
import { LiveActivity } from '../../modules/live-activity/src';

export const SHORTCUTS_CREATE_URL = 'shortcuts://create-shortcut';
export const SHORTCUTS_APP_URL = 'shortcuts://';
// Full Keyboard Access claims Tab and Fn combos by default and no Option ones.
const SUGGESTED_COMBO = '⌥D';

// iOS can refuse the editor deep link. The Shortcuts app itself is enough, since
// step 2 says which action to add, and a refusal must never become an error screen.
async function openShortcuts(): Promise<void> {
  try {
    await Linking.openURL(SHORTCUTS_CREATE_URL);
  } catch {
    await Linking.openURL(SHORTCUTS_APP_URL).catch(() => undefined);
  }
}

/**
 * Setup for dictating from a hardware keyboard (plugins/hotkey-dictation).
 * iPadOS hides third-party keyboards while a hardware keyboard is attached, so
 * the path is a Shortcuts action bound to a Full Keyboard Access command, with
 * the transcript delivered on the clipboard. Apple doesn't allow deep links into
 * Accessibility settings, so steps 3 and 4 are written out.
 */
export function HardwareKeyboardShortcutScreen() {
  const [dictationMode, setDictationMode] = useState(() => LiveActivity.isDictationModeEnabled());
  const [notificationStatus, setNotificationStatus] = useState<NotificationStatus | null>(null);
  const [tryText, setTryText] = useState('');

  const refreshNotificationStatus = useCallback(() => {
    getNotificationStatus()
      .then(setNotificationStatus)
      .catch(() => setNotificationStatus('unavailable'));
  }, []);

  // Re-read on return from Settings, where a denied user may have allowed them.
  useEffect(() => {
    refreshNotificationStatus();
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') refreshNotificationStatus();
    });
    return () => subscription.remove();
  }, [refreshNotificationStatus]);

  const handleNotifications = useCallback(async () => {
    if (notificationStatus === 'denied') {
      await Linking.openSettings();
      return;
    }
    setNotificationStatus(await requestNotifications());
  }, [notificationStatus]);

  const needsNotifications =
    notificationStatus === 'undetermined' || notificationStatus === 'denied';
  const tried = tryText.trim().length > 0;

  return (
    <SettingsScreen>
      <Text className="px-4 pb-2 text-[15px] text-secondaryLabel">
        Istalgan ilovada tugmalar birikmasini bosing — diktovka boshlanadi. Yana bossangiz,
        to'xtaydi. Keyin joylash uchun ⌘V ni bosing.
      </Text>
      <SettingsSection title="1. Diktovka rejimi">
        <SettingsRow
          iconStyle="line"
          icon="waveform"
          mdIcon="Activity"
          title="Diktovka rejimi"
          description="Tezkor tugma yozishni darhol boshlashi uchun buni yoqilgan holda qoldiring."
          rightElement={
            <SettingsSwitch
              testID="hardware-keyboard-dictation-mode"
              value={dictationMode}
              onValueChange={(next) => {
                LiveActivity.setDictationMode(next);
                setDictationMode(next);
              }}
            />
          }
          showChevron={false}
        />
      </SettingsSection>
      <SettingsSection title="2. Tezkor buyruq qo'shing">
        <SettingsRow
          iconStyle="line"
          icon="square.stack.3d.up"
          mdIcon="Layers"
          title="Tezkor buyruqlarni ochish"
          description="«Gapla diktovkasini yoqish/o'chirish» amalini qo'shing, keyin «Tayyor»ni bosing."
          onPress={openShortcuts}
        />
      </SettingsSection>
      <SettingsSection title="3. Klaviaturadan to'liq boshqaruvni yoqing">
        <SettingsRow
          iconStyle="line"
          icon="keyboard"
          mdIcon="Keyboard"
          title="Klaviaturadan to'liq boshqaruv"
          description="Sozlamalar → Maxsus imkoniyatlar → Klaviaturalar va yozish bo'limida «Klaviaturadan to'liq boshqaruv»ni yoqing. U o'chiq bo'lsa, tezkor tugma ishlamaydi."
          showChevron={false}
        />
      </SettingsSection>
      <SettingsSection title="4. Tugmalar birikmasini belgilang">
        <SettingsRow
          iconStyle="line"
          icon="command"
          mdIcon="Command"
          title="Gapla diktovkasini yoqish/o'chirish"
          description={`«Klaviaturadan to'liq boshqaruv»da «Buyruqlar»ni oching, «Tezkor buyruqlar» ostida shu amalni tanlang va ${SUGGESTED_COMBO} (Option-D) ni bosing.`}
          showChevron={false}
        />
      </SettingsSection>
      {needsNotifications ? (
        <SettingsSection title="5. Bildirishnomalarga ruxsat bering">
          <SettingsRow
            iconStyle="line"
            icon="bell.badge"
            mdIcon="BellRing"
            title={
              notificationStatus === 'denied'
                ? 'Sozlamalarni ochish'
                : 'Bildirishnomalarga ruxsat berish'
            }
            description="Har diktovkadan keyin «Nusxalandi — joylash uchun ⌘V ni bosing» xabari chiqadi."
            onPress={handleNotifications}
          />
        </SettingsSection>
      ) : null}
      <SettingsSection title="Sinab ko'ring">
        <SettingsTextFieldRow
          icon="text.cursor"
          mdIcon="TextCursorInput"
          placeholder={`${SUGGESTED_COMBO}, gapiring, ${SUGGESTED_COMBO}, keyin ⌘V`}
          value={tryText}
          onChangeText={setTryText}
          testID="hardware-keyboard-try-it"
          trailing={
            tried ? (
              <View testID="hardware-keyboard-try-it-done">
                <SystemIcon
                  name="checkmark.circle.fill"
                  mdName="CircleCheck"
                  size={20}
                  color="systemGreen"
                />
              </View>
            ) : null
          }
        />
      </SettingsSection>
    </SettingsScreen>
  );
}
