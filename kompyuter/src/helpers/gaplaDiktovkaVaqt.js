// Gapla G64 (2026-11-14): diktovka vaqtlari fayli — asosiy jarayon tomoni. Oyna (gaplaDiktovkaOlchov.js) har diktovka
// tugaganda bosqich vaqtlarini yuboradi, bu yerda bitta qator bo'lib `<userData>/logs/gapla-diktovka-vaqt.log` ga yoziladi
// (Windows: %APPDATA%\Gapla\logs, Mac: ~/Library/Application Support/Gapla/logs). Fayl oxirgi 500 qator bilan cheklangan.
// Matn yozilmaydi: faqat raqamlar, rejim nomi, fayl turi va natija belgisi qabul qilinadi.
const fs = require("fs");
const path = require("path");

const FAYL_NOMI = "gapla-diktovka-vaqt.log";
const MAX_QATOR = 500;

const raqam = (v) => (Number.isFinite(v) ? v : null);
const qisqa = (v, max = 40) => (typeof v === "string" ? v.replace(/[^\w./:;=+-]/g, "").slice(0, max) : null);

/** Oynadan kelgan yozuvdan faqat ruxsat etilgan maydonlar. */
function tozala(v = {}) {
  return {
    toxtadi: raqam(v.toxtadi),
    audioTayyor: raqam(v.audioTayyor),
    yuklashTayyor: raqam(v.yuklashTayyor),
    yuborildi: raqam(v.yuborildi),
    javob: raqam(v.javob),
    joylandi: raqam(v.joylandi),
    audioSoniya: raqam(v.audioSoniya),
    yozuvHajm: raqam(v.yozuvHajm),
    yuklashHajm: raqam(v.yuklashHajm),
    yozuvTur: qisqa(v.yozuvTur),
    yuklashTur: qisqa(v.yuklashTur),
    rejim: qisqa(v.rejim),
    natija: qisqa(v.natija, 24),
    qurilma: qisqa(v.qurilma, 16),
  };
}

const oraliq = (a, b) => (a != null && b != null ? `${((b - a) / 1000).toFixed(2)} s` : "—");

/** Bitta qator: sana, rejim, natija, audio uzunligi, hajm va bosqichlar orasidagi vaqt (soniya). */
function qatorYasa(kirish) {
  const v = tozala(kirish);
  const sana = new Date(v.toxtadi ?? Date.now()).toISOString();
  const oxirgi = v.joylandi ?? v.javob ?? v.yuborildi ?? v.audioTayyor;
  const hajm = (n, t) => (n != null ? `${n} B ${t || "?"}` : "—");
  return [
    sana,
    `rejim=${v.rejim || "?"}`,
    `qurilma=${v.qurilma || "?"}`,
    `natija=${v.natija || "?"}`,
    `audio=${v.audioSoniya != null ? v.audioSoniya.toFixed(1) + " s" : "—"}`,
    `yozuv=${hajm(v.yozuvHajm, v.yozuvTur)}`,
    `yuborilgan=${hajm(v.yuklashHajm, v.yuklashTur)}`,
    `to'xtadi→audio ${oraliq(v.toxtadi, v.audioTayyor)}`,
    `audio→yuklashga tayyor ${oraliq(v.audioTayyor, v.yuklashTayyor)}`,
    `tayyor→yuborildi ${oraliq(v.yuklashTayyor ?? v.audioTayyor, v.yuborildi)}`,
    `yuborildi→javob ${oraliq(v.yuborildi, v.javob)}`,
    `javob→joylandi ${oraliq(v.javob, v.joylandi)}`,
    `jami ${oraliq(v.toxtadi, oxirgi)}`,
  ].join(" | ");
}

/** Qatorni qo'shadi va faylda oxirgi `max` qatorni qoldiradi (vaqtinchalik fayl + almashtirish — fayl bo'shab qolmaydi). */
function qatorQosh(fayl, qator, max = MAX_QATOR) {
  fs.mkdirSync(path.dirname(fayl), { recursive: true });
  let eski = [];
  try {
    eski = fs.readFileSync(fayl, "utf8").split(/\r?\n/).filter(Boolean);
  } catch {
    eski = [];
  }
  const yangi = [...eski, qator].slice(-max);
  const tmp = `${fayl}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, yangi.join("\n") + "\n", "utf8");
  fs.renameSync(tmp, fayl);
  return yangi.length;
}

function setupGaplaDiktovkaVaqt({ ipcMain, app, debugLogger }) {
  let fayl = null;
  try {
    fayl = path.join(app.getPath("userData"), "logs", FAYL_NOMI);
  } catch {
    return null;
  }
  // G64: Gapla ko'prigiga ketadigan ovozni opus 32 kbps 16 kHz mono ga siqish (ffmpegUtils.convertBufferToOpus32).
  // Xato bo'lsa oyna eski yo'lga (WAV) qaytadi.
  ipcMain.handle("gapla-opus32", async (_event, data) => {
    const { convertBufferToOpus32 } = require("./ffmpegUtils");
    return convertBufferToOpus32(Buffer.from(data));
  });
  ipcMain.on("gapla-diktovka-vaqt", (_event, yozuv) => {
    try {
      qatorQosh(fayl, qatorYasa(yozuv));
    } catch (error) {
      debugLogger?.warn?.("Gapla diktovka vaqti yozilmadi", { error: error?.message }, "audio");
    }
  });
  return { fayl };
}

module.exports = { setupGaplaDiktovkaVaqt, qatorYasa, qatorQosh, tozala, FAYL_NOMI, MAX_QATOR };
