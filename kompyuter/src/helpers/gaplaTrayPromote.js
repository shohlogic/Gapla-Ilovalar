// Gapla (egasi, 2026-11-11: «shu kichik logoni olib tashlaylik … buni o'rniga uni taskbarga qo'yish kerak, masofadan
// boshqarayotganimda ochish oson bo'ladi»): Windows 11 yangi tray belgisini yashirin joyga qo'yadi. Gapla belgisi
// vazifalar panelining o'zida (soat yonida) ko'rinsin — Explorer'ning shu ilova uchun «IsPromoted» qiymati 1 qilinadi.
// Faqat bir marta va faqat qiymat hali qo'yilmagan bo'lsa: egasi keyin yashirsa, qaytadan chiqarilmaydi.
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");
const debugLogger = require("./debugLogger");

const NOTIFY_ICON_KEY = "HKCU\\Control Panel\\NotifyIconSettings";
const RETRY_MS = 10_000;
const MAX_TRIES = 6;

function run(args) {
  return new Promise((resolve) => {
    execFile("reg", args, { windowsHide: true }, (error, stdout) =>
      resolve(error ? null : String(stdout || ""))
    );
  });
}

// `reg query … /s` chiqishidan har bir ichki kalit uchun qiymatlar.
function parseEntries(stdout) {
  const entries = [];
  let current = null;
  for (const raw of stdout.split(/\r?\n/)) {
    const line = raw.trimEnd();
    if (/^HKEY_/i.test(line)) {
      current = { key: line, values: {} };
      entries.push(current);
      continue;
    }
    const match = /^\s+(\S+)\s+(REG_\w+)\s+(.*)$/.exec(line);
    if (match && current) current.values[match[1]] = match[3].trim();
  }
  return entries;
}

function matchesExe(entryPath, exePath) {
  if (!entryPath) return false;
  const a = entryPath.toLowerCase();
  const b = exePath.toLowerCase();
  if (a === b) return true;
  // Explorer yo'lni ba'zan ma'lum papka GUID'i bilan yozadi: {F1B32785-…}\Programs\Gapla\Gapla.exe
  const tail = b.split("\\").slice(-3).join("\\");
  return a.startsWith("{") && a.endsWith(`\\${tail}`);
}

async function tryPromote(exePath, marker, attempt) {
  const stdout = await run(["query", NOTIFY_ICON_KEY, "/s"]);
  const entry = stdout
    ? parseEntries(stdout).find((e) => matchesExe(e.values.ExecutablePath, exePath))
    : null;
  if (!entry) {
    if (attempt < MAX_TRIES) {
      setTimeout(() => void tryPromote(exePath, marker, attempt + 1), RETRY_MS).unref?.();
    }
    return;
  }
  if (entry.values.IsPromoted === undefined) {
    const ok = await run(["add", entry.key, "/v", "IsPromoted", "/t", "REG_DWORD", "/d", "1", "/f"]);
    debugLogger.info("Gapla tray icon promoted to the taskbar", { ok: ok !== null }, "tray");
    if (ok === null) return;
  }
  try {
    fs.writeFileSync(marker, new Date().toISOString());
  } catch {
    // Belgi yozilmasa, keyingi ishga tushishda qiymat bor-yo'qligi yana tekshiriladi — zararsiz.
  }
}

function promoteWindowsTrayIcon({ userDataDir, exePath }) {
  if (process.platform !== "win32" || !userDataDir || !exePath) return;
  const marker = path.join(userDataDir, "gapla-tray-promoted.flag");
  if (fs.existsSync(marker)) return;
  // Explorer belgi uchun yozuvni birinchi ko'rsatishda yaratadi — biroz kutib boshlaymiz.
  setTimeout(() => void tryPromote(exePath, marker, 1), 3_000).unref?.();
}

module.exports = { promoteWindowsTrayIcon, parseEntries, matchesExe };
