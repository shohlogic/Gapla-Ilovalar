// Gapla G64 (2026-11-14): diktovka vaqtini o'lchash — oyna (renderer) tomoni. Egasi: «juda sekin işladi. Buning sababini
// top, ildizini top». Har diktovkada bosqich vaqtlari yig'iladi (yozuv to'xtadi → audio tayyor → yuborildi → javob keldi →
// matn joylandi) va asosiy jarayonga beriladi, u faylga yozadi (gaplaDiktovkaVaqt.js). Matn yozilmaydi.
// Gapla serveriga ketadigan so'rovga uchta sarlavha qo'shiladi — server jurnalida «yo'lda qancha ketdi» ko'rinadi.
import GAPLA_DEFAULTS from "../constants/gapla.json";

/** Server jurnalidagi qurilma nomi: Windows — «kompyuter», Mac — «mac». */
export function gaplaQurilma(platform) {
  if (platform === "darwin") return "mac";
  if (platform === "linux") return "linux";
  return "kompyuter";
}

/** So'rov Gapla ko'prigiga ketyaptimi (Tez/O'rta/Sekin). Boshqa «custom» manzillar o'zgarishsiz qoladi. */
export function isGaplaBridgeEndpoint(endpoint, bridgeUrl = GAPLA_DEFAULTS.bridgeUrl) {
  if (typeof endpoint !== "string" || !bridgeUrl) return false;
  try {
    const a = new URL(endpoint);
    const b = new URL(bridgeUrl);
    return a.origin === b.origin && a.pathname.startsWith(b.pathname.replace(/\/+$/, "") + "/");
  } catch {
    return false;
  }
}

/** Bitta diktovkaning o'lchov yozuvi (vaqtlar — Date.now(), millisoniya). */
export function yangiVaqt({ toxtadi, audioTayyor, audioSoniya, hajm, tur }) {
  return {
    toxtadi: Number.isFinite(toxtadi) ? toxtadi : Date.now(),
    audioTayyor: Number.isFinite(audioTayyor) ? audioTayyor : null,
    audioSoniya: Number.isFinite(audioSoniya) ? audioSoniya : null,
    yozuvHajm: Number.isFinite(hajm) ? hajm : null,
    yozuvTur: typeof tur === "string" ? tur : null,
    rejim: null,
    yuklashHajm: null,
    yuklashTur: null,
    yuklashTayyor: null,
    yuborildi: null,
    javob: null,
    joylandi: null,
    natija: null,
  };
}

/** Gapla serveriga ketadigan sarlavhalar. `yuborildi` so'rov jo'natilayotgan payt. */
export function gaplaSarlavhalar(vaqt, platform, yuborildi = Date.now()) {
  return {
    "X-Gapla-Qurilma": gaplaQurilma(platform),
    "X-Gapla-Yozuv-Tugadi": String(Math.round(vaqt?.toxtadi ?? yuborildi)),
    "X-Gapla-Yuborildi": String(Math.round(yuborildi)),
  };
}
