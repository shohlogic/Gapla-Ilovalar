// Gapla (G61, Mac): oldinda turgan ilovani eslab qolish va qaytarish — tarjimonning «Joylash» tugmasi uchun.
// Windows'da bu ishni windows-fast-paste qiladi (--detect-only, --restore-window). Mac'da ruxsat so'ramaydigan tizim
// vositalari ishlatiladi: `lsappinfo` (oldindagi ilova) va `open -b` (ilovani oldinga chiqarish). AppleScript
// ishlatilmaydi — u «Gapla System Events'ni boshqarmoqchi» degan qo'shimcha ruxsat so'raydi.
const { execFile } = require("child_process");

const LSAPPINFO = "/usr/bin/lsappinfo";
const OPEN = "/usr/bin/open";

function run(file, args, timeoutMs = 800) {
  return new Promise((resolve) => {
    try {
      execFile(file, args, { timeout: timeoutMs }, (error, stdout) => {
        resolve(error ? null : String(stdout || ""));
      });
    } catch {
      resolve(null);
    }
  });
}

/** `lsappinfo front` chiqishidan ilova belgisini (ASN) oladi: "ASN:0x0-0x1d01d:". */
function parseFrontAsn(out) {
  const m = String(out || "").match(/ASN:0x[0-9a-f]+-0x[0-9a-f]+:/i);
  return m ? m[0] : null;
}

/**
 * `lsappinfo info <ASN>` chiqishidan pid va bundle id. Ikki shakl tushuniladi:
 * to'liq (`bundleID="com.apple.TextEdit"`, `pid = 1234`) va -only shakli
 * (`"CFBundleIdentifier"="com.apple.TextEdit"`, `"pid"=1234`).
 */
function parseAppInfo(out) {
  const text = String(out || "");
  const pid = Number(text.match(/"?pid"?\s*=\s*(\d+)/)?.[1]);
  const bundleId =
    text.match(/bundleID\s*=\s*"([^"]+)"/)?.[1] || text.match(/"CFBundleIdentifier"\s*=\s*"([^"]+)"/)?.[1] || null;
  return { pid: Number.isFinite(pid) && pid > 0 ? pid : null, bundleId };
}

async function frontAsn() {
  return parseFrontAsn(await run(LSAPPINFO, ["front"]));
}

/** Oldinda turgan ilova: { kind: "mac-app", asn, pid, bundleId } yoki null. */
async function captureFrontApp() {
  if (process.platform !== "darwin") return null;
  const asn = await frontAsn();
  if (!asn) return null;
  const info = parseAppInfo(await run(LSAPPINFO, ["info", asn]));
  return { kind: "mac-app", asn, pid: info.pid, bundleId: info.bundleId };
}

/** Gapla'ning o'zi emas va qaytarib bo'ladigan ilova bo'lsa — «Joylash» nishoni bo'la oladi. */
function isRestorableMacTarget(target, ownPid = process.pid) {
  return Boolean(target && target.kind === "mac-app" && target.asn && target.bundleId && target.pid && target.pid !== ownPid);
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Nishon ilovani oldinga chiqaradi va haqiqatan oldinda ekanini tekshiradi. Tarjimon «panel» oyna — u Gapla'ni
 * oldinga chiqarmaydi, shuning uchun odatda nishon allaqachon oldinda turadi. Bo'lmasa `open -b` bilan chaqiriladi.
 */
async function bringToFront(target) {
  if (!isRestorableMacTarget(target)) return false;
  if ((await frontAsn()) === target.asn) return true;
  await run(OPEN, ["-b", target.bundleId], 1500);
  for (let i = 0; i < 6; i += 1) {
    await wait(80);
    if ((await frontAsn()) === target.asn) return true;
  }
  return false;
}

module.exports = { parseFrontAsn, parseAppInfo, captureFrontApp, isRestorableMacTarget, bringToFront };
