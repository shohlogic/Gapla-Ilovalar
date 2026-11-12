import React, { useCallback, useEffect } from 'react';
import { View } from 'react-native';
import { Text } from '@/components/ui/Text';
import { router } from 'expo-router';
import { SettingsRow, SettingsSection } from '@/components/ui/SettingsSection';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { PlanBadge } from '@/components/ui/PlanBadge';
import { GradientGlassSurface } from '@/components/ui/GradientGlassSurface';
import { useAuthStore } from '@/store/useAuthStore';
import { useUsageStore } from '@/store/useUsageStore';
import { confirmAccountDeletion, confirmDestructive } from '@/lib/alerts';
import { safeHaptics } from '@/lib/utils';
import { getAccountDisplay } from '@/lib/accountDisplay';

export default function ProfileScreen() {
  const { user, isGuest, signOut, deleteAccount } = useAuthStore();
  // See AccountScreen: an anonymous session gets Create Account, not Sign Out
  // (which would revoke it) or Delete Account (which the API refuses).
  const isAnonymous = user?.isAnonymous === true;
  const usage = useUsageStore((s) => s.usage);
  const loadUsage = useUsageStore((s) => s.load);

  useEffect(() => {
    if (user) loadUsage();
  }, [user, loadUsage]);

  const handleSignOut = useCallback(() => {
    confirmDestructive(
      user ? 'Hisobdan chiqish' : 'Mehmon rejimidan chiqish',
      user ? 'Hisobdan chiqasizmi?' : 'Kirish sahifasiga qaytasizmi?',
      async () => {
        safeHaptics('warning');
        await signOut();
      },
      { destructiveLabel: user ? 'Chiqish' : 'Davom etish' },
    );
  }, [signOut, user]);

  const handleDeleteAccount = useCallback(() => {
    if (!user) return;
    confirmAccountDeletion(deleteAccount);
  }, [deleteAccount, user]);

  const { initials, name: displayName } = getAccountDisplay(
    user,
    isGuest,
    'Faqat lokal qaydlar va shaxsiy jarayonlar',
  );
  const email = user?.email;

  return (
    <SettingsScreen>
      <View className="items-center px-6 pb-6 pt-4">
        <View
          style={{ borderCurve: 'continuous' }}
          className="h-20 w-20 items-center justify-center overflow-hidden rounded-full bg-brand"
        >
          <GradientGlassSurface shape="circle" />
          <Text className="text-[28px] font-semibold text-white tracking-tight">{initials}</Text>
        </View>
        <View className="mt-3 flex-row items-center gap-2">
          <Text
            accessibilityRole="header"
            className="shrink text-[22px] font-semibold text-label tracking-tight"
          >
            {displayName}
          </Text>
          {user ? <PlanBadge usage={usage} /> : null}
        </View>
        {email ? (
          <Text className="mt-1 text-[15px] text-secondaryLabel">{email}</Text>
        ) : (
          <Text className="mt-1 text-[15px] text-secondaryLabel">
            Faqat lokal qaydlar va shaxsiy jarayonlar
          </Text>
        )}
      </View>

      {/* Gapla: no OpenWhispr accounts — no Sign In or Create Account; an old session can sign out. */}
      {user ? (
        <SettingsSection>
          <SettingsRow
            iconStyle="line"
            icon="rectangle.portrait.and.arrow.right"
            mdIcon="LogOut"
            title="Hisobdan chiqish"
            destructive
            onPress={handleSignOut}
            showChevron={false}
          />
        </SettingsSection>
      ) : null}

      {user && !isAnonymous ? (
        <SettingsSection>
          <SettingsRow
            iconStyle="line"
            icon="trash"
            mdIcon="Trash2"
            title="Hisobni o'chirib tashlash"
            destructive
            onPress={handleDeleteAccount}
            showChevron={false}
          />
        </SettingsSection>
      ) : null}
    </SettingsScreen>
  );
}
