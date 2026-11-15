// Gapla G64: diktovka vaqti — sarlavhalar, ko'prik manzilini tanish, vaqt fayli (shakli, 500 qator, matn yo'q).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  gaplaQurilma,
  gaplaSarlavhalar,
  isGaplaBridgeEndpoint,
  yangiVaqt,
} from "../src/helpers/gaplaDiktovkaOlchov.js";
import vaqtFayli from "../src/helpers/gaplaDiktovkaVaqt.js";

const { qatorYasa, qatorQosh, tozala } = vaqtFayli;

test("qurilma nomi: Windows — kompyuter, Mac — mac", () => {
  assert.equal(gaplaQurilma("win32"), "kompyuter");
  assert.equal(gaplaQurilma("darwin"), "mac");
});

test("faqat Gapla ko'prigi taniladi, boshqa custom manzil emas", () => {
  assert.equal(isGaplaBridgeEndpoint("https://gapla.xaliljonov.uz/v1/audio/transcriptions"), true);
  assert.equal(isGaplaBridgeEndpoint("https://gapla.xaliljonov.uz/v1x/audio"), false);
  assert.equal(isGaplaBridgeEndpoint("https://example.com/v1/audio/transcriptions"), false);
  assert.equal(isGaplaBridgeEndpoint("https://gapla.xaliljonov.uz.evil.com/v1/audio"), false);
  assert.equal(isGaplaBridgeEndpoint(null), false);
});

test("sarlavhalar: qurilma, yozuv to'xtagan va yuborilgan payt (millisoniya)", () => {
  const v = yangiVaqt({ toxtadi: 1_700_000_000_000 });
  assert.deepEqual(gaplaSarlavhalar(v, "win32", 1_700_000_001_500), {
    "X-Gapla-Qurilma": "kompyuter",
    "X-Gapla-Yozuv-Tugadi": "1700000000000",
    "X-Gapla-Yuborildi": "1700000001500",
  });
  assert.equal(gaplaSarlavhalar(null, "darwin", 5)["X-Gapla-Qurilma"], "mac");
});

test("vaqt qatori: bosqichlar soniyada, matn va begona maydon yozilmaydi", () => {
  const t0 = Date.UTC(2026, 10, 14, 14, 26, 58, 700);
  const qator = qatorYasa({
    toxtadi: t0,
    audioTayyor: t0 + 50,
    yuklashTayyor: t0 + 60,
    yuborildi: t0 + 200,
    javob: t0 + 4200,
    joylandi: t0 + 4500,
    audioSoniya: 81.2,
    yozuvHajm: 1305131,
    yozuvTur: "audio/webm;codecs=opus",
    yuklashHajm: 1305131,
    yuklashTur: "audio/webm;codecs=opus",
    rejim: "gapla-orta",
    natija: "matn",
    qurilma: "kompyuter",
    matn: "MAXFIY GAP",
  });
  assert.ok(qator.startsWith("2026-11-14T14:26:58.700Z | rejim=gapla-orta | qurilma=kompyuter | natija=matn"));
  assert.match(qator, /audio=81\.2 s/);
  assert.match(qator, /yozuv=1305131 B audio\/webm;codecs=opus/);
  assert.match(qator, /yuborildi→javob 4\.00 s/);
  assert.match(qator, /jami 4\.50 s/);
  assert.ok(!qator.includes("MAXFIY"));
  assert.equal("matn" in tozala({ matn: "x" }), false);
});

test("ovozni siqish: opus 32 kbps 16 kHz mono, WebM, WAV'dan ancha kichik", async () => {
  const { convertBufferToOpus32 } = (await import("../src/helpers/ffmpegUtils.js")).default;
  const sr = 16000;
  const n = sr * 3;
  const wav = Buffer.alloc(44 + n * 2);
  wav.write("RIFF", 0);
  wav.writeUInt32LE(36 + n * 2, 4);
  wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sr, 24);
  wav.writeUInt32LE(sr * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36);
  wav.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i += 1) wav.writeInt16LE(Math.round(8000 * Math.sin((2 * Math.PI * 220 * i) / sr)), 44 + i * 2);
  const opus = await convertBufferToOpus32(wav);
  assert.equal(opus.subarray(0, 4).toString("hex"), "1a45dfa3"); // WebM (EBML) boshlanishi
  assert.ok(opus.length < wav.length / 4, `opus ${opus.length} B, wav ${wav.length} B`);
});

test("vaqt fayli: oxirgi 500 qator qoladi", () => {
  const papka = fs.mkdtempSync(path.join(os.tmpdir(), "gapla-vaqt-"));
  const fayl = path.join(papka, "logs", "gapla-diktovka-vaqt.log");
  for (let i = 0; i < 505; i += 1) qatorQosh(fayl, `qator ${i}`, 500);
  const qatorlar = fs.readFileSync(fayl, "utf8").trim().split("\n");
  assert.equal(qatorlar.length, 500);
  assert.equal(qatorlar[0], "qator 5");
  assert.equal(qatorlar.at(-1), "qator 504");
  fs.rmSync(papka, { recursive: true, force: true });
});
