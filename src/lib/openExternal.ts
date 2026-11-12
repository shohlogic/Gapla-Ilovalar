import { Alert, Linking, Platform } from 'react-native';

/**
 * Hands `url` to the default browser. Resolves `true` when the OS took it and
 * `false` when it could not be opened, allowing callers to unwind any state
 * armed for an external round trip.
 */
export async function openExternal(url: string, fallbackMessage?: string): Promise<boolean> {
  try {
    const supported = await Linking.canOpenURL(url);
    if (supported) {
      await Linking.openURL(url);
      return true;
    }
  } catch {
    // fall through
  }

  Alert.alert("Ochib bo'lmadi", fallbackMessage ?? `${url} manzilini ochib bo'lmadi.`, [
    { text: 'OK', style: 'cancel' },
  ]);
  return false;
}

export function openMail(email: string, subject: string): Promise<boolean> {
  const encoded = encodeURIComponent(subject);
  const url = `mailto:${email}?subject=${encoded}`;
  const fallback =
    Platform.OS === 'ios'
      ? `Pochta hisobi sozlanmagan. Bizga ${email} manziliga yozing.`
      : `Pochta ilovasi topilmadi. Bizga ${email} manziliga yozing.`;
  return openExternal(url, fallback);
}
