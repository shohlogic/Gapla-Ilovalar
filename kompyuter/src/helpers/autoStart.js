// Launch at login, for ipcHandlers.js and main.js. setLoginItemSettings covers
// macOS and Windows; on Linux it does nothing, so an XDG autostart entry stands in
// (linuxAutostart.js). Decisions live in autoStartPolicy.js.

const { app } = require("electron");
const { execFile } = require("child_process");
const debugLogger = require("./debugLogger");
const linuxAutostart = require("./linuxAutostart");
const {
  getLoginItemArgs,
  resolveAutoStartState,
  needsHiddenFlagMigration,
  wasLaunchedHidden,
} = require("./autoStartPolicy");

const isLinux = () => process.platform === "linux";

// Gapla: Windows 11 25H2 (26200) kirishda Run yozuvini «StartupApproved» da qiymati bo'lmasa o'tkazib yuboradi
// (2026-11-10 va 11-11 kirishlari: Shell-Core jurnalida qolgan hamma yozuv ishga tushdi, Gapla'niki — yo'q).
// Electron yoqishda o'sha qiymatni o'chiradi, shuning uchun yoqilgandan keyin «yoqilgan» qiymati (02 + nollar,
// Vazifalar menejeri yozadigan shakl) qo'yiladi. Qiymat bor bo'lsa tegilmaydi — foydalanuvchi Vazifalar
// menejerida o'chirgan bo'lsa, shu tanlov qoladi.
// Run nomi = ilova identifikatori: main.js → BASE_WINDOWS_APP_ID va installer.nsh bilan bir xil tuting.
const STARTUP_APPROVED_KEY =
  "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
const STARTUP_APPROVED_ENABLED = "020000000000000000000000";

function windowsRunName() {
  const channel = process.env.OPENWHISPR_CHANNEL || "production";
  return channel === "production" ? "uz.gapla.windows" : `uz.gapla.windows.${channel}`;
}

function ensureWindowsStartupApproved() {
  if (process.platform !== "win32") return;
  const name = windowsRunName();
  const opts = { windowsHide: true };
  execFile("reg", ["query", STARTUP_APPROVED_KEY, "/v", name], opts, (queryError) => {
    if (!queryError) return;
    execFile(
      "reg",
      ["add", STARTUP_APPROVED_KEY, "/v", name, "/t", "REG_BINARY", "/d", STARTUP_APPROVED_ENABLED, "/f"],
      opts,
      (addError) => {
        if (addError) {
          debugLogger.warn("[Gapla] StartupApproved yozilmadi", { error: addError.message });
        } else {
          debugLogger.info("[Gapla] Kirishda ishga tushish Windows'da tasdiqlandi", { name });
        }
      }
    );
  });
}

function readLoginItemSettings() {
  return app.getLoginItemSettings({ args: getLoginItemArgs(process.platform) });
}

function writeLoginItem(enabled) {
  app.setLoginItemSettings({
    openAtLogin: enabled,
    args: getLoginItemArgs(process.platform),
  });
  if (enabled) ensureWindowsStartupApproved();
}

// { enabled, requiresApproval } — requiresApproval is macOS-only.
function getAutoStartState() {
  if (isLinux()) {
    return { enabled: linuxAutostart.isAutostartEnabled(), requiresApproval: false };
  }
  return resolveAutoStartState({
    platform: process.platform,
    loginItemSettings: readLoginItemSettings(),
  });
}

function setAutoStartEnabled(enabled) {
  if (isLinux()) {
    linuxAutostart.setAutostartEnabled(enabled);
    return;
  }
  writeLoginItem(enabled);
}

function wasLaunchedAtLoginHidden() {
  return wasLaunchedHidden({
    platform: process.platform,
    argv: process.argv,
    loginItemSettings: process.platform === "darwin" ? app.getLoginItemSettings() : null,
  });
}

// Repairs an entry that still exists but no longer starts this executable, or
// starts it without the flag that sends it to the tray. True when it rewrote one.
function syncAutoStartEntry() {
  if (isLinux()) return linuxAutostart.syncAutostartEntry();

  const loginItemSettings = readLoginItemSettings();
  // Gapla: eski o'rnatishda (yoki Electron o'chirib yuborgan bo'lsa) tasdiq qiymati har ochilishda tiklanadi.
  if (loginItemSettings?.openAtLogin) ensureWindowsStartupApproved();
  if (!needsHiddenFlagMigration({ platform: process.platform, loginItemSettings })) return false;

  writeLoginItem(true);
  return true;
}

module.exports = {
  getAutoStartState,
  setAutoStartEnabled,
  wasLaunchedAtLoginHidden,
  syncAutoStartEntry,
};
