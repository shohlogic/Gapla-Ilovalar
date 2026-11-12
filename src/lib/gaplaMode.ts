// Gapla: the cleanup mode (Tez, O'rta, Sekin). Faster is quicker, slower is better quality.
// The app and the keyboard share it through the App Group key below; the keyboard's menu
// (KeyboardViewController.swift, gaplaModeMenuItems) writes the same key.
// Which model each mode runs is decided by the Gapla bridge, not by the app.
import { useCallback, useEffect, useState } from 'react';
import { ActionSheetIOS, AppState } from 'react-native';
import { AppGroupStorage } from '../../modules/app-group-storage/src';

// Lokal runs RubaiSTT on the Gapla server (~22 s for a short clip against 1–2 s for the others).
// Requests already wait up to 5 minutes (NativeProviderTransport, 300 s idle); the keyboard
// waits 5 minutes in this mode instead of 2 (KeyboardViewController, waitForTranscript).
export type GaplaMode = 'tez' | 'orta' | 'sekin' | 'lokal';

export const GAPLA_MODES: ReadonlyArray<{ id: GaplaMode; title: string }> = [
  { id: 'tez', title: 'Tez' },
  { id: 'orta', title: "O'rta" },
  { id: 'sekin', title: 'Sekin' },
  { id: 'lokal', title: 'Lokal' },
];

export const GAPLA_DEFAULT_MODE: GaplaMode = 'orta';
const GAPLA_MODE_KEY = 'gapla_rejim';
const GAPLA_BRIDGE_HOST = 'gapla.xaliljonov.uz';

/** The name sent in the request's `model` field. Changing the naming is this one line. */
export function gaplaModelName(mode: GaplaMode): string {
  return `gapla-${mode}`;
}

function isGaplaMode(value: unknown): value is GaplaMode {
  return GAPLA_MODES.some((mode) => mode.id === value);
}

export function getGaplaMode(): GaplaMode {
  try {
    const saved = AppGroupStorage.getItem(GAPLA_MODE_KEY);
    return isGaplaMode(saved) ? saved : GAPLA_DEFAULT_MODE;
  } catch {
    return GAPLA_DEFAULT_MODE;
  }
}

const listeners = new Set<(mode: GaplaMode) => void>();

export function setGaplaMode(mode: GaplaMode): void {
  AppGroupStorage.setItem(GAPLA_MODE_KEY, mode);
  listeners.forEach((listener) => listener(mode));
}

export function gaplaModeTitle(mode: GaplaMode): string {
  return GAPLA_MODES.find((item) => item.id === mode)?.title ?? mode;
}

/** True when the endpoint is the Gapla bridge, the only server that understands the modes. */
export function isGaplaBridge(endpoint: string): boolean {
  try {
    return new URL(endpoint).hostname === GAPLA_BRIDGE_HOST;
  } catch {
    return false;
  }
}

/** The current mode for a screen; follows changes made here and, on return, in the keyboard. */
export function useGaplaMode(): [GaplaMode, (mode: GaplaMode) => void] {
  const [mode, setMode] = useState<GaplaMode>(getGaplaMode);
  useEffect(() => {
    const listener = (next: GaplaMode): void => setMode(next);
    listeners.add(listener);
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') setMode(getGaplaMode());
    });
    return (): void => {
      listeners.delete(listener);
      subscription.remove();
    };
  }, []);
  const choose = useCallback((next: GaplaMode): void => setGaplaMode(next), []);
  return [mode, choose];
}

/** iOS action sheet with the three modes, for settings rows. */
export function pickGaplaMode(current: GaplaMode, onPick: (mode: GaplaMode) => void): void {
  ActionSheetIOS.showActionSheetWithOptions(
    {
      title: 'Tozalash rejimi',
      message:
        'Tez — tezroq javob, Sekin — sifatliroq matn. Lokal — serverdagi RubaiSTT, javob ~20 soniya.',
      options: [...GAPLA_MODES.map((item) => (item.id === current ? `✓ ${item.title}` : item.title)), 'Bekor'],
      cancelButtonIndex: GAPLA_MODES.length,
    },
    (index) => {
      const picked = GAPLA_MODES[index];
      if (picked) onPick(picked.id);
    },
  );
}
