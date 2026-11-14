// Gapla: ekran o'rtasidagi zarra shar (G47) — diktovka oynasi tomoni.
// Ovoz yozish mantig'iga tegmaydi: faqat uning holatini kuzatib, sharga signal va ovoz darajasini yuboradi.
// Signallar: "rec" → "proc" → "done" (matn tayyor) yoki "hide" (Esc, xato, ovoz yo'q, bekor qilish).

// Ishlov tugagach "idle" ba'zan natijadan oldin keladi — shuncha kutib, natija kelmasa shar yo'qoladi.
const IDLE_GRACE_MS = 400;
// Ovoz darajasi desibel bo'yicha (bilim/gapla-yozish-animatsiyasi-tanlov.md, «Ovoz darajasi qanday hisoblanadi»):
// 40 ms RMS → dB → pastki chegara = 0, yuqori chegara = 1. Egasi (2026-11-11): «animatsiya juda sekin va qimirlagani
// bilinmaydi». Mezon — tanlov sahifasining sinov ovozi: 10 s gapda o'rtacha ~0,23, 90-foizi ~0,7, eng balandi 1, jimlikda
// ≤ 0,05. Chegaralar shu kompyuter mikrofonida o'lchandi (egasining 8 ta yozuvi, 40 ms bo'laklar, jimlik −45…−52 dB):
// −42…−22 dB da o'rtacha 0,30, 90-foizi 0,71, eng balandi 1, jimlik 0. Namunadagi −50…−15 dB da 90-foizi 0,64 edi.
// Bilim fayliga ko'ra jihozga qarab faqat shu ikki chegara o'zgaradi.
const LEVEL_FLOOR_DB = -42;
const LEVEL_CEIL_DB = -22;

// Tashxis (egasi 2026-11-12: «Hali kuchsiz»): oxirgi ~100 s dagi har o'lchov — [vaqt, dB, daraja, sikl].
// `globalThis.__gaplaOrbLevelLog` — faqat raqamlar, ovozning o'zi saqlanmaydi.
function noteLevel(rms, level) {
  try {
    const numeric = Number(rms);
    const log = (globalThis.__gaplaOrbLevelLog ||= []);
    log.push([
      Date.now(),
      Number.isFinite(numeric) ? Math.round(20 * Math.log10(Math.max(numeric, 1e-6)) * 10) / 10 : null,
      level === null ? null : Math.round(level * 100) / 100,
      phase === "rec" ? cycle : null,
    ]);
    if (log.length > 3000) log.splice(0, log.length - 3000);
  } catch {
    // tashxis ishni to'xtatmasin
  }
}

/** 40 ms RMS (namunalar −1…1) → shar darajasi 0…1. */
export function levelFromRms(rms) {
  const numeric = Number(rms);
  if (!Number.isFinite(numeric)) return null;
  const db = 20 * Math.log10(Math.max(numeric, 1e-6));
  return Math.min(1, Math.max(0, (db - LEVEL_FLOOR_DB) / (LEVEL_CEIL_DB - LEVEL_FLOOR_DB)));
}

// Pastki kapsula (Gapla logosi) oddiy diktovkada umuman ko'rinmaydi — yozish shar bilan ko'rsatiladi.
// Egasi (2026-11-11): «animatsiyamiz chiqishidan avval gapla ni logosi korinyapti, keyin animatsiyamiz chiqyapti,
// bu g'alati». Sabab: kapsula shar tugagach qaytib ko'rinardi, yashirin oynada oxirgi kadr logo bo'lib qolardi va
// keyingi Alt+D da oyna shu kadr bilan ochilardi; mikrofon tayyorlanayotganda ham kapsula ko'rinardi.
// Endi kapsula shar ishlatiladigan yozuvlardan keyin ham yashirin qoladi; faqat shar qatnashmaydigan yozuv
// (Agent paneli, tanishtiruv) uni qaytaradi.
function initialVisible() {
  try {
    return globalThis.localStorage?.getItem("onboardingCompleted") === "true";
  } catch {
    return false;
  }
}

let phase = "idle"; // idle | rec | proc
let cycle = 0;
let idleTimer = null;
let visible = initialVisible();
const listeners = new Set();

function setVisible(next) {
  if (visible === next) return;
  visible = next;
  listeners.forEach((listener) => listener());
}

function send(type) {
  window.electronAPI?.dictationOrbSignal?.(type, cycle);
}

function clearIdleTimer() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = null;
}

function end(type) {
  phase = "idle";
  clearIdleTimer();
  send(type);
}

/** useAudioRecording dagi hayot sikli hisobotidan chaqiriladi. */
export function dictationOrbLifecycle(state, { eligible }) {
  // Tugma bosilishi bilan (mikrofon tayyorlanayotganda) shar chiqa boshlaydi — kapsula oralig'i qolmaydi.
  if (state === "recording" || state === "preparing") {
    if (!eligible) {
      if (phase !== "idle") end("hide");
      setVisible(false);
      return;
    }
    if (phase === "rec") return;
    clearIdleTimer();
    cycle += 1;
    phase = "rec";
    setVisible(true);
    send("rec");
    return;
  }
  if (state === "processing") {
    if (phase === "rec") {
      phase = "proc";
      send("proc");
    }
    return;
  }
  // idle
  if (phase === "rec") {
    end("hide");
  } else if (phase === "proc" && !idleTimer) {
    idleTimer = setTimeout(() => {
      idleTimer = null;
      if (phase === "proc") end("hide");
    }, IDLE_GRACE_MS);
  }
}

/** Matn tayyor bo'ldi (server yoki Lokal javobi keldi). */
export function dictationOrbDone() {
  if (phase === "rec" || phase === "proc") end("done");
}

export function isDictationOrbRecording() {
  return phase === "rec";
}

export function sendDictationOrbLevel(rms) {
  if (phase !== "rec") {
    noteLevel(rms, null);
    return;
  }
  const level = levelFromRms(rms);
  noteLevel(rms, level);
  if (level === null) return;
  window.electronAPI?.dictationOrbLevel?.(level);
}

export function subscribeDictationOrbVisible(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getDictationOrbVisible() {
  return visible;
}
