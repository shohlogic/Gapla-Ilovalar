// Gapla tarjimoni (G56, 2026-11-13) — server so'rovi. Egasi: «ruscha ozbekcha va inglizcha tarjimalari boladi …
// har safar avtomatik 2 ta variant beradi, birinchisi birga bir tarjima, ikkinchisi esa gramatik jixatdan yahshilangan
// va biroz qisqartirilgan varinat». Android'dagi GaplaTarjimon.kt bilan bir xil.
//
// Server: `POST <Gapla>/v1/tarjima`, diktovka bilan bir xil kalit (`Authorization: Bearer`), so'rov
// `{"matn", "til": uz|ru|en|auto}`, javob `{"manba", "til", "variantlar": [{"tur": "aniq"|"silliq", "matn"}], "matn"}`.
// Kompyuter AI kalitini ko'rmaydi — model serverda. Matn logga yozilmaydi.

const MAX_BELGI = 20_000;
const TILLAR = ["uz", "ru", "en", "auto"];
const REQUEST_TIMEOUT_MS = 40_000;

class TarjimaXato extends Error {
  constructor(status, code) {
    super(`tarjima: ${code || status}`);
    this.status = status;
    this.code = code || null;
  }
}

function tilniTekshir(til) {
  return TILLAR.includes(til) ? til : "auto";
}

/** Server javobidan ikki variant: «aniq» bo'lmasa umumiy `matn`, «silliq» bo'lmasa bo'sh. */
function natijaniOqi(json) {
  const variantlar = Array.isArray(json?.variantlar) ? json.variantlar : [];
  const tur = (t) => String(variantlar.find((v) => v?.tur === t)?.matn || "").trim();
  const aniq = tur("aniq") || String(json?.matn || "").trim();
  return {
    manba: String(json?.manba || ""),
    til: String(json?.til || ""),
    aniq,
    silliq: tur("silliq"),
  };
}

/**
 * Matnni tarjima qiladi. Xatoda TarjimaXato: status 0 — tarmoq yo'q yoki vaqt tugadi; 401 — kalit yo'q;
 * 413 — 20 000 belgidan uzun (so'rov yuborilmaydi); 502 — javob tushunarsiz yoki bo'sh.
 */
async function tarjima({ baseUrl, key, matn, til, fetchImpl, timeoutMs = REQUEST_TIMEOUT_MS }) {
  const toza = String(matn || "").trim();
  if (!toza) throw new TarjimaXato(400, "EMPTY");
  if (toza.length > MAX_BELGI) throw new TarjimaXato(413);
  const token = String(key || "").trim();
  if (!token) throw new TarjimaXato(401, "NO_KEY");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res;
  try {
    res = await fetchImpl(`${String(baseUrl).replace(/\/+$/, "")}/tarjima`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ matn: toza, til: tilniTekshir(til) }),
      signal: controller.signal,
    });
  } catch {
    throw new TarjimaXato(0, "NETWORK");
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) throw new TarjimaXato(res.status);
  let json;
  try {
    json = await res.json();
  } catch {
    throw new TarjimaXato(502);
  }
  const natija = natijaniOqi(json);
  if (!natija.aniq) throw new TarjimaXato(502);
  return natija;
}

module.exports = { tarjima, natijaniOqi, tilniTekshir, TarjimaXato, MAX_BELGI, TILLAR };
