// Gapla tarjimoni (G56, 2026-11-13) — Alt+T oynasi (asosiy jarayon). Egasi: «pc tomonida esa alt+t ga bosganimda o'sha
// tarjima oynasi ochiladi, unda ham huddi shunaqa mobildagi kabi ishlashi kerak bo'ladi», «tarjima qilinadigan matnni
// kiritishda kopyalaganimni paste qilish yoki audio orqali yangi gap yozish imkoniyatim bo'lishi lozim».
// Namuna — Android 1.4.9 (GaplaTarjimonActivity.kt). Kalit va server so'rovi shu jarayonda, oynaga kalit berilmaydi.
//
// Oyna joriy ilova ustida, diktovka shari chiqadigan joydan (ekran pasti, o'rtada) yuqoriroqda ochiladi.
// Alt+T yoki Esc yopadi. «Joylash» — Alt+T bosilganda oldinda turgan oynani eslab qoladi va tanlangan variantni o'sha
// oynadagi maydonga joylaydi (diktovka joylash yo'lining o'zi, `windows-fast-paste --restore-window`).
// «Gapirish» — oddiy diktovka (egasi tanlagan rejim bilan); natija ilovaga joylanmaydi, tarjimon maydoniga tushadi
// (gaplaTarjimaSink.js, ipcHandlers.js → "paste-text").
//
// Mac (G61, 2026-11-14): tugma Option+T (Electron'da «Alt» Mac'da Option). Oyna «panel» turida — Spotlight kabi
// Gapla'ni oldinga chiqarmaydi, egasi yozib turgan ilova oldinda qoladi. Nishon ilova gaplaMacFront.js bilan
// eslab qolinadi va qaytariladi; matnni joylash uchun Mac «Maxsus imkoniyatlar» (Accessibility) ruxsatini so'raydi.
const path = require("path");
const { spawn } = require("child_process");
const { app, BrowserWindow, ipcMain, screen, clipboard, net, systemPreferences } = require("electron");
const debugLogger = require("./debugLogger");
const DevServerManager = require("./devServerManager");
const { createHotkeyRepeatGate } = require("./hotkeyRepeatGate");
const { isRestorablePasteTarget, parseWindowHandle } = require("./windowsPasteTarget");
const macFront = require("./gaplaMacFront");
const { tarjima } = require("./gaplaTarjima");
const sink = require("./gaplaTarjimaSink");
const GAPLA = require("../constants/gapla.json");

const IS_MAC = process.platform === "darwin";
const TARJIMA_HOTKEY = "Alt+T";
const SIZE = { width: 460, height: 620 };
// Diktovka shari ekran pastida, o'rtada — tarjimon undan yuqorida turadi, gapirganda shar ko'rinib tursin.
const ORB_CLEARANCE_PX = 200;
const PREWARM_DELAY_MS = 5000;
// Diktovka tugagach matn bir oz kechroq kelishi mumkin (shar ham shuni kutadi) — shuncha kutib, qabul qiluvchi olinadi.
const SINK_GRACE_MS = 3000;

function runDetect(binary) {
  return new Promise((resolve) => {
    let out = "";
    let done = false;
    const finish = (value) => {
      if (done) return;
      done = true;
      resolve(value);
    };
    let child;
    try {
      child = spawn(binary, ["--detect-only"], { windowsHide: true });
    } catch {
      finish(null);
      return;
    }
    const timer = setTimeout(() => {
      try {
        child.kill();
      } catch {}
      finish(null);
    }, 700);
    child.stdout?.on("data", (d) => (out += d.toString()));
    child.on("error", () => {
      clearTimeout(timer);
      finish(null);
    });
    child.on("close", () => {
      clearTimeout(timer);
      const id = out.match(/TARGET\s+(\S+)/)?.[1];
      if (!id) return finish(null);
      finish({
        kind: "win-hwnd",
        id,
        exeName: out.match(/^EXE_NAME (.+)$/m)?.[1]?.trim() || null,
      });
    });
  });
}

// `--restore-window <hwnd> --detect-only`: oynani oldinga chiqaradi va oldinda qaysi oyna turganini aytadi.
function restoreAndCheck(binary, id) {
  return new Promise((resolve) => {
    let out = "";
    let done = false;
    const finish = (v) => {
      if (!done) {
        done = true;
        resolve(v);
      }
    };
    let child;
    try {
      child = spawn(binary, ["--restore-window", String(id), "--detect-only"], { windowsHide: true });
    } catch {
      finish(false);
      return;
    }
    const timer = setTimeout(() => {
      try {
        child.kill();
      } catch {}
      finish(false);
    }, 1500);
    child.stdout?.on("data", (d) => (out += d.toString()));
    child.on("error", () => {
      clearTimeout(timer);
      finish(false);
    });
    child.on("close", () => {
      clearTimeout(timer);
      const front = out.match(/TARGET\s+(\S+)/)?.[1];
      const wanted = parseWindowHandle(id);
      finish(wanted !== null && front != null && parseWindowHandle(front) === wanted);
    });
  });
}

function errorPayload(error) {
  return { ok: false, status: Number(error?.status ?? 0), code: error?.code || null };
}

function setupGaplaTarjima({ hotkeyManager, environmentManager, windowManager, clipboardManager }) {
  if (process.platform !== "win32" && !IS_MAC) return null;

  let win = null;
  let ready = false;
  let pendingOpen = false;
  let target = null; // Alt+T bosilganda oldinda turgan oyna — «Joylash» shu yerga
  let dictating = false; // «Gapirish» bilan boshlangan diktovka davom etyapti
  let sawActive = false;
  let graceTimer = null;

  const isOwnSender = (event) => Boolean(win && !win.isDestroyed() && event.sender === win.webContents);
  const send = (channel, payload) => {
    if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
  };

  function endDictationSession() {
    dictating = false;
    sawActive = false;
    if (graceTimer) clearTimeout(graceTimer);
    graceTimer = null;
    sink.clearSink();
  }

  // windowManager.setDictationLifecycleState chaqiradi: oynaga yozish holati boradi («Gapirish» ↔ «To'xtatish»).
  function onDictationState(state) {
    if (!dictating) return;
    send("gapla-tarjima-dictation-state", state);
    if (state !== "idle") {
      sawActive = true;
      if (graceTimer) clearTimeout(graceTimer);
      graceTimer = null;
      return;
    }
    if (!sawActive) return;
    // Yozuv tugadi: matn kelsa qabul qiluvchi uni oladi; kelmasa (ovoz yo'q, bekor qilindi) — bir ozdan keyin tushadi.
    if (graceTimer) clearTimeout(graceTimer);
    graceTimer = setTimeout(() => {
      graceTimer = null;
      if (dictating) {
        endDictationSession();
        send("gapla-tarjima-dictation-state", "idle");
      }
    }, SINK_GRACE_MS);
  }

  function hide() {
    if (!win || win.isDestroyed() || !win.isVisible()) return;
    // Gapirayotgan paytda yopilsa yozuv bekor qilinadi — matn adashib boshqa ilovaga joylanmasin.
    if (dictating) {
      windowManager?.sendCancelActiveDictation?.();
      endDictationSession();
    }
    win.hide();
  }

  ipcMain.handle("gapla-tarjima-ready", (event) => {
    if (!isOwnSender(event)) return { open: false };
    ready = true;
    const open = pendingOpen;
    pendingOpen = false;
    return { open };
  });

  ipcMain.handle("gapla-tarjima-translate", async (event, matn, til) => {
    if (!isOwnSender(event)) return { ok: false, status: 0 };
    try {
      const natija = await tarjima({
        baseUrl: GAPLA.bridgeUrl,
        key: environmentManager?.getCustomTranscriptionKey?.() || "",
        matn,
        til,
        fetchImpl: (url, init) => net.fetch(url, init),
      });
      return { ok: true, data: natija };
    } catch (error) {
      debugLogger.warn("Gapla tarjima failed", { status: error?.status, code: error?.code }, "tarjima");
      return errorPayload(error);
    }
  });

  ipcMain.handle("gapla-tarjima-read-clipboard", (event) => (isOwnSender(event) ? clipboard.readText() : ""));

  ipcMain.handle("gapla-tarjima-copy", (event, text) => {
    if (!isOwnSender(event)) return false;
    clipboard.writeText(String(text ?? ""));
    return true;
  });

  // «Joylash»: oynani yashirib, tanlangan matnni Alt+T dan oldingi oynaga joylaydi. U oyna yo'q bo'lsa (yoki Gapla'ning
  // o'zi bo'lsa) matn faqat buferga tushadi — oyna buni aytadi.
  ipcMain.handle("gapla-tarjima-place", async (event, text) => {
    if (!isOwnSender(event)) return { ok: false };
    const matn = String(text ?? "");
    if (IS_MAC) return placeMac(matn);
    const ownWindowHandles = BrowserWindow.getAllWindows()
      .filter((w) => !w.isDestroyed())
      .map((w) => w.getNativeWindowHandle());
    const targetWindow =
      target &&
      target.id &&
      isRestorablePasteTarget({ target, ownExeName: path.basename(process.execPath), ownWindowHandles })
        ? target.id
        : null;
    if (!targetWindow) {
      clipboard.writeText(matn);
      return { ok: true, pasted: false };
    }
    // Avval nishon oynani oldinga chiqarib, haqiqatan oldinda ekanini tekshiramiz — tarjimon hali oldinda turgan
    // paytda (Windows oynani oldinga chiqarishga faqat oldindagi dasturga ruxsat beradi). Chiqmasa, joylanmaydi:
    // yordamchi dastur aks holda matnni oldinda turgan boshqa oynaga joylab yuboradi (sinovda Claude oynasiga tushdi).
    const binary = clipboardManager?.resolveWindowsFastPasteBinary?.();
    const restored = binary ? await restoreAndCheck(binary, targetWindow) : false;
    if (!restored) {
      clipboard.writeText(matn);
      return { ok: true, pasted: false, reason: "restore" };
    }
    hide();
    await new Promise((resolve) => setTimeout(resolve, 80));
    try {
      const result = await clipboardManager.pasteText(matn, { targetWindow, silentAccessibilityCheck: true });
      return { ok: true, pasted: result?.success !== false };
    } catch (error) {
      debugLogger.warn("Gapla tarjima place failed", { error: error?.message }, "tarjima");
      clipboard.writeText(matn);
      return { ok: true, pasted: false };
    }
  });

  // Mac: ruxsat bo'lmasa yoki nishon ilova oldinga chiqmasa — joylanmaydi, matn buferda qoladi (oyna buni aytadi).
  // Ikkalasi ham oyna yopilishidan oldin tekshiriladi: aks holda xabar ko'rinmay qoladi.
  async function placeMac(matn) {
    if (!macFront.isRestorableMacTarget(target)) {
      clipboard.writeText(matn);
      return { ok: true, pasted: false };
    }
    if (!systemPreferences.isTrustedAccessibilityClient(false)) {
      clipboard.writeText(matn);
      return { ok: true, pasted: false, reason: "accessibility" };
    }
    if (!(await macFront.bringToFront(target))) {
      clipboard.writeText(matn);
      return { ok: true, pasted: false, reason: "restore" };
    }
    hide();
    await new Promise((resolve) => setTimeout(resolve, 120));
    try {
      const result = await clipboardManager.pasteText(matn, { silentAccessibilityCheck: true });
      return { ok: true, pasted: result?.success !== false && result?.pasted !== false };
    } catch (error) {
      debugLogger.warn("Gapla tarjima place failed", { error: error?.message }, "tarjima");
      clipboard.writeText(matn);
      return { ok: true, pasted: false };
    }
  }

  // «Gapirish» / «To'xtatish»: oddiy diktovka tugmasining o'zi (Alt+D bilan bir xil yo'l va rejim).
  ipcMain.handle("gapla-tarjima-dictate", (event) => {
    if (!isOwnSender(event)) return { ok: false };
    if (dictating) {
      windowManager?.sendToggleDictation?.();
      return { ok: true, recording: false };
    }
    dictating = true;
    sawActive = false;
    sink.setSink((text) => {
      endDictationSession();
      send("gapla-tarjima-dictated", text);
      send("gapla-tarjima-dictation-state", "idle");
    });
    windowManager?.sendToggleDictation?.();
    return { ok: true, recording: true };
  });

  ipcMain.on("gapla-tarjima-close", (event) => {
    if (isOwnSender(event)) hide();
  });

  function create() {
    win = new BrowserWindow({
      ...SIZE,
      title: "Gapla — tarjimon",
      frame: false,
      resizable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      show: false,
      backgroundColor: "#1c1917",
      ...(IS_MAC ? { type: "panel", hiddenInMissionControl: true } : {}),
      webPreferences: {
        preload: path.join(__dirname, "..", "..", "preload.js"),
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
      },
    });
    ready = false;
    pendingOpen = false;
    win.on("closed", () => {
      win = null;
      ready = false;
    });
    win.webContents.on("did-start-loading", () => {
      ready = false;
    });
    const load =
      process.env.NODE_ENV === "development"
        ? DevServerManager.waitForDevServer().then(() =>
            win.loadURL(`${DevServerManager.DEV_SERVER_URL}?gapla-tarjima=true`)
          )
        : (() => {
            const fileInfo = DevServerManager.getAppFilePath(false);
            if (!fileInfo) return Promise.reject(new Error("Failed to get app file path"));
            return win.loadFile(fileInfo.path, { query: { ...fileInfo.query, "gapla-tarjima": "true" } });
          })();
    void load.catch((error) => {
      debugLogger.warn("Failed to load Gapla tarjima window", { error: error.message }, "tarjima");
    });
  }

  function place() {
    const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    const area = display.workArea || display.bounds;
    const x = Math.round(area.x + (area.width - SIZE.width) / 2);
    const fromBottom = area.y + area.height - ORB_CLEARANCE_PX - SIZE.height;
    const y = Math.round(Math.max(area.y + 16, fromBottom));
    win.setBounds({ x, y, ...SIZE });
  }

  async function toggle() {
    if (!win || win.isDestroyed()) create();
    if (win.isVisible()) {
      hide();
      return;
    }
    // Oyna ochilishidan oldin oldinda turgan oyna — «Joylash» nishoni.
    if (IS_MAC) {
      target = await macFront.captureFrontApp();
    } else {
      const binary = clipboardManager?.resolveWindowsFastPasteBinary?.();
      target = binary ? await runDetect(binary) : null;
    }
    place();
    if (ready) send("gapla-tarjima-opened");
    else pendingOpen = true;
    if (IS_MAC) {
      // Panel Gapla'ni oldinga chiqarmay klaviaturani oladi (showInactive + focus).
      win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      win.showInactive();
    } else {
      win.show();
    }
    win.focus();
  }

  const prewarm = setTimeout(() => {
    if (!win || win.isDestroyed()) create();
  }, PREWARM_DELAY_MS);
  prewarm.unref?.();

  const api = { toggle: () => void toggle(), hide, onDictationState };
  if (windowManager) windowManager.gaplaTarjima = api;

  const isPress = createHotkeyRepeatGate();
  void hotkeyManager
    .registerSlot("gaplaTarjima", TARJIMA_HOTKEY, () => {
      if (isPress()) void toggle();
    })
    .then((result) => {
      if (!result?.success) {
        debugLogger.warn("Gapla tarjima hotkey not registered", { hotkey: TARJIMA_HOTKEY, error: result?.error }, "tarjima");
      } else {
        debugLogger.info("Gapla tarjima hotkey registered", { hotkey: TARJIMA_HOTKEY }, "tarjima");
      }
    })
    .catch((error) => debugLogger.warn("Gapla tarjima hotkey failed", { error: error?.message }, "tarjima"));

  app.on("before-quit", () => sink.clearSink());
  return api;
}

module.exports = { setupGaplaTarjima, TARJIMA_HOTKEY };
