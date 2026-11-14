// Gapla: yangi alifbo sinovlari — ko'prikdagi sinov.py → test_yangi_alifbo_* va test_eski_alifbo_tanlansa_tegilmaydi
// ning aynan nusxasi (misollar bir xil). Qoida: src/helpers/gaplaAlphabet.js.
import { test } from "node:test";
import assert from "node:assert/strict";
import GAPLA_DEFAULTS from "../src/constants/gapla.json";
import { toNewAlphabet as y } from "../src/helpers/gaplaAlphabet.js";

test("yangi alifbo standart", () => {
  // Egasi tanlovi (2026-11-11, «Diktovka ham»): diktovka matni ham yangi alifboda — ö ğ ş ç
  assert.equal(GAPLA_DEFAULTS.alphabet, "yangi");
});

test("yangi alifbo o'zbekcha", () => {
  assert.equal(y("O'zbekiston go'zal, tog'lar baland."), "Özbekiston gözal, toğlar baland.");
  assert.equal(y("Shohjahon choy ichdi, shu kecha."), "Şohjahon çoy içdi, şu keça.");
  assert.equal(y("SHAHAR CHIROYLI, G'ALABA! O'g'il"), "ŞAHAR ÇIROYLI, ĞALABA! Öğil");
  for (const apostrof of "'ʻ’‘`") {
    assert.equal(y(`o${apostrof}zbekcha`), "özbekça", apostrof);
  }
  assert.equal(y("Toshkent-Samarqand, 5-chi qavat"), "Toşkent-Samarqand, 5-çi qavat");
  assert.equal(y(""), "");
});

test("yangi alifbo — tutuq belgisi qoladi", () => {
  // Tutuq belgisi yangi alifboda ham bor; «s'h» — ş emas (Is'hoq)
  assert.equal(y("ma'no, san'at, e'lon, Is'hoq"), "ma'no, san'at, e'lon, Is'hoq");
});

test("yangi alifbo — chet so'zlar tegilmaydi", () => {
  for (const soz of [
    "ChatGPT", "OpenRouter", "DeepSeek", "dashboard'da", "dashboardda", "flash", "Sherlock", "push",
    "branch", "scratchpad", "switch", "check", "cache", "ThinkingMachines", "Exotechdagi", "короче",
    "точно", "şu", "çok güzel", "yürüyüş", "https://chat.example.com/shop", "shohlogic@gmail.com",
    "@shoh_logic", "#shoshilinch", "mp3chi", "deshboardda",
  ]) {
    assert.equal(y(soz), soz, soz);
  }
  // o'zbekcha so'z inglizcha so'z bilan boshlansa ham o'giriladi
  assert.equal(y("pushti chipta"), "puşti çipta");
  assert.equal(y("Bugun dashboard'da choy, короче"), "Bugun dashboard'da çoy, короче");
});

test("eski alifbo tanlansa tegilmaydi", () => {
  // ko'prikda GAPLA_ALIFBO=eski, bu yerda gapla.json → alphabet: "eski"
  assert.equal(y("O'g'il choy ichdi", "eski"), "O'g'il choy ichdi");
});
