// Gapla: ikki tugma — `dictationKey` dagi asosiy tugma (Alt+D) bir bosishda yoqadi/o'chiradi,
// `holdKey` (Shift+Alt+D) esa bosib turilganda yozadi. Ikkalasi ham diktovka slotida turadi;
// bosib turish tugmasi Windows'da past darajadagi tinglovchi orqali ishlaydi.
const GAPLA = require("../constants/gapla.json");

function normalize(hotkey) {
  return String(hotkey || "")
    .split("+")
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
    .sort()
    .join("+");
}

const HOLD_KEY = normalize(GAPLA.holdKey);

function isGaplaHoldKey(hotkey) {
  return process.platform === "win32" && Boolean(HOLD_KEY) && normalize(hotkey) === HOLD_KEY;
}

module.exports = { isGaplaHoldKey };
