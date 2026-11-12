export type LanguageCode = string;

export type Language = {
  code: LanguageCode;
  label: string;
  flag: string;
};

export const DEFAULT_LANGUAGE: LanguageCode = 'auto';

// Gapla: names are shown in Uzbek and sorted by that name; 'auto' stays first (getLanguage falls back to it).
export const LANGUAGES: Language[] = [
  { code: 'auto', label: 'Avtomatik aniqlash', flag: '🌐' },
  { code: 'af', label: 'Afrikaans tili', flag: '🇿🇦' },
  { code: 'ar', label: 'Arab tili', flag: '🇸🇦' },
  { code: 'hy', label: 'Arman tili', flag: '🇦🇲' },
  { code: 'be', label: 'Belarus tili', flag: '🇧🇾' },
  { code: 'bg', label: 'Bolgar tili', flag: '🇧🇬' },
  { code: 'bs', label: 'Bosniya tili', flag: '🇧🇦' },
  { code: 'cs', label: 'Chex tili', flag: '🇨🇿' },
  { code: 'da', label: 'Daniya tili', flag: '🇩🇰' },
  { code: 'et', label: 'Eston tili', flag: '🇪🇪' },
  { code: 'fi', label: 'Fin tili', flag: '🇫🇮' },
  { code: 'fa', label: 'Fors tili', flag: '🇮🇷' },
  { code: 'fr', label: 'Fransuz tili', flag: '🇫🇷' },
  { code: 'gl', label: 'Galisiya tili', flag: '🇪🇸' },
  { code: 'hi', label: 'Hind tili', flag: '🇮🇳' },
  { code: 'id', label: 'Indonez tili', flag: '🇮🇩' },
  { code: 'en-US', label: 'Ingliz tili (AQSh)', flag: '🇺🇸' },
  { code: 'en-GB', label: 'Ingliz tili (Britaniya)', flag: '🇬🇧' },
  { code: 'is', label: 'Island tili', flag: '🇮🇸' },
  { code: 'es', label: 'Ispan tili', flag: '🇪🇸' },
  { code: 'it', label: 'Italyan tili', flag: '🇮🇹' },
  { code: 'he', label: 'Ivrit tili', flag: '🇮🇱' },
  { code: 'kn', label: 'Kannada tili', flag: '🇮🇳' },
  { code: 'ca', label: 'Katalan tili', flag: '🇪🇸' },
  { code: 'ko', label: 'Koreys tili', flag: '🇰🇷' },
  { code: 'lv', label: 'Latish tili', flag: '🇱🇻' },
  { code: 'lt', label: 'Litva tili', flag: '🇱🇹' },
  { code: 'mk', label: 'Makedon tili', flag: '🇲🇰' },
  { code: 'ms', label: 'Malay tili', flag: '🇲🇾' },
  { code: 'mt', label: 'Malta tili', flag: '🇲🇹' },
  { code: 'mi', label: 'Maori tili', flag: '🇳🇿' },
  { code: 'mr', label: 'Marathi tili', flag: '🇮🇳' },
  { code: 'de', label: 'Nemis tili', flag: '🇩🇪' },
  { code: 'ne', label: 'Nepal tili', flag: '🇳🇵' },
  { code: 'nl', label: 'Niderland tili', flag: '🇳🇱' },
  { code: 'no', label: 'Norveg tili', flag: '🇳🇴' },
  { code: 'az', label: 'Ozarbayjon tili', flag: '🇦🇿' },
  { code: 'pl', label: 'Polyak tili', flag: '🇵🇱' },
  { code: 'pt', label: 'Portugal tili', flag: '🇵🇹' },
  { code: 'kk', label: 'Qozoq tili', flag: '🇰🇿' },
  { code: 'ro', label: 'Rumin tili', flag: '🇷🇴' },
  { code: 'ru', label: 'Rus tili', flag: '🇷🇺' },
  { code: 'sr', label: 'Serb tili', flag: '🇷🇸' },
  { code: 'sv', label: 'Shved tili', flag: '🇸🇪' },
  { code: 'sk', label: 'Slovak tili', flag: '🇸🇰' },
  { code: 'sl', label: 'Sloven tili', flag: '🇸🇮' },
  { code: 'sw', label: 'Suaxili tili', flag: '🇰🇪' },
  { code: 'tl', label: 'Tagalog tili', flag: '🇵🇭' },
  { code: 'ta', label: 'Tamil tili', flag: '🇮🇳' },
  { code: 'th', label: 'Tay tili', flag: '🇹🇭' },
  { code: 'tr', label: 'Turk tili', flag: '🇹🇷' },
  { code: 'cy', label: 'Uels tili', flag: '🏴󠁧󠁢󠁷󠁬󠁳󠁿' },
  { code: 'uk', label: 'Ukrain tili', flag: '🇺🇦' },
  { code: 'ur', label: 'Urdu tili', flag: '🇵🇰' },
  { code: 'hu', label: 'Venger tili', flag: '🇭🇺' },
  { code: 'vi', label: 'Vyetnam tili', flag: '🇻🇳' },
  { code: 'zh-TW', label: "Xitoy tili (an'anaviy)", flag: '🇹🇼' },
  { code: 'zh-CN', label: 'Xitoy tili (soddalashgan)', flag: '🇨🇳' },
  { code: 'hr', label: 'Xorvat tili', flag: '🇭🇷' },
  { code: 'ja', label: 'Yapon tili', flag: '🇯🇵' },
  { code: 'el', label: 'Yunon tili', flag: '🇬🇷' },
];

const BY_CODE = new Map(LANGUAGES.map((l) => [l.code, l]));

export function getLanguage(code: LanguageCode | undefined): Language {
  if (!code) return LANGUAGES[0];
  return BY_CODE.get(code) ?? LANGUAGES[0];
}

/** Uzbek display name for a registry code, or the fallback when the app list has no such code. */
export function languageLabel(code: LanguageCode, fallback: string): string {
  return BY_CODE.get(code)?.label ?? fallback;
}

// Whisper / OpenAI want the base ISO-639 code (no region). 'auto' becomes
// undefined so the upstream API auto-detects.
export function toApiLanguage(code: LanguageCode | undefined): string | undefined {
  if (!code || code === 'auto') return undefined;
  return code.split('-')[0];
}
