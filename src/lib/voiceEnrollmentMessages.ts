import {
  VOICE_ENROLLMENT_LOW_SNR,
  VOICE_ENROLLMENT_LOW_SPEECH_RATIO,
  VOICE_ENROLLMENT_MULTIPLE_SPEAKERS,
  VOICE_ENROLLMENT_NO_MEANINGFUL_SPEAKER,
  VOICE_ENROLLMENT_NO_SPEECH,
  VOICE_ENROLLMENT_PROFILE_NOT_FOUND,
  VOICE_ENROLLMENT_SHORT_SPEECH,
  VoiceEnrollmentError,
} from '@/services/diarization/VoiceprintService';

/** Shown for failures we can't explain; callers report these so they can be diagnosed. */
export const VOICE_ENROLLMENT_UNEXPLAINED_FAILURE =
  "Ovozingizni tekshirishda xato yuz berdi. Qayta urinib ko'ring.";

/** Alert title and message for teaching your voice when you already have a profile. */
export const VOICE_ALREADY_TAUGHT_ALERT = [
  "Siz Gapla'ga ovozingizni allaqachon o'rgatgansiz",
  "Uni «Ovoz profillari» bo'limida oching va «Ovozni qayta o'rgatish» ni tanlang.",
] as const;

// The speech detector never sets its bar above -30 dB, so a voice whose loudest moment
// stays below this reads as pauses or too little speech. Measured: failed reads peaked
// at -22 to -24 dB, a normal read at -9 dB.
const QUIET_PEAK_DB = -18;

const LEVEL_FAILURES = new Set<string>([
  VOICE_ENROLLMENT_LOW_SPEECH_RATIO,
  VOICE_ENROLLMENT_SHORT_SPEECH,
  VOICE_ENROLLMENT_NO_MEANINGFUL_SPEAKER,
]);

const wasTooQuiet = (error: VoiceEnrollmentError): boolean => {
  const quality = error.quality;
  const peakDb = quality && !quality.ok ? quality.speechActivity?.peakDb : undefined;
  return peakDb !== undefined && peakDb < QUIET_PEAK_DB;
};

/** What to tell someone whose voice sample failed, in words they can act on. */
export function voiceEnrollmentFailureMessage(error: unknown): string {
  if (!(error instanceof VoiceEnrollmentError)) return VOICE_ENROLLMENT_UNEXPLAINED_FAILURE;
  const { code } = error;
  if (LEVEL_FAILURES.has(code) && wasTooQuiet(error)) {
    return 'Ovozingiz juda past eshitildi. Balandroq gapiring yoki telefonni yaqinroq tuting.';
  }
  switch (code) {
    case VOICE_ENROLLMENT_NO_SPEECH:
      return "Ovozingiz eshitilmadi. Mikrofonni hech narsa to'sib turmaganini tekshirib, qayta urinib ko'ring.";
    case VOICE_ENROLLMENT_SHORT_SPEECH:
      return "Ovozingiz yetarlicha eshitilmadi. Matnni oxirigacha o'qing.";
    case VOICE_ENROLLMENT_NO_MEANINGFUL_SPEAKER:
      return "Ovozingizni ajratib bo'lmadi. Telefonni yaqin tutib, matnni oxirigacha o'qing.";
    case VOICE_ENROLLMENT_LOW_SNR:
      return "Atrofda shovqin juda ko'p. Tinchroq joyda urinib ko'ring.";
    case VOICE_ENROLLMENT_LOW_SPEECH_RATIO:
      return "Pauzalar juda ko'p. Odatdagi tezlikda o'qing.";
    case VOICE_ENROLLMENT_MULTIPLE_SPEAKERS:
      return "Bir nechta ovoz eshitildi. Yolg'iz qolib, qayta urinib ko'ring.";
    case VOICE_ENROLLMENT_PROFILE_NOT_FOUND:
      return "Bu ovoz profili o'chirilgan. Uni qayta qo'shish uchun «Ovoz profillari» ga qayting.";
    default:
      return VOICE_ENROLLMENT_UNEXPLAINED_FAILURE;
  }
}
