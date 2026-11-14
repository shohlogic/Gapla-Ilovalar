// Gapla tarjimoni (G56): server so'rovi va «Gapirish» qabul qiluvchisi.
const test = require("node:test");
const assert = require("node:assert/strict");
const { tarjima, natijaniOqi, tilniTekshir, MAX_BELGI } = require("../src/helpers/gaplaTarjima");
const sink = require("../src/helpers/gaplaTarjimaSink");

function fakeFetch(status, body, seen = []) {
  return async (url, init) => {
    seen.push({ url, init });
    return { ok: status >= 200 && status < 300, status, json: async () => body };
  };
}

test("so'rov: manzil, kalit, til va matn to'g'ri boradi; ikki variant qaytadi", async () => {
  const seen = [];
  const r = await tarjima({
    baseUrl: "https://gapla.example/v1/",
    key: " kalit ",
    matn: "  Salom dunyo  ",
    til: "ru",
    fetchImpl: fakeFetch(200, {
      manba: "uz",
      til: "ru",
      variantlar: [
        { tur: "aniq", matn: "Привет, мир" },
        { tur: "silliq", matn: "Привет!" },
      ],
      matn: "Привет, мир",
    }, seen),
  });
  assert.deepEqual(r, { manba: "uz", til: "ru", aniq: "Привет, мир", silliq: "Привет!" });
  assert.equal(seen[0].url, "https://gapla.example/v1/tarjima");
  assert.equal(seen[0].init.headers.Authorization, "Bearer kalit");
  assert.deepEqual(JSON.parse(seen[0].init.body), { matn: "Salom dunyo", til: "ru" });
});

test("noma'lum til «auto» bo'ladi; «aniq» yo'q bo'lsa umumiy matn olinadi", () => {
  assert.equal(tilniTekshir("de"), "auto");
  assert.equal(tilniTekshir("en"), "en");
  assert.deepEqual(natijaniOqi({ matn: "Hi", variantlar: [] }), { manba: "", til: "", aniq: "Hi", silliq: "" });
});

test("xatolar: kalitsiz 401, uzun matn 413 (so'rovsiz), server xatosi o'z kodi, bo'sh javob 502, tarmoq 0", async () => {
  const kutilgan = async (opts, status) => {
    await assert.rejects(() => tarjima({ baseUrl: "https://x/v1", key: "k", matn: "a", til: "uz", ...opts }), (e) => e.status === status);
  };
  await kutilgan({ key: "", fetchImpl: fakeFetch(200, {}) }, 401);
  let chaqirildi = false;
  await kutilgan({ matn: "a".repeat(MAX_BELGI + 1), fetchImpl: async () => ((chaqirildi = true), {}) }, 413);
  assert.equal(chaqirildi, false);
  await kutilgan({ fetchImpl: fakeFetch(429, {}) }, 429);
  await kutilgan({ fetchImpl: fakeFetch(200, { variantlar: [] }) }, 502);
  await kutilgan({ fetchImpl: async () => { throw new Error("offline"); } }, 0);
});

test("«Gapirish» qabul qiluvchisi bir martalik, muddati o'tsa matn oddiy joylashga qaytadi", () => {
  const olingan = [];
  sink.setSink((t) => olingan.push(t), { ttlMs: 1000, now: 0 });
  assert.equal(sink.takeDictation("birinchi", 10), true);
  assert.equal(sink.takeDictation("ikkinchi", 20), false); // keyingi Alt+D matni tarjimonga ketmaydi
  assert.deepEqual(olingan, ["birinchi"]);
  sink.setSink((t) => olingan.push(t), { ttlMs: 1000, now: 0 });
  assert.equal(sink.takeDictation("kech", 5000), false);
  assert.deepEqual(olingan, ["birinchi"]);
  sink.clearSink();
});
