// Gapla: umumiy bufer (G8) — Alt+B oynasi va fon kuzatuvi ulanadigan joy (asosiy jarayon).
const path = require("path");
const { app, BrowserWindow, ipcMain, screen } = require("electron");
const debugLogger = require("./debugLogger");
const DevServerManager = require("./devServerManager");
const { GaplaBufer } = require("./gaplaBufer");
const { createHotkeyRepeatGate } = require("./hotkeyRepeatGate");
const GAPLA = require("../constants/gapla.json");

const BUFER_HOTKEY = "Alt+B";
const SIZE = { width: 420, height: 540 };
// Oyna ishga tushgandan keyin yashirin tayyorlanadi — birinchi Alt+B ham sahifa yuklanishini kutmaydi.
const PREWARM_DELAY_MS = 4000;

function errorCode(error) {
  if (error?.code === "NO_KEY") return "NO_KEY";
  if (error?.status === 401 || error?.status === 403) return "AUTH";
  if (error?.status === 404) return "GONE";
  if (!error?.status) return "NETWORK";
  return "OTHER";
}

// Mac (G61): tugma Option+B. Oyna «panel» turida — Gapla'ni oldinga chiqarmaydi, yopilganda egasi yozib turgan ilova
// oldinda qoladi va nusxani darhol Cmd+V bilan qo'ya oladi.
const IS_MAC = process.platform === "darwin";

function setupGaplaBufer({ hotkeyManager, environmentManager }) {
  if (process.platform !== "win32" && !IS_MAC) return null;
  let cacheFile = null;
  let legacyCacheFile = null;
  try {
    cacheFile = path.join(app.getPath("userData"), "gapla-bufer-cache.dat");
    legacyCacheFile = path.join(app.getPath("userData"), "gapla-bufer-cache.json");
  } catch {
    cacheFile = null;
  }
  const bufer = new GaplaBufer({
    baseUrl: GAPLA.bridgeUrl,
    getKey: () => environmentManager?.getCustomTranscriptionKey?.() || "",
    cacheFile,
    legacyCacheFile,
  });
  bufer.start();
  app.on("before-quit", () => bufer.persistNow());

  let win = null;
  let ready = false;
  let pendingOpen = false;

  const isBuferSender = (event) => Boolean(win && !win.isDestroyed() && event.sender === win.webContents);
  const wrap = (fn) => async (event, ...args) => {
    if (!isBuferSender(event)) return { ok: false, code: "OTHER" };
    try {
      return { ok: true, data: await fn(...args) };
    } catch (error) {
      debugLogger.warn("Gapla bufer request failed", { status: error?.status, code: error?.code }, "bufer");
      return { ok: false, code: errorCode(error), status: error?.status };
    }
  };
  // Sahifa tinglovchini ulab, shu so'rovni yuboradi — shundan keyin u «ochildi» xabarini qabul qila oladi.
  // Oyna sahifa tayyor bo'lishidan oldin ochilgan bo'lsa, javobda open: true — sahifa o'zi yangilaydi.
  ipcMain.handle(
    "gapla-bufer-cached",
    wrap(() => {
      ready = true;
      const open = pendingOpen;
      pendingOpen = false;
      return { ...bufer.cached(), open };
    })
  );
  ipcMain.handle("gapla-bufer-list", wrap(() => bufer.list()));
  ipcMain.handle("gapla-bufer-copy", wrap((id) => bufer.copy(id)));
  ipcMain.handle("gapla-bufer-pin", wrap((id, value) => bufer.pin(id, value)));
  ipcMain.handle("gapla-bufer-delete", wrap((id) => bufer.remove(id)));
  ipcMain.on("gapla-bufer-close", (event) => {
    if (isBuferSender(event) && win.isVisible()) win.hide();
  });

  function create() {
    win = new BrowserWindow({
      ...SIZE,
      title: "Gapla — bufer",
      frame: false,
      resizable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      show: false,
      backgroundColor: "#18181b",
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
    win.on("blur", () => {
      if (win && !win.isDestroyed() && win.isVisible()) win.hide();
    });
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
            win.loadURL(`${DevServerManager.DEV_SERVER_URL}?gapla-bufer=true`)
          )
        : (() => {
            const fileInfo = DevServerManager.getAppFilePath(false);
            if (!fileInfo) return Promise.reject(new Error("Failed to get app file path"));
            return win.loadFile(fileInfo.path, { query: { ...fileInfo.query, "gapla-bufer": "true" } });
          })();
    void load.catch((error) => {
      debugLogger.warn("Failed to load Gapla bufer window", { error: error.message }, "bufer");
    });
  }

  // Kursor turgan ekranning o'rtasida ochiladi. Saqlangan ro'yxat xabar bilan birga boradi va darhol chiqadi;
  // oyna keyin serverdan yangisini jimgina so'raydi. Fonda davriy so'rov yo'q.
  function toggle() {
    if (!win || win.isDestroyed()) create();
    if (win.isVisible()) {
      win.hide();
      return;
    }
    const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    const area = display.workArea || display.bounds;
    win.setBounds({
      x: Math.round(area.x + (area.width - SIZE.width) / 2),
      y: Math.round(area.y + (area.height - SIZE.height) / 2),
      ...SIZE,
    });
    if (ready) win.webContents.send("gapla-bufer-opened", bufer.cached());
    else pendingOpen = true;
    if (IS_MAC) {
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

  const isPress = createHotkeyRepeatGate();
  void hotkeyManager
    .registerSlot("gaplaBufer", BUFER_HOTKEY, () => {
      if (isPress()) toggle();
    })
    .then((result) => {
      if (!result?.success) {
        debugLogger.warn("Gapla bufer hotkey not registered", { hotkey: BUFER_HOTKEY, error: result?.error }, "bufer");
      } else {
        debugLogger.info("Gapla bufer hotkey registered", { hotkey: BUFER_HOTKEY }, "bufer");
      }
    })
    .catch((error) => debugLogger.warn("Gapla bufer hotkey failed", { error: error?.message }, "bufer"));

  return { bufer, toggle };
}

module.exports = { setupGaplaBufer };
