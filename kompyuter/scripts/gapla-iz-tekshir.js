#!/usr/bin/env node
// Gapla: yig'ishdan oldingi taqiq tekshiruvi (egasi, 2026-11-11, G44). Ro'yxat — ../gapla-taqiqlangan.json.
// Yuboriladigan kodda yoki qurilgan oynada OpenWhispr manzili, ko'rinadigan matnda OpenWhispr nomi qolsa —
// yig'ish to'xtaydi. electron-builder.json → "beforePack" chaqiradi; qo'lda: `node scripts/gapla-iz-tekshir.js`.
// Renderer (`npm run build:renderer`) avval qurilgan bo'lishi kerak — src/dist ham tekshiriladi.
//
// Rasm, belgi va animatsiya (egasi, 2026-11-12: «ustanovka qilayotganimda ham eski brend loyihalari va animatsiyalari
// chiqayotgan edi»). So'z tekshiruvi rasmni ko'rmaydi, shuning uchun ilovaga kiradigan har rasm fayli (va SVG ichiga
// joylangan rasm) mazmuni bo'yicha (sha256) tekshiriladi:
//   1) gapla-taqiqlangan.json → "eski_rasmlar" dagi eski brend rasmi qaytsa — yig'ish to'xtaydi;
//   2) gapla-rasmlar.json → "korilgan" da yo'q rasm (yangi yoki o'zgargan) ham to'xtatadi: odam ko'rib, Gapla'niki yoki
//      neytral ekaniga ishonch hosil qilgach `node scripts/gapla-iz-tekshir.js --korildi <fayl> [fayl…]` bilan qo'shadi.
//   3) O'rnatuvchi o'z rasmisiz qolmasin: NSIS yon rasmi berilmasa, NSIS'ning o'z logosi chiqadi.
//   4) Eski brendning ko'k-binafsha ranglari va kodda chizilgan logosi (egasi, 2026-11-12: «Ha, Gapla rangi»):
//      gapla-taqiqlangan.json → "eski_ranglar" — src kodi va qurilgan oynada (src/dist) taqiq.
// Faqat rasmlar: `node scripts/gapla-iz-tekshir.js --rasmlar` (src/dist shart emas).
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const KOD = path.join(__dirname, "..");
const OTKAZ = new Set(["node_modules", "test", "tests", "__tests__"]);
const KOD_TURI = /\.(js|cjs|mjs|ts|tsx|json|html|css|nsh)$/;
// Ilovaga kiradigan rasm, belgi va animatsiya turlari. src/assets ichidagi .json ham (Lottie animatsiya bo'lishi mumkin).
const RASM_TURI = /\.(png|jpe?g|webp|gif|apng|avif|bmp|ico|icns|svg|mp4|webm|mov|lottie|riv)$/i;
const RASM_PAPKALARI = ["src/assets", "resources/nsis"];
const RASM_OTKAZ = new Set(["fonts"]);
const ICHKI_RASM = /data:(image\/[a-z0-9.+-]+|video\/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=]+)/g;

const nisbiy = (kod, p) => path.relative(kod, p).split(path.sep).join("/");
const jsonOqi = (p) => JSON.parse(fs.readFileSync(p, "utf8").replace(/^﻿/, ""));

function yur(papka, natija = [], turi = KOD_TURI, otkaz = OTKAZ) {
  if (!fs.existsSync(papka)) return natija;
  for (const e of fs.readdirSync(papka, { withFileTypes: true })) {
    if (otkaz.has(e.name)) continue;
    const p = path.join(papka, e.name);
    if (e.isDirectory()) yur(p, natija, turi, otkaz);
    else if (turi.test(e.name)) natija.push(p);
  }
  return natija;
}

// Izohlar yuborilmaydi va ko'rinmaydi: butun qatorli `//`, `/* */` va NSIS `;` izohlari olib tashlanadi.
function izohsiz(matn, fayl) {
  if (fayl.endsWith(".json") || fayl.endsWith(".svg")) return matn;
  if (fayl.endsWith(".nsh")) return matn.replace(/^\s*;.*$/gm, "");
  return matn.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, " ")).replace(/^\s*\/\/.*$/gm, "");
}

const xesh = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex").slice(0, 16);

/** Ilovaga kiradigan har rasm bo'lagi: fayl o'zi va SVG/JSON ichiga base64 bilan joylangan rasmlar. */
function rasmBolaklari(kod) {
  const fayllar = [];
  for (const p of RASM_PAPKALARI) {
    const papka = path.join(kod, p);
    yur(papka, fayllar, RASM_TURI, RASM_OTKAZ);
    if (p === "src/assets") yur(papka, fayllar, /\.json$/i, RASM_OTKAZ);
  }
  const bolaklar = [];
  for (const p of fayllar) {
    const fayl = nisbiy(kod, p);
    const bytes = fs.readFileSync(p);
    bolaklar.push({ fayl, xesh: xesh(bytes) });
    if (/\.(svg|json)$/i.test(fayl)) {
      let n = 0;
      for (const m of bytes.toString("utf8").matchAll(ICHKI_RASM)) {
        n += 1;
        bolaklar.push({ fayl: `${fayl}#ichki-${n}`, xesh: xesh(Buffer.from(m[2], "base64")) });
      }
    }
  }
  return bolaklar;
}

/** Rasm tekshiruvi: eski brend rasmi, ko'rilmagan rasm, o'rnatuvchi rasmi. Topilganlar ro'yxatini qaytaradi. */
function rasmlarniTekshir(kod = KOD) {
  const royxat = jsonOqi(path.join(kod, "gapla-taqiqlangan.json"));
  const rasmFayl = path.join(kod, "gapla-rasmlar.json");
  const korilgan = fs.existsSync(rasmFayl) ? jsonOqi(rasmFayl).korilgan || {} : {};
  const eski = royxat.eski_rasmlar || {};
  const topildi = [];
  for (const b of rasmBolaklari(kod)) {
    if (eski[b.xesh]) topildi.push(`${b.fayl}  eski brend rasmi (${b.xesh}): ${eski[b.xesh]}`);
    else if (!korilgan[b.xesh]) topildi.push(`${b.fayl}  ko'rilmagan rasm (${b.xesh}) — ko'ring, keyin --korildi`);
  }
  const quruvchi = path.join(kod, "electron-builder.json");
  if (fs.existsSync(quruvchi)) {
    const q = jsonOqi(quruvchi);
    for (const kalit of ["installerSidebar", "uninstallerSidebar"]) {
      const f = q.nsis?.[kalit];
      if (!f) topildi.push(`electron-builder.json  nsis.${kalit} yo'q — o'rnatuvchida NSIS logosi chiqadi`);
      else if (!fs.existsSync(path.join(kod, f))) topildi.push(`electron-builder.json  nsis.${kalit}: ${f} topilmadi`);
    }
    if (!q.win?.icon) topildi.push("electron-builder.json  win.icon yo'q — Electron'ning o'z belgisi chiqadi");
  }
  return topildi;
}

// Rang yozuvini solishtirishga tayyorlash: kichik harf, bo'sh joy bitta, vergul va qavs atrofida bo'sh joy yo'q.
const rangShakli = (s) =>
  s
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/\s*([,(])\s*/g, "$1");
const RANG_FAYLI = /\.(css|js|cjs|mjs|jsx|ts|tsx|html|svg)$/i;

/** Eski brend ranglari (gapla-taqiqlangan.json → eski_ranglar): src kodi va qurilgan oynada (src/dist). */
function ranglarniTekshir(kod = KOD) {
  const royxat = jsonOqi(path.join(kod, "gapla-taqiqlangan.json"));
  const qiymatlar = (royxat.eski_ranglar?.qiymatlar || []).map((q) => [q, rangShakli(q)]);
  if (!qiymatlar.length) return [];
  const istisnomi = (fayl, qator) =>
    (royxat.istisnolar || []).some((i) => fayl === i.fayl && qator.includes(i.matn));
  const fayllar = yur(path.join(kod, "src"), [], RANG_FAYLI, new Set([...OTKAZ, "fonts"]));
  const topildi = [];
  for (const p of fayllar) {
    const fayl = nisbiy(kod, p);
    fs.readFileSync(p, "utf8")
      .split(/\r?\n/)
      .forEach((qator, i) => {
        const shakl = rangShakli(qator);
        const t = qiymatlar.find(([, q]) => shakl.includes(q));
        if (t && !istisnomi(fayl, qator)) topildi.push(`${fayl}:${i + 1}  eski brend rangi «${t[0]}»`);
      });
  }
  return topildi;
}

/** Ko'rilgan rasmlarni ro'yxatga qo'shish (odam ko'rgandan keyin). Eski brend rasmini qo'shmaydi. */
function korildi(fayllar, kod = KOD) {
  const royxat = jsonOqi(path.join(kod, "gapla-taqiqlangan.json"));
  const eski = royxat.eski_rasmlar || {};
  const rasmFayl = path.join(kod, "gapla-rasmlar.json");
  const r = fs.existsSync(rasmFayl) ? jsonOqi(rasmFayl) : { izoh: "", korilgan: {} };
  const kerak = new Set(fayllar.map((f) => nisbiy(kod, path.resolve(kod, f))));
  const sana = new Date().toISOString().slice(0, 10);
  const qoshildi = [];
  for (const b of rasmBolaklari(kod)) {
    if (!kerak.has(b.fayl.split("#")[0])) continue;
    if (eski[b.xesh]) throw new Error(`${b.fayl} — eski brend rasmi (${eski[b.xesh]}), qo'shilmaydi`);
    if (!r.korilgan[b.xesh]) {
      r.korilgan[b.xesh] = `${b.fayl} — ko'rildi ${sana}`;
      qoshildi.push(b.fayl);
    }
  }
  r.korilgan = Object.fromEntries(Object.entries(r.korilgan).sort(([, a], [, b]) => a.localeCompare(b)));
  const tmp = `${rasmFayl}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(r, null, 2)}\n`);
  fs.renameSync(tmp, rasmFayl);
  return qoshildi;
}

/** So'z va manzil tekshiruvi (2026-11-11 dagi asl qism). */
function matnlarniTekshir(kod = KOD) {
  const ROYXAT = jsonOqi(path.join(kod, "gapla-taqiqlangan.json"));
  const topildi = [];
  const istisnomi = (fayl, qator) => ROYXAT.istisnolar.some((i) => fayl === i.fayl && qator.includes(i.matn));
  const qatorlarniTekshir = (fayl, matn, tekshir) => {
    matn.split(/\r?\n/).forEach((qator, i) => {
      const soz = tekshir(qator);
      if (soz && !istisnomi(fayl, qator)) topildi.push(`${fayl}:${i + 1}  «${soz}»  ${qator.trim().slice(0, 140)}`);
    });
  };
  const manzilTop = (qator) => {
    const kichik = qator.toLowerCase();
    return ROYXAT.manzillar.find((m) => kichik.includes(m.toLowerCase()));
  };
  const NOM_NAQSH = ROYXAT.nomlar.map((n) => [n, new RegExp(`(?<![A-Za-z])${n.replace(/ /g, "\\s+")}(?![A-Za-z])`)]);
  const nomTop = (qator) => (NOM_NAQSH.find(([, r]) => r.test(qator)) || [])[0];

  // 1) Manzillar — yuboriladigan hamma kod va qurilgan oyna
  const qurilgan = path.join(kod, "src", "dist");
  if (!fs.existsSync(qurilgan)) {
    throw new Error("gapla-iz-tekshir: src/dist yo'q — avval `npm run build:renderer`");
  }
  const manzilFayllari = [
    path.join(kod, "main.js"),
    path.join(kod, "preload.js"),
    path.join(kod, "package.json"),
    path.join(kod, "electron-builder.json"),
    path.join(kod, "electron-builder.unsigned-win.json"),
    ...yur(path.join(kod, "src")),
    ...yur(path.join(kod, "resources", "nsis")),
  ];
  for (const p of manzilFayllari) {
    const fayl = nisbiy(kod, p);
    qatorlarniTekshir(fayl, izohsiz(fs.readFileSync(p, "utf8"), fayl), manzilTop);
  }

  // 2) Nomlar — foydalanuvchi ko'radigan matnlar
  const qiymatlar = (x, chiqish = []) => {
    if (typeof x === "string") chiqish.push(x);
    else if (Array.isArray(x)) x.forEach((v) => qiymatlar(v, chiqish));
    else if (x && typeof x === "object") Object.values(x).forEach((v) => qiymatlar(v, chiqish));
    return chiqish;
  };
  for (const p of yur(path.join(kod, "src", "locales"))) {
    if (!p.endsWith(".json")) continue;
    const fayl = nisbiy(kod, p);
    for (const q of qiymatlar(jsonOqi(p))) {
      const soz = nomTop(q);
      if (soz && !istisnomi(fayl, q)) topildi.push(`${fayl}  «${soz}»  ${q.slice(0, 140)}`);
    }
  }
  for (const p of [
    path.join(kod, "package.json"),
    path.join(kod, "electron-builder.json"),
    path.join(kod, "electron-builder.unsigned-win.json"),
    ...yur(path.join(kod, "resources", "nsis")),
    // SVG ichidagi <text>/<title> ham ekranda ko'rinadi
    ...yur(path.join(kod, "src", "assets"), [], /\.svg$/i, RASM_OTKAZ),
  ]) {
    const fayl = nisbiy(kod, p);
    qatorlarniTekshir(fayl, izohsiz(fs.readFileSync(p, "utf8"), fayl), nomTop);
  }
  return { topildi, soni: manzilFayllari.length };
}

function natija({ faqatRasm = false } = {}) {
  const rasm = rasmlarniTekshir();
  const rang = ranglarniTekshir();
  const matn = faqatRasm ? { topildi: [], soni: 0 } : matnlarniTekshir();
  const topildi = [...matn.topildi, ...rasm, ...rang];
  if (topildi.length) {
    const xabar =
      `gapla-iz-tekshir: eski brend izi qoldi (${topildi.length}) — yig'ish to'xtatildi.\n` +
      topildi.map((t) => `  ${t}`).join("\n") +
      "\nSo'z bo'lsa — tuzating yoki sababi bilan gapla-taqiqlangan.json → istisnolar ga yozing." +
      "\nRasm bo'lsa — ko'ring: Gapla'niki yoki neytral bo'lsa `node scripts/gapla-iz-tekshir.js --korildi <fayl>`." +
      "\nRang bo'lsa — Gapla rangiga almashtiring (index.css dagi --color-primary, --gapla-mandarin).";
    throw new Error(xabar);
  }
  const rasmSoni = rasmBolaklari(KOD).length;
  console.log(
    faqatRasm
      ? `gapla-iz-tekshir: rasmlar toza (${rasmSoni} rasm)`
      : `gapla-iz-tekshir: toza (${matn.soni} fayl, ${rasmSoni} rasm tekshirildi)`
  );
}

module.exports = async function beforePack() {
  natija();
};
module.exports.rasmBolaklari = rasmBolaklari;
module.exports.rasmlarniTekshir = rasmlarniTekshir;
module.exports.korildi = korildi;
module.exports.ranglarniTekshir = ranglarniTekshir;

if (require.main === module) {
  const args = process.argv.slice(2);
  try {
    if (args[0] === "--korildi") {
      const q = korildi(args.slice(1));
      console.log(q.length ? `ro'yxatga qo'shildi (${q.length}):\n  ${q.join("\n  ")}` : "yangi rasm yo'q");
    } else {
      natija({ faqatRasm: args.includes("--rasmlar") });
    }
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
