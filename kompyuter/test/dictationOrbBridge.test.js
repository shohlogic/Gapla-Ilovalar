// Gapla (G47): ekran o'rtasidagi zarra sharga boradigan signallar ketma-ketligi.
import { test } from "node:test";
import assert from "node:assert/strict";
// Ko'prik window.electronAPI ni chaqiruv paytida o'qiydi — soxta oyna importdan keyin qo'yilsa ham bo'ladi.
import * as bridge from "../src/helpers/dictationOrbBridge.js";

const sent = [];
globalThis.window = {
  electronAPI: {
    dictationOrbSignal: (type, id) => sent.push([type, id]),
    dictationOrbLevel: (level) => sent.push(["level", Math.round(level * 1000) / 1000]),
  },
};

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const types = () => sent.map(([type]) => type);
const ok = { eligible: true };

test("yozish → aylantirish → tayyor", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbLifecycle("processing", ok);
  bridge.dictationOrbDone();
  bridge.dictationOrbLifecycle("idle", ok);
  assert.deepEqual(types(), ["rec", "proc", "done"]);
  assert.equal(bridge.getDictationOrbVisible(), true);
});

test("Esc (yozishdan to'g'ri idle) — shar yo'qoladi", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbLifecycle("idle", ok);
  assert.deepEqual(types(), ["rec", "hide"]);
});

test("natija kelmasa (xato, bo'sh matn) — biroz kutib yo'qoladi", async () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbLifecycle("processing", ok);
  bridge.dictationOrbLifecycle("idle", ok);
  assert.deepEqual(types(), ["rec", "proc"]);
  await wait(450);
  assert.deepEqual(types(), ["rec", "proc", "hide"]);
});

test("idle natijadan oldin kelsa ham «tayyor» chiqadi", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbLifecycle("processing", ok);
  bridge.dictationOrbLifecycle("idle", ok);
  bridge.dictationOrbDone();
  assert.deepEqual(types(), ["rec", "proc", "done"]);
});

test("Agent paneli yozuvi — shar chiqmaydi, pastki kapsula qaytadi", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("recording", { eligible: false });
  bridge.dictationOrbLifecycle("processing", { eligible: false });
  bridge.dictationOrbDone();
  assert.deepEqual(types(), []);
  assert.equal(bridge.getDictationOrbVisible(), false);
  bridge.dictationOrbLifecycle("idle", { eligible: false });
});

test("tugma bosilishi bilan (mikrofon tayyorlanayotganda) shar chiqadi, kapsula yashirinadi", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("preparing", ok);
  assert.equal(bridge.getDictationOrbVisible(), true);
  bridge.dictationOrbLifecycle("preparing", ok);
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbLifecycle("processing", ok);
  bridge.dictationOrbDone();
  assert.deepEqual(types(), ["rec", "proc", "done"]);
});

test("tayyorlanayotganda bekor qilinsa — shar yo'qoladi", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("preparing", ok);
  bridge.dictationOrbLifecycle("idle", ok);
  assert.deepEqual(types(), ["rec", "hide"]);
});

test("shar tugagach ham kapsula yashirin qoladi — keyingi ochilishda logo chaqnamaydi", async () => {
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbDone();
  bridge.dictationOrbLifecycle("idle", ok);
  await wait(1500);
  assert.equal(bridge.getDictationOrbVisible(), true);
});

test("ovoz darajasi faqat yozish paytida, 0…1 oralig'ida", () => {
  sent.length = 0;
  bridge.sendDictationOrbLevel(0.05);
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.sendDictationOrbLevel(0.05);
  bridge.sendDictationOrbLevel(2);
  bridge.dictationOrbLifecycle("idle", ok);
  bridge.sendDictationOrbLevel(0.05);
  const levels = sent.filter(([type]) => type === "level").map(([, level]) => level);
  // 0,05 RMS ≈ −26 dB → (−26 + 42) / 20 ≈ 0,8; 2 (chegaradan baland) → 1.
  assert.deepEqual(levels, [Math.round(((20 * Math.log10(0.05) + 42) / 20) * 1000) / 1000, 1]);
});

test("daraja desibel bo'yicha: jimlik 0, oddiy gap o'rtada, urg'uli bo'g'in 1 ga yaqin", () => {
  const fromDb = (db) => bridge.levelFromRms(Math.pow(10, db / 20));
  assert.equal(fromDb(-45), 0); // jim xona (shu kompyuterda −45…−52 dB)
  assert.ok(fromDb(-41.5) <= 0.05);
  const speech = fromDb(-32); // gap o'rtacha −31…−39 dB
  assert.ok(speech >= 0.3 && speech <= 0.6, `gap ${speech}`);
  assert.ok(fromDb(-23) >= 0.9); // bo'g'inlar (98-foiz) −22…−27 dB
  assert.equal(fromDb(-10), 1);
  assert.equal(bridge.levelFromRms("x"), null);
});

test("har yangi yozish yangi raqam oladi", () => {
  sent.length = 0;
  bridge.dictationOrbLifecycle("recording", ok);
  bridge.dictationOrbLifecycle("idle", ok);
  bridge.dictationOrbLifecycle("recording", ok);
  const ids = sent.filter(([type]) => type === "rec").map(([, id]) => id);
  assert.equal(ids.length, 2);
  assert.ok(ids[1] > ids[0]);
  bridge.dictationOrbLifecycle("idle", ok);
});
