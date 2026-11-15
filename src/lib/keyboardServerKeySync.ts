// Gapla (G8): the keyboard's shared clipboard talks to the Gapla server with the same key as
// dictation. The key stays in this app's Keychain (ProviderCredentials); this keeps a copy in the
// App Group's Keychain group, readable only by this app and its keyboard, and removes it when the
// key is removed. The keyboard reads it in GaplaClipboard.swift. The value is never logged.
import { AppState } from 'react-native';
import { isGaplaBridge } from '@/lib/gaplaMode';
import { useConfigStore } from '@/store/useConfigStore';
import {
  getProviderCredential,
  getProviderCredentialReference,
  subscribeProviderCredentialChanges,
} from '@/services/providers/ProviderCredentials';
import { AppGroupStorage } from '../../modules/app-group-storage/src';

// The dictation default in useConfigStore (GAPLA_BRIDGE.endpoint).
const GAPLA_BRIDGE_ENDPOINT = 'https://gapla.xaliljonov.uz/v1';

/** The Gapla server's API base (…/v1); the translator (src/lib/gaplaTarjima.ts) calls it too. */
export function bridgeEndpoint(): string {
  const dictation = useConfigStore.getState().config?.inference?.dictation;
  const endpoint = dictation?.providerId === 'custom' ? dictation.endpoint : undefined;
  return endpoint && isGaplaBridge(endpoint) ? endpoint : GAPLA_BRIDGE_ENDPOINT;
}

async function bridgeReference(): Promise<string> {
  return getProviderCredentialReference('custom', bridgeEndpoint());
}

/** The Gapla server key — the dictation key — or null when none is saved. Never logged. */
export async function gaplaServerKey(): Promise<string | null> {
  const credential = await getProviderCredential(await bridgeReference());
  const key = credential?.apiKey?.trim();
  return key ? key : null;
}

export async function syncKeyboardServerKey(): Promise<void> {
  try {
    const credential = await getProviderCredential(await bridgeReference());
    AppGroupStorage.setSharedServerKey(credential?.apiKey ?? null);
  } catch {
    // Unreadable now (e.g. before first unlock); the next launch or key change retries.
  }
}

/** Starts the mirror: now, on every key change, and each time the app comes forward. */
export function startKeyboardServerKeySync(): () => void {
  void syncKeyboardServerKey();
  const unsubscribe = subscribeProviderCredentialChanges((changed): void => {
    // Reads queue behind the change being written, so they see its result.
    if (changed === null) {
      void syncKeyboardServerKey();
      return;
    }
    void bridgeReference()
      .then((reference) => {
        if (reference === changed) void syncKeyboardServerKey();
      })
      .catch(() => undefined);
  });
  const subscription = AppState.addEventListener('change', (state) => {
    if (state === 'active') void syncKeyboardServerKey();
  });
  return (): void => {
    unsubscribe();
    subscription.remove();
  };
}
