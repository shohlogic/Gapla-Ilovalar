import { Alert } from 'react-native';
import { router } from 'expo-router';
import { isAccountRequiredError } from '@/lib/accountRequiredError';
import { useAuthStore } from '@/store/useAuthStore';
import { useProcessingModeStore } from '@/store/useProcessingModeStore';
import type { AuthUser } from '@/lib/authClient';
import type { ProcessingMode } from '@/types';

// Deliberately `!user`, not requiresRealAccount: cloud transcription is exactly
// what an anonymous onboarding session exists to do, and the API leaves
// /api/transcribe ungated for it.
export function accountRequiredForCloud(user: AuthUser | null): boolean {
  return !user;
}

/**
 * True when the caller holds nothing the API would accept for a gated feature.
 * An anonymous onboarding session is a real session — it carries dictation and
 * the paywall — but every endpoint behind requireAccount refuses it with 403
 * ACCOUNT_REQUIRED, so for those it counts as no account at all.
 */
export function requiresRealAccount(user: AuthUser | null): boolean {
  return !user || Boolean(user.isAnonymous);
}

export function cloudModeRequiresAccount(mode: ProcessingMode, user: AuthUser | null): boolean {
  return mode === 'cloud' && accountRequiredForCloud(user);
}

// Cloud meetings run on the realtime token, which the API keeps behind a real
// account (unlike /api/transcribe), so an anonymous session records locally
// exactly as a guest does.
export function canRunCloudMeeting(user: AuthUser | null, mode: ProcessingMode): boolean {
  return mode !== 'private' && !requiresRealAccount(user);
}

// Gapla: `feature` is an Uzbek noun phrase that starts the sentence ('Yozish', 'Audio yuklash').
export function getCloudAccountRequiredMessage(feature: string, anonymous = false): string {
  const action = `${feature} bulutda ishlashi uchun ${anonymous ? 'hisob yarating' : 'hisobga kiring'}`;
  // Already in Private Mode, which is what turning it off asks Cloud for, so don't offer it back.
  return useProcessingModeStore.getState().activeMode === 'private'
    ? `${action}.`
    : `${action} yoki Hisob → AI modellari bo'limida Diktovkani «Qurilmada» rejimiga o'tkazing.`;
}

// For features with no local model (AI actions, AI chat): Private Mode is not
// an alternative, so don't suggest it as one.
export function getCloudOnlyAccountRequiredMessage(feature: string, anonymous = false): string {
  return `${feature} uchun ${anonymous ? 'hisob yarating' : 'hisobga kiring'}. Bu imkoniyat Lokal rejimda ham doim bulutdagi AI'dan foydalanadi.`;
}

export function showAccountRequiredAlert(feature: string, options?: { cloudOnly?: boolean }): void {
  // An anonymous onboarding session already has a user; what it lacks is an
  // account, and the Account screen has nothing to offer it. Send it straight
  // to sign-up instead of a screen whose only action would be Sign Out.
  const anonymous = useAuthStore.getState().user?.isAnonymous === true;
  const message = options?.cloudOnly
    ? getCloudOnlyAccountRequiredMessage(feature, anonymous)
    : getCloudAccountRequiredMessage(feature, anonymous);
  Alert.alert(anonymous ? 'Hisob yarating' : 'Hisobga kirish kerak', message, [
    { text: 'Bekor qilish', style: 'cancel' },
    anonymous
      ? { text: 'Hisob yaratish', onPress: () => router.push('/auth') }
      : { text: 'Hisob', onPress: () => router.push('/(account)') },
  ]);
}

/**
 * Backstop for a gated endpoint the client-side checks did not anticipate:
 * turns the API's 403 ACCOUNT_REQUIRED into the same prompt those checks show,
 * instead of letting a bare "HTTP 403" reach an alert. Returns whether it
 * handled the error, so callers can `if (handled) return;` before their own
 * generic error path.
 */
export function handleAccountRequiredError(
  error: unknown,
  feature: string,
  options?: { cloudOnly?: boolean },
): boolean {
  if (!isAccountRequiredError(error)) return false;
  showAccountRequiredAlert(feature, options);
  return true;
}
