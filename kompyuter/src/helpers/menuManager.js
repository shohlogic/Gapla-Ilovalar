const { Menu } = require("electron");
const { i18nMain } = require("./i18nMain");

// Gapla (G61): Mac tepasidagi menyu o'zbekcha. Electron «role» bandlariga o'z nomini inglizcha qo'yadi
// («Hide Gapla», «Edit», «Window»), shuning uchun har bandning nomi shu yerda yozilgan.
function macAppSubmenu(onOpenSettings) {
  return [
    { role: "about", label: "Gapla haqida" },
    { type: "separator" },
    {
      label: i18nMain.t("menu.settings"),
      accelerator: "Command+,",
      click: () => onOpenSettings?.(),
    },
    { type: "separator" },
    { role: "services", label: "Xizmatlar" },
    { type: "separator" },
    { role: "hide", label: "Gapla'ni yashirish" },
    { role: "hideOthers", label: "Boshqalarini yashirish" },
    { role: "unhide", label: "Hammasini ko'rsatish" },
    { type: "separator" },
    { role: "quit", label: i18nMain.t("menu.quit") },
  ];
}

class MenuManager {
  static setupMainMenu(onOpenSettings) {
    if (process.platform === "darwin") {
      const template = [
        {
          label: i18nMain.t("menu.appLabel"),
          submenu: macAppSubmenu(onOpenSettings),
        },
      ];
      const menu = Menu.buildFromTemplate(template);
      Menu.setApplicationMenu(menu);
    }
  }

  static setupControlPanelMenu(controlPanelWindow, onOpenSettings) {
    if (process.platform === "darwin") {
      // On macOS, create a proper application menu
      const template = [
        {
          label: i18nMain.t("menu.appLabel"),
          submenu: macAppSubmenu(onOpenSettings),
        },
        {
          label: "Tahrirlash",
          submenu: [
            { role: "undo", label: "Bekor qilish" },
            { role: "redo", label: "Qaytarish" },
            { type: "separator" },
            { role: "cut", label: "Kesish" },
            { role: "copy", label: "Nusxa olish" },
            { role: "paste", label: "Joylash" },
            { role: "pasteAndMatchStyle", label: "Uslubni moslab joylash" },
            { role: "delete", label: "O'chirish" },
            { role: "selectAll", label: "Hammasini belgilash" },
            { type: "separator" },
            {
              label: i18nMain.t("menu.speech"),
              submenu: [
                { role: "startSpeaking", label: "O'qib berish" },
                { role: "stopSpeaking", label: "O'qishni to'xtatish" },
              ],
            },
          ],
        },
        {
          label: "Ko'rinish",
          submenu: [
            { role: "reload", label: "Qayta yuklash" },
            { role: "forceReload", label: "Majburan qayta yuklash" },
            { role: "toggleDevTools", label: "Dasturchi vositalari" },
            { type: "separator" },
            { role: "resetZoom", label: "Asl o'lcham" },
            { role: "zoomIn", label: "Kattalashtirish" },
            { role: "zoomOut", label: "Kichraytirish" },
            { type: "separator" },
            { role: "togglefullscreen", label: "To'liq ekran" },
          ],
        },
        {
          label: "Oyna",
          submenu: [
            { role: "minimize", label: "Yig'ish" },
            { role: "close", label: "Yopish" },
            { type: "separator" },
            { role: "front", label: "Hammasini oldinga chiqarish" },
            { type: "separator" },
            { role: "window" },
          ],
        },
        // Gapla: macOS «Help → Learn More» OpenWhispr GitHub sahifasini ochardi — olib tashlandi (2026-11-11, G44).
      ];

      const menu = Menu.buildFromTemplate(template);
      Menu.setApplicationMenu(menu);
    } else {
      // For Windows/Linux, keep the window-specific menu
      const template = [
        {
          label: i18nMain.t("menu.file"),
          submenu: [
            {
              label: i18nMain.t("menu.settings"),
              accelerator: "Ctrl+,",
              click: () => onOpenSettings?.(),
            },
            { type: "separator" },
            { role: "close", label: i18nMain.t("menu.closeWindow") },
          ],
        },
        {
          label: "Edit",
          submenu: [
            { role: "undo" },
            { role: "redo" },
            { type: "separator" },
            { role: "cut" },
            { role: "copy" },
            { role: "paste" },
            { type: "separator" },
            { role: "selectAll" },
          ],
        },
        {
          label: "View",
          submenu: [
            { role: "reload" },
            { role: "forceReload" },
            { role: "toggleDevTools" },
            { type: "separator" },
            { role: "resetZoom" },
            { role: "zoomIn" },
            { role: "zoomOut" },
            { type: "separator" },
            { role: "togglefullscreen" },
          ],
        },
      ];

      const menu = Menu.buildFromTemplate(template);
      controlPanelWindow.setMenu(menu);
    }
  }
}

module.exports = MenuManager;
