import React, { useCallback, useEffect, useRef } from 'react';
import { gaplaModeTitle, pickGaplaMode, useGaplaMode } from '@/lib/gaplaMode';
import { Alert, Platform, View, Pressable } from 'react-native';
import { Text } from '@/components/ui/Text';
import Constants from 'expo-constants';
import * as Application from 'expo-application';
import { router, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { SettingsRow, SettingsSection } from '@/components/ui/SettingsSection';
import { SettingsScreen } from '@/components/ui/SettingsScreen';
import { PlanBadge } from '@/components/ui/PlanBadge';
import { UsageMeter } from '@/components/ui/UsageMeter';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { GlassBackButton } from '@/components/ui/GlassBackButton';
import { TabScreenHeader } from '@/components/ui/TabScreenHeader';
import { GradientGlassSurface } from '@/components/ui/GradientGlassSurface';
import { useAuthStore } from '@/store/useAuthStore';
import { useUsageStore } from '@/store/useUsageStore';
import { useOnboardingStore } from '@/store/useOnboardingStore';
import type { UsageInfo } from '@/data/remote/usageApi';
import { createStripeBillingPortalSession } from '@/data/remote/billingApi';
import { ApiError } from '@/lib/apiClient';
import { openExternal } from '@/lib/openExternal';
import { getAppStorefrontCountryCode, showAppStoreManageSubscriptions } from '@/lib/revenuecat';
import { confirmAccountDeletion, confirmDestructive } from '@/lib/alerts';
import { safeHaptics } from '@/lib/utils';
import { iosColor } from '@/config/colors';
import { getAccountDisplay } from '@/lib/accountDisplay';
import { useSuperwallGate } from '@/hooks/useSuperwallGate';
import { useAffiliateStore } from '@/store/useAffiliateStore';
import { getAffiliateClientConfig } from '@/lib/affiliateLink';
import { loadAffiliateOffer, type AffiliateOffer } from '@/lib/affiliateOffer';
import { AccountCreatorLink, type CreatorOfferResult } from '@/components/AccountCreatorLink';
import { SUPERWALL_PLACEMENTS } from '@/lib/superwall';

/** Gapla: the installed build, e.g. «1.0.0 · yig'ma 47». Every cloud build gets its own number (the marketing version
 *  stays 1.0.0 between releases), so the owner can see which build is on the phone after an install. */
function installedVersionLabel(): string {
  const version = Application.nativeApplicationVersion ?? Constants.expoConfig?.version;
  const build = Application.nativeBuildVersion;
  if (!version) return "noma'lum";
  return build ? `${version} · yig'ma ${build}` : version;
}

const MUTED_ICON_BG = iosColor('systemGray2');
const SHOW_GOOGLE_CALENDAR_INTEGRATION = Platform.OS === 'ios';
const APP_STORE_SUBSCRIPTIONS_URL = 'itms-apps://apps.apple.com/account/subscriptions';
const US_APP_STORE_COUNTRY_CODE = 'USA';
const WEB_SUBSCRIPTION_SUPPORT_COPY =
  "Gapla'da pullik tarif yo'q, shuning uchun bu yerda o'zgartiradigan narsa yo'q.";

type SubscriptionManagementProvider = 'app-store' | 'web' | 'unknown';

function getSubscriptionManagementProvider(usage: UsageInfo): SubscriptionManagementProvider {
  const sources = usage.entitlementSources;
  if (!sources) return 'unknown';
  if (sources.provider) return 'app-store';
  if (sources.personal || sources.workspaceIds.length > 0) return 'web';
  return 'unknown';
}

function showWebSubscriptionSupport(): void {
  Alert.alert('Obunani boshqarish', WEB_SUBSCRIPTION_SUPPORT_COPY, [{ text: 'Tayyor', style: 'cancel' }]);
}

async function openAppStoreManagement(): Promise<void> {
  if (await showAppStoreManageSubscriptions()) return;
  await openExternal(
    APP_STORE_SUBSCRIPTIONS_URL,
    "Xaridlarni boshqarish uchun Sozlamalar > Apple hisobi > Obunalar bo'limini oching.",
  );
}

async function openBillingManagement(usage: UsageInfo): Promise<void> {
  const provider = getSubscriptionManagementProvider(usage);
  if (provider === 'app-store') {
    await openAppStoreManagement();
    return;
  }
  if (provider === 'unknown') {
    showWebSubscriptionSupport();
    return;
  }

  const storefrontCountryCode = await getAppStorefrontCountryCode();
  if (storefrontCountryCode !== US_APP_STORE_COUNTRY_CODE) {
    showWebSubscriptionSupport();
    return;
  }

  let portalUrl: string;
  try {
    portalUrl = await createStripeBillingPortalSession();
  } catch (error) {
    if (error instanceof ApiError && error.status >= 400 && error.status < 500) {
      showWebSubscriptionSupport();
      return;
    }
    Alert.alert("To'lov sahifasi ochilmadi", "Birozdan keyin qayta urinib ko'ring.");
    return;
  }

  useUsageStore.getState().beginBillingSession();
  const didOpenPortal = await openExternal(portalUrl, "To'lov sahifasini ochib bo'lmadi.");
  if (!didOpenPortal) useUsageStore.getState().endBillingSession();
}

async function openGrantedBillingManagement(usage: UsageInfo): Promise<void> {
  if (usage.isSubscribed) {
    await openBillingManagement(usage);
    return;
  }

  if (Platform.OS === 'ios') {
    await openAppStoreManagement();
    return;
  }

  showWebSubscriptionSupport();
}

export default function AccountScreen() {
  const params = useLocalSearchParams<{ superwallPlacement?: string }>();
  const { user, sessionCookie, isGuest, signOut, deleteAccount } = useAuthStore();
  // An anonymous onboarding session: Sign Out would revoke it (and the notes
  // and purchase it carries) and the API refuses to delete it, so the one
  // account action it needs is creating the account.
  const isAnonymous = user?.isAnonymous === true;
  const usage = useUsageStore((s) => s.usage);
  const loadUsage = useUsageStore((s) => s.load);
  const resetOnboarding = useOnboardingStore((state) => state.reset);
  // Gapla (G38, 2026-11-11): the keyboard has one Turkish-style layout with ç ğ ş ö, so the
  // «Klaviatura alifbosi» switch that picked o' g' or ö ğ ş ç is gone.
  const [gaplaMode, setGaplaModeChoice] = useGaplaMode();
  const { register: registerSuperwallGate, isConfigured: superwallConfigured } = useSuperwallGate();
  const handledBillingIntentRef = useRef<string | null>(null);
  const billingContextRef = useRef({
    userId: user?.id,
    sessionCookie,
    active: true,
    generation: 0,
  });
  billingContextRef.current.userId = user?.id;
  billingContextRef.current.sessionCookie = sessionCookie;
  const affiliatePendingRef = useRef(false);
  const billingRegistrationRef = useRef<AbortController | null>(null);
  useFocusEffect(
    useCallback(() => {
      billingContextRef.current.active = true;
      return () => {
        billingContextRef.current.active = false;
        billingContextRef.current.generation += 1;
        billingRegistrationRef.current?.abort();
      };
    }, []),
  );

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

  const handleBillingPress = useCallback(
    async (intent: 'plans' | 'creator' = 'plans'): Promise<CreatorOfferResult> => {
      if (affiliatePendingRef.current) return 'cancelled';
      affiliatePendingRef.current = true;
      try {
        const context = { ...billingContextRef.current };
        const isCurrent = () =>
          billingContextRef.current.active &&
          billingContextRef.current.generation === context.generation &&
          useAuthStore.getState().user?.id === context.userId &&
          useAuthStore.getState().sessionCookie === context.sessionCookie;
        let currentUsage = useUsageStore.getState().usage;
        if (user && !currentUsage) {
          const loadResult = await loadUsage(true);
          currentUsage = loadResult.usage ?? useUsageStore.getState().usage;
          if (!isCurrent()) return 'cancelled';
          if (!currentUsage) {
            Alert.alert("To'lov ma'lumoti yuklanmadi", "Birozdan keyin qayta urinib ko'ring.");
            return 'cancelled';
          }
        }

        const managementUsage = currentUsage;
        if (
          intent === 'creator' &&
          (!currentUsage || currentUsage.isSubscribed || !useAffiliateStore.getState().link.trim())
        )
          return 'cancelled';
        if (
          !currentUsage?.isSubscribed &&
          intent === 'creator' &&
          !(await useAffiliateStore.getState().prepare(isCurrent))
        )
          return 'invalid';
        if (!isCurrent()) return 'cancelled';
        let creatorOffer: AffiliateOffer | undefined;
        if (!currentUsage?.isSubscribed && intent === 'creator') {
          // Allocating stock for a paywall that can't open would waste the offer.
          if (!superwallConfigured) return 'unavailable';
          creatorOffer = (await loadAffiliateOffer(isCurrent)) ?? undefined;
          if (!isCurrent()) return 'cancelled';
          if (!creatorOffer) return 'unavailable';
        }
        if (!isCurrent()) return 'cancelled';

        const registration = new AbortController();
        billingRegistrationRef.current = registration;
        let presented = false;
        await registerSuperwallGate({
          signal: registration.signal,
          onPresent: () => {
            presented = true;
          },
          placement: SUPERWALL_PLACEMENTS.accountBillingOpen,
          creatorOffer,
          requiresAccount: creatorOffer ? false : undefined,
          params: currentUsage
            ? {
                plan: currentUsage.plan,
                status: currentUsage.status,
                isSubscribed: currentUsage.isSubscribed,
                isTrial: currentUsage.isTrial,
              }
            : undefined,
          onAccessGrantedWithoutPurchase:
            managementUsage && !creatorOffer
              ? () => {
                  openGrantedBillingManagement(managementUsage).catch(() => {});
                }
              : undefined,
          onPurchaseComplete: (completion) => {
            router.replace({
              pathname: '/(tabs)/(record)',
              params: { proCompletion: completion },
            });
          },
        });
        // A skipped or failed paywall never showed the offer, so keep the regular plans in reach.
        if (!creatorOffer) return 'cancelled';
        return presented ? 'shown' : 'unavailable';
      } finally {
        affiliatePendingRef.current = false;
      }
    },
    [loadUsage, registerSuperwallGate, superwallConfigured, user],
  );

  useEffect(() => {
    if (!user || params.superwallPlacement !== SUPERWALL_PLACEMENTS.accountBillingOpen) return;
    const intentKey = `${user.id}:${params.superwallPlacement}`;
    if (handledBillingIntentRef.current === intentKey) return;
    handledBillingIntentRef.current = intentKey;
    handleBillingPress().catch(() => {});
  }, [handleBillingPress, params.superwallPlacement, user]);

  const {
    initials,
    name: accountName,
    subtitle: accountSubtitle,
  } = getAccountDisplay(user, isGuest);

  return (
    <View className="flex-1 bg-systemBackground">
      <TabScreenHeader
        title="Hisob"
        left={<GlassBackButton fallbackRoute="/(tabs)/(record)" />}
      />
      <SettingsScreen automaticallyAdjustKeyboardInsets keyboardShouldPersistTaps="handled">
        {(user || isGuest) && (
          <Pressable
            onPress={() => router.push('/(account)/profile')}
            className="active:opacity-70"
          >
            <View
              style={{ borderCurve: 'continuous' }}
              className="mx-4 mb-5 flex-row items-center gap-3 rounded-[14px] p-3.5"
            >
              <View className="h-11 w-11 items-center justify-center overflow-hidden rounded-full bg-brand">
                <GradientGlassSurface shape="circle" />
                <Text className="text-[17px] font-semibold text-white tracking-tight">
                  {isGuest ? 'G' : initials}
                </Text>
              </View>
              <View className="flex-1">
                <View className="flex-row items-center gap-2">
                  <Text numberOfLines={1} className="shrink text-[17px] font-semibold text-label">
                    {accountName}
                  </Text>
                  {user ? <PlanBadge usage={usage} /> : null}
                </View>
                <Text numberOfLines={1} className="mt-0.5 text-sm text-secondaryLabel">
                  {accountSubtitle}
                </Text>
              </View>
              <SystemIcon
                name="chevron.right"
                mdName="ChevronRight"
                size={13}
                color="tertiaryLabel"
              />
            </View>
          </Pressable>
        )}

        {user && usage ? (
          <SettingsSection title="Foydalanish">
            <UsageMeter usage={usage} />
          </SettingsSection>
        ) : null}

        {/* Gapla: OpenWhispr's referral program, plans and billing, support e-mail and its site's
            terms and privacy links are removed; Licenses & Attribution stays. */}
        <SettingsSection title="Sozlamalar">
          <SettingsRow
            iconStyle="line"
            icon="brain.head.profile"
            mdIcon="Brain"
            title="AI modellari"
            onPress={() => router.push('/(account)/ai-models')}
          />
          <SettingsRow
            iconStyle="line"
            icon="gauge.with.dots.needle.50percent"
            mdIcon="Gauge"
            title="Tozalash rejimi"
            subtitle={`${gaplaModeTitle(gaplaMode)} · Tez — tezroq, Sekin — sifatliroq`}
            onPress={() => pickGaplaMode(gaplaMode, setGaplaModeChoice)}
          />
          <SettingsRow
            iconStyle="line"
            icon="slider.horizontal.3"
            mdIcon="SlidersHorizontal"
            title="Afzalliklar"
            onPress={() => router.push('/(account)/preferences')}
          />
          <SettingsRow
            iconStyle="line"
            icon="lock.shield"
            mdIcon="ShieldCheck"
            title="Maxfiylik va ma'lumotlar"
            onPress={() => router.push('/(account)/privacy')}
          />
        </SettingsSection>

        {user && SHOW_GOOGLE_CALENDAR_INTEGRATION ? (
          <SettingsSection title="Integratsiyalar">
            <SettingsRow
              iconStyle="line"
              icon="calendar"
              mdIcon="CalendarDays"
              title="Google Kalendar"
              onPress={() => router.push('/(account)/google-calendar')}
            />
          </SettingsSection>
        ) : null}

        <SettingsSection title="Tanishuv">
          <SettingsRow
            icon="arrow.counterclockwise"
            mdIcon="RotateCcw"
            iconBg={MUTED_ICON_BG}
            title="Tanishuvni qayta ko'rsatish"
            subtitle="Ilova keyingi safar ochilganda tanishuv qaytadan ko'rsatiladi"
            onPress={() => {
              confirmDestructive(
                "Tanishuv qayta ko'rsatilsinmi?",
                "Ilovani keyingi safar ochganingizda tanishuv qadamlari yana ko'rsatiladi.",
                async () => {
                  await resetOnboarding();
                  Alert.alert('Tayyor', "Tanishuvni ko'rish uchun ilovani qayta ishga tushiring.");
                },
                { destructiveLabel: "Qayta ko'rsatish" },
              );
            }}
            showChevron={false}
          />
        </SettingsSection>

        <SettingsSection title="Ilova haqida">
          <SettingsRow
            iconStyle="line"
            icon="info.circle"
            mdIcon="Info"
            title="Versiya"
            subtitle={installedVersionLabel()}
            showChevron={false}
          />
          <SettingsRow
            iconStyle="line"
            icon="text.badge.checkmark"
            mdIcon="ScrollText"
            title="Litsenziyalar va mualliflar"
            onPress={() => router.push('/(account)/licenses')}
          />
        </SettingsSection>

        {/* Gapla: no OpenWhispr accounts — no Sign In or Create Account; an old session can sign out. */}
        {user ? (
          <SettingsSection borderless>
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
          <SettingsSection borderless>
            <SettingsRow
              iconStyle="line"
              icon="trash"
              mdIcon="Trash2"
              title="Hisobni o'chirib tashlash"
              destructive
              onPress={() => confirmAccountDeletion(deleteAccount)}
              showChevron={false}
            />
          </SettingsSection>
        ) : null}
      </SettingsScreen>
    </View>
  );
}
