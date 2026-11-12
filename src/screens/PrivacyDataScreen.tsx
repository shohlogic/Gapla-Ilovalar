import React, { useCallback, useEffect, useState } from 'react';
import { SettingsRow, SettingsSection } from '@/components/ui/SettingsSection';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { SettingsSwitch } from '@/components/ui/SettingsSwitch';
import { useConfigStore } from '@/store/useConfigStore';
import { useConfigToggle } from '@/hooks/useConfigToggle';
import { useAuthStore } from '@/store/useAuthStore';
import { useNotesStore } from '@/store/useNotesStore';
import { useUsageStore } from '@/store/useUsageStore';
import { useSyncStore } from '@/sync/useSyncStore';
import { requestSync } from '@/sync/syncEngine';
import { formatRelativeTime, safeHaptics } from '@/lib/utils';
import { confirmDestructive } from '@/lib/alerts';

const RELATIVE_TICK_MS = 30_000;

function describeSyncStatus(
  enabled: boolean,
  signedIn: boolean,
  status: string,
  lastSyncAt: string | null,
  paidPlanRequired: boolean,
  policyBlocked: boolean,
): string {
  if (!signedIn) return 'Bulutga zaxira nusxa uchun hisobga kiring.';
  if (paidPlanRequired) return "Bulutga zaxira nusxa uchun Pro kerak. Hisob → Tariflar va to'lov bo'limida yangilang.";
  if (policyBlocked) return "Bulutga zaxira nusxani tashkilotingiz o'chirib qo'ygan.";
  if (!enabled)
    return "Zaxira nusxa o'chiq. Shaxsiy qaydlar shu qurilmada qoladi, umumiy maydonlardagi qaydlar esa sinxronlanadi.";
  if (status === 'running') return 'Sinxronlanmoqda…';
  if (status === 'error') return "Oxirgi sinxronlash bajarilmadi. Qayta urinish uchun Qaydlar bo'limida ro'yxatni pastga torting.";
  if (!lastSyncAt) return "O'zgartirish kiritsangiz, qaydlar sinxronlanadi.";
  return `Oxirgi sinxronlash: ${formatRelativeTime(lastSyncAt, 'long').toLowerCase()}.`;
}

export default function PrivacyDataScreen() {
  const config = useConfigStore((s) => s.config);
  const updateConfig = useConfigStore((s) => s.updateConfig);
  const user = useAuthStore((s) => s.user);
  const isGuest = useAuthStore((s) => s.isGuest);
  const { status, lastSyncAt, subscriptionRequired, policyBlocked } = useSyncStore();
  const usage = useUsageStore((s) => s.usage);
  const loadUsage = useUsageStore((s) => s.load);
  const voiceProfiles = useNotesStore((s) => s.voiceProfiles);
  const loadVoiceProfiles = useNotesStore((s) => s.loadVoiceProfiles);
  const deleteAllVoiceProfiles = useNotesStore((s) => s.deleteAllVoiceProfiles);
  const cloudBackupEnabled = config?.cloudBackupEnabled ?? true;
  const usageAnalytics = config?.usageAnalyticsEnabled ?? true;
  const signedIn = !!user && !isGuest;
  const paidPlanRequired = usage ? !usage.isSubscribed : subscriptionRequired;

  // Re-render every 30s so "Last synced X ago" stays current without waiting
  // on the next sync event.
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), RELATIVE_TICK_MS);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    loadVoiceProfiles();
  }, [loadVoiceProfiles]);

  useEffect(() => {
    if (signedIn) loadUsage();
  }, [signedIn, loadUsage]);

  const handleToggleCloudBackup = useCallback(
    (value: boolean) => {
      safeHaptics('light');
      updateConfig({ cloudBackupEnabled: value });
      // Toggling ON: kick a sync immediately so the user sees confirmation
      // that things are flowing. Toggling OFF is lazy — the engine guards
      // future triggers; no action needed here.
      if (value) requestSync('manual');
    },
    [updateConfig],
  );

  const handleToggleAnalytics = useConfigToggle('usageAnalyticsEnabled');
  const handleDeleteVoiceProfiles = useCallback(() => {
    confirmDestructive(
      "Ovoz profillarini o'chirish",
      "Shu qurilmadagi barcha ovoz profillari butunlay o'chiriladi. Eski transkriptlardagi gapiruvchi nomlari saqlanib qoladi.",
      () => {
        safeHaptics('warning');
        deleteAllVoiceProfiles();
      },
    );
  }, [deleteAllVoiceProfiles]);

  const description = describeSyncStatus(
    cloudBackupEnabled,
    signedIn,
    status,
    lastSyncAt,
    paidPlanRequired,
    policyBlocked,
  );

  return (
    <SettingsScreen>
      {signedIn ? (
        <SettingsSection title="Sinxronlash">
          <SettingsRow
            iconStyle="line"
            icon="icloud"
            mdIcon="Cloud"
            title="Bulutga zaxira nusxa"
            description={description}
            rightElement={
              <SettingsSwitch value={cloudBackupEnabled} onValueChange={handleToggleCloudBackup} />
            }
            showChevron={false}
          />
        </SettingsSection>
      ) : null}

      <SettingsSection title="Ma'lumotlar">
        <SettingsRow
          iconStyle="line"
          icon="chart.bar"
          mdIcon="BarChart3"
          title="Foydalanish statistikasi"
          description="Gapla'ni yaxshilash uchun ishlash ko'rsatkichlari va ilovadan foydalanish statistikasini yuboring. iOS'da Apple'ning Kuzatuv ruxsati reklama bo'yicha ma'lumotni alohida cheklaydi. Transkript matni hech qachon yuborilmaydi."
          rightElement={
            <SettingsSwitch value={usageAnalytics} onValueChange={handleToggleAnalytics} />
          }
          showChevron={false}
        />
        <SettingsRow
          iconStyle="line"
          icon="text.cursor"
          mdIcon="TextCursor"
          title="Ovozli yordamchiga yuboriladigan matn"
          description="Ovozli yordamchidan foydalanganda belgilangan matn doim bulut xizmatiga yuboriladi. «Kursor atrofidagi matnni yuborish» yoqilgan bo'lsa, kursor atrofidagi matn ham yuboriladi. Bu sozlama odatda o'chiq, uni Ovozli yordamchi sozlamalarida o'zgartirish mumkin."
          showChevron={false}
        />
        <SettingsRow
          iconStyle="line"
          icon="waveform"
          mdIcon="AudioLines"
          title="Ovoz profillarini o'chirish"
          description={
            voiceProfiles.length === 0
              ? "Shu qurilmada ovoz profili yo'q."
              : `${voiceProfiles.length} ta lokal ovoz profili o'chiriladi.`
          }
          destructive
          onPress={voiceProfiles.length > 0 ? handleDeleteVoiceProfiles : undefined}
          showChevron={false}
        />
      </SettingsSection>
    </SettingsScreen>
  );
}
