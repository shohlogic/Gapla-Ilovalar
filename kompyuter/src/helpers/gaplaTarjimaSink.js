// Gapla tarjimoni (G56): «Gapirish» bosilganda keyingi diktovka matni egasi yozib turgan ilovaga emas, tarjimon
// maydoniga tushadi. ipcHandlers.js dagi "paste-text" shu yerni so'raydi: qabul qiluvchi bo'lsa — matn unga beriladi
// va hech qayerga joylanmaydi. Qabul qiluvchi bitta diktovka uchun; muddati o'tsa (egasi gapirmay qo'ysa) o'zi tushadi,
// shunda keyingi oddiy Alt+D matni adashib tarjimonga ketmaydi.

const DEFAULT_TTL_MS = 120_000;

let sink = null;
let expiresAt = 0;

function setSink(fn, { ttlMs = DEFAULT_TTL_MS, now = Date.now() } = {}) {
  sink = typeof fn === "function" ? fn : null;
  expiresAt = now + ttlMs;
}

function clearSink() {
  sink = null;
  expiresAt = 0;
}

function isActive(now = Date.now()) {
  if (sink && now > expiresAt) clearSink();
  return Boolean(sink);
}

/** Qabul qiluvchi bo'lsa matnni beradi va true qaytaradi (qabul qiluvchi bir martalik). */
function takeDictation(text, now = Date.now()) {
  if (!isActive(now)) return false;
  const fn = sink;
  clearSink();
  try {
    fn(String(text ?? ""));
  } catch {
    // tarjimon oynasi yopilgan bo'lsa ham matn boshqa ilovaga ketmaydi
  }
  return true;
}

module.exports = { setSink, clearSink, isActive, takeDictation };
