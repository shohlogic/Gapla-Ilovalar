// Gapla: Lokal rejim (RubaiSTT kompyuterda) faqat model ilova ichida kelganda ko'rsatiladi.
// Windows o'rnatuvchisida model bor (electron-builder.json → win.extraResources). Mac yig'masida hozircha yo'q
// (egasi, 2026-11-14: «hozircha unda lokal bo'lmaydi»), shuning uchun Mac'da menyuda Tez, O'rta va Sekin qoladi.
const fs = require("fs");
const path = require("path");
const GAPLA = require("../constants/gapla.json");
const registry = require("../models/modelRegistryData.json");

let cached;

function localModelPath() {
  const fileName = registry.whisperModels?.[GAPLA.localWhisperModel]?.fileName;
  if (!fileName) return null;
  const candidates = [];
  if (process.resourcesPath) candidates.push(path.join(process.resourcesPath, "models", fileName));
  candidates.push(path.join(__dirname, "..", "..", "resources", "models", fileName));
  return candidates.find((p) => fs.existsSync(p)) || null;
}

function isGaplaLocalAvailable() {
  if (cached === undefined) cached = Boolean(localModelPath());
  return cached;
}

/** Shu kompyuterda ishlaydigan rejimlar: model bo'lmasa Lokal olib tashlanadi. */
function gaplaModesForThisComputer(modes = GAPLA.modes, localAvailable = isGaplaLocalAvailable()) {
  return localAvailable ? modes : modes.filter((mode) => !mode.local);
}

module.exports = { isGaplaLocalAvailable, gaplaModesForThisComputer };
