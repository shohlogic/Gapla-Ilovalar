// Gapla (G8): Alt+B oynasi uchun saqlangan ro'yxat — darhol chiqishi, kalitga bog'liqligi, maxfiy matn diskka tushmasligi.
import { test } from "node:test";
import assert from "node:assert/strict";
import cacheModule from "../src/helpers/gaplaBuferCache.js";

const { BuferCache, keyOwner, SECRET_PREVIEW } = cacheModule;
const A = keyOwner("kalit-a");
const B = keyOwner("kalit-b");

const item = (id, vaqt, extra = {}) => ({ id, boshi: `matn ${id}`, uzunlik: 7, qurilma: "iPhone", vaqt, qadalgan: false, maxfiy: false, ...extra });

test("ro'yxat hali olinmagan — null, yuklash belgisi kerak", () => {
  const cache = new BuferCache();
  assert.deepEqual(cache.snapshot(A), { items: null, savedAt: 0 });
});

test("serverdan kelgan ro'yxat saqlanadi va qadalgan tepada", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 100), item(2, 300), item(3, 200, { qadalgan: true })], 5000);
  assert.deepEqual(cache.snapshot(A).items.map((x) => x.id), [3, 2, 1]);
  assert.equal(cache.snapshot(A).savedAt, 5000);
});

test("boshqa kalit bilan eski ro'yxat ko'rsatilmaydi", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 100)]);
  cache.setText(A, 1, "to'liq");
  assert.equal(cache.snapshot(B).items, null);
  assert.equal(cache.getText(B, 1), undefined);
  assert.equal(cache.snapshot(null).items, null);
});

test("to'liq matn bir marta saqlanadi, ro'yxatdan chiqqani tozalanadi", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 100), item(2, 200)]);
  cache.setText(A, 1, "birinchi");
  cache.setText(A, 2, "ikkinchi");
  assert.equal(cache.getText(A, 1), "birinchi");
  cache.setList(A, [item(2, 200)]);
  assert.equal(cache.getText(A, 1), undefined);
  assert.equal(cache.getText(A, 2), "ikkinchi");
});

test("kompyuterning o'z nusxasi ro'yxat tepasiga darhol tushadi", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 100), item(2, 200, { qadalgan: true })]);
  cache.rememberOwn(A, { matn: "yangi nusxa", qurilma: "Kompyuter", maxfiy: false }, 9, 1_000_000);
  const items = cache.snapshot(A).items;
  assert.deepEqual(items.map((x) => x.id), [2, 9, 1]);
  assert.equal(items[1].boshi, "yangi nusxa");
  assert.equal(items[1].vaqt, 1000);
  assert.equal(cache.getText(A, 9), "yangi nusxa");
});

test("maxfiy nusxa: ro'yxatda yulduzcha, to'liq matn diskka yozilmaydi", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 100)]);
  cache.setText(A, 1, "oddiy matn");
  cache.rememberOwn(A, { matn: "parol123", qurilma: "Kompyuter", maxfiy: true }, 2);
  assert.equal(cache.snapshot(A).items[0].boshi, SECRET_PREVIEW);
  assert.equal(cache.getText(A, 2), "parol123");
  const json = cache.serialize();
  assert.ok(!json.includes("parol123"));
  assert.ok(json.includes("oddiy matn"));
});

test("diskdan qayta o'qilgan kesh xuddi shunday ishlaydi", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 100), item(2, 200)], 7000);
  cache.setText(A, 2, "saqlangan matn");
  const restored = new BuferCache();
  assert.equal(restored.load(cache.serialize()), true);
  assert.deepEqual(restored.snapshot(A).items.map((x) => x.id), [2, 1]);
  assert.equal(restored.snapshot(A).savedAt, 7000);
  assert.equal(restored.getText(A, 2), "saqlangan matn");
  assert.equal(new BuferCache().load("{buzuq"), false);
});

test("qadash va o'chirish keshga ham tushadi", () => {
  const cache = new BuferCache();
  cache.setList(A, [item(1, 300), item(2, 200), item(3, 100)]);
  cache.setText(A, 3, "uchinchi");
  cache.setPinned(A, 3, true);
  assert.deepEqual(cache.snapshot(A).items.map((x) => x.id), [3, 1, 2]);
  cache.remove(A, 3);
  assert.deepEqual(cache.snapshot(A).items.map((x) => x.id), [1, 2]);
  assert.equal(cache.getText(A, 3), undefined);
});
