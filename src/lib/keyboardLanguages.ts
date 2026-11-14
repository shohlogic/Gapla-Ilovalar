// Gapla (G58): the keyboard's languages — O'zbekcha, Русский, English, Türkçe. The app saves which
// are on in the App Group key below as "uz,ru,en,tr"; the keyboard reads it each time it comes up
// (KeyboardViewController.swift: KeyboardLanguage, KeyboardHandoffProvider.keyboardLanguages).
// Not saved yet: all four, the default. O'zbekcha is always on. The order is the order the
// keyboard's language key steps through them.
import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import { AppGroupStorage } from '../../modules/app-group-storage/src';

export type KeyboardLanguageId = 'uz' | 'ru' | 'en' | 'tr';

/** `label` is the keyboard's language key, `name` the language's own name (on the space bar too). */
type KeyboardLanguage = { id: KeyboardLanguageId; label: string; name: string };

export const KEYBOARD_LANGUAGES: ReadonlyArray<KeyboardLanguage> = [
  { id: 'uz', label: 'UZ', name: "O'zbekcha" },
  { id: 'ru', label: 'RU', name: 'Русский' },
  { id: 'en', label: 'EN', name: 'English' },
  { id: 'tr', label: 'TR', name: 'Türkçe' },
];

const KEYBOARD_LANGUAGES_KEY = 'gapla_klaviatura_tillari';
const ALL_IDS: KeyboardLanguageId[] = KEYBOARD_LANGUAGES.map((language) => language.id);

/** Known ids only, O'zbekcha always, in the key's order. */
function normalize(ids: ReadonlyArray<string>): KeyboardLanguageId[] {
  return ALL_IDS.filter((id) => id === 'uz' || ids.includes(id));
}

export function getKeyboardLanguages(): KeyboardLanguageId[] {
  try {
    const saved = AppGroupStorage.getItem(KEYBOARD_LANGUAGES_KEY);
    return saved === null ? [...ALL_IDS] : normalize(saved.split(',').map((id) => id.trim()));
  } catch {
    return [...ALL_IDS];
  }
}

const listeners = new Set<(ids: KeyboardLanguageId[]) => void>();

/** Turns a language on or off; O'zbekcha stays on whatever is asked. */
export function setKeyboardLanguageOn(id: KeyboardLanguageId, on: boolean): void {
  if (id === 'uz') return;
  const current = getKeyboardLanguages();
  const next = normalize(on ? [...current, id] : current.filter((item) => item !== id));
  AppGroupStorage.setItem(KEYBOARD_LANGUAGES_KEY, next.join(','));
  listeners.forEach((listener) => listener(next));
}

/** The language keys of `ids`, for a settings row: "UZ, RU, EN, TR". */
export function keyboardLanguageLabels(ids: ReadonlyArray<KeyboardLanguageId>): string {
  return KEYBOARD_LANGUAGES.filter((language) => ids.includes(language.id))
    .map((language) => language.label)
    .join(', ');
}

type SetKeyboardLanguageOn = (id: KeyboardLanguageId, on: boolean) => void;

/** The languages on, for a screen; follows changes made here and on returning to the app. */
export function useKeyboardLanguages(): [KeyboardLanguageId[], SetKeyboardLanguageOn] {
  const [ids, setIds] = useState<KeyboardLanguageId[]>(getKeyboardLanguages);
  useEffect(() => {
    const listener = (next: KeyboardLanguageId[]): void => setIds(next);
    listeners.add(listener);
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') setIds(getKeyboardLanguages());
    });
    return (): void => {
      listeners.delete(listener);
      subscription.remove();
    };
  }, []);
  const setOn = useCallback<SetKeyboardLanguageOn>(
    (id, on) => setKeyboardLanguageOn(id, on),
    [],
  );
  return [ids, setOn];
}
