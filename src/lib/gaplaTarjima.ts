// Gapla tarjimoni (G56, owner 2026-11-12): «ruscha ozbekcha va inglizcha tarjimalari boladi … har safar avtomatik 2 ta
// variant beradi, birinchisi birga bir tarjima, ikkinchisi esa gramatik jixatdan yahshilangan va biroz qisqartirilgan».
// Server: `POST <Gapla>/v1/tarjima`, the dictation key (`Authorization: Bearer`), request `{matn, til}`, answer
// `{manba, til, variantlar: [{tur: "aniq"|"silliq", matn}]}`. The AI key and the model stay on the server. The text is
// never logged. Same shape as Android (GaplaTarjimon.kt).
import { bridgeEndpoint, gaplaServerKey } from './keyboardServerKeySync';

export type TarjimaTil = 'auto' | 'uz' | 'ru' | 'en';

export const TARJIMA_TILLARI: ReadonlyArray<{ id: TarjimaTil; nom: string }> = [
  { id: 'auto', nom: 'Avto' },
  { id: 'uz', nom: "O'zbekcha" },
  { id: 'ru', nom: 'Русский' },
  { id: 'en', nom: 'English' },
];

export const TARJIMA_MAX_BELGI = 20_000;
const TIMEOUT_MS = 40_000;

export interface TarjimaNatija {
  manba: string;
  til: string;
  aniq: string;
  silliq: string;
}

/** The server answered with an error; `kod` 0 means no network or no answer. */
export class TarjimaXato extends Error {
  readonly kod: number;

  constructor(kod: number) {
    super(tarjimaXatoXabari(kod));
    this.kod = kod;
  }
}

function tarjimaXatoXabari(kod: number): string {
  switch (kod) {
    case 0:
      return "Internet yo'q yoki server javob bermadi. Qayta urinib ko'ring.";
    case 400:
      return "So'rov noto'g'ri. Matnni tekshirib, qayta urinib ko'ring.";
    case 401:
    case 403:
      return "Gapla kaliti yo'q yoki noto'g'ri. Uni AI modellari bo'limida kiriting.";
    case 404:
      return 'Tarjima xizmati hali ishga tushmagan.';
    case 413:
      return "Matn juda uzun: 20 000 belgidan oshmasin.";
    case 429:
      return "So'rov juda ko'p. Birozdan keyin qayta urinib ko'ring.";
    default:
      return "Tarjima chiqmadi, qayta urinib ko'ring.";
  }
}

export function tarjimaTilNomi(kod: string): string {
  return TARJIMA_TILLARI.find((item) => item.id === kod)?.nom ?? kod;
}

function matnOf(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

/** `til`: "uz", "ru", "en" or "auto" (Uzbek → Russian, anything else → Uzbek). */
export async function tarjimaQil(
  matn: string,
  til: TarjimaTil,
  signal?: AbortSignal,
): Promise<TarjimaNatija> {
  if (matn.length > TARJIMA_MAX_BELGI) throw new TarjimaXato(413);
  const key = await gaplaServerKey().catch(() => null);
  if (!key) throw new TarjimaXato(401);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  const abort = (): void => controller.abort();
  signal?.addEventListener('abort', abort, { once: true });
  let response: Response;
  try {
    response = await fetch(`${bridgeEndpoint().replace(/\/+$/, '')}/tarjima`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ matn, til }),
      signal: controller.signal,
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw new TarjimaXato(0);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', abort);
  }
  if (!response.ok) throw new TarjimaXato(response.status);

  let payload: Record<string, unknown>;
  try {
    payload = (await response.json()) as Record<string, unknown>;
  } catch {
    throw new TarjimaXato(502);
  }
  const variantlar = Array.isArray(payload.variantlar)
    ? (payload.variantlar as Array<Record<string, unknown>>)
    : [];
  const variant = (tur: string): string =>
    matnOf(variantlar.find((item) => item?.tur === tur)?.matn);
  const aniq = variant('aniq').trim() ? variant('aniq') : matnOf(payload.matn);
  if (!aniq.trim()) throw new TarjimaXato(502);
  return {
    manba: matnOf(payload.manba),
    til: matnOf(payload.til),
    aniq,
    silliq: variant('silliq'),
  };
}
