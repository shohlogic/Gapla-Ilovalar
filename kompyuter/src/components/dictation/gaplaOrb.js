// Gapla: ovoz yozish animatsiyasi — ekran o'rtasidagi zarra shar (G47).
// Yagona namuna: Gapla-Keyboard/bilim/gapla-yozish-animatsiyasi-tanlov.md («Aylanuvchi shar», «Shaffof», «O'rta»).
// Qiymatlar va chizish namunadagi JavaScript'dan aynan ko'chirilgan; faqat "spin" harakati va orqa plansiz ("none") qismi.
// Namunadan farqlar: 1) server javobi 1,7 s dan tez kelsa, «Tayyor» aylantirishning o'sha paytdagi qiymatlaridan
// boshlanadi (`from`) — namunada aylantirish doim 1,7 s edi; 2) silliqlash kadr tezligiga bog'liq emas va egasi namunani
// ko'rgan ekranga (165–180 Hz) moslangan — pastda SHAPE_K.

const CY = [62, 240, 255];
const BL = [76, 125, 255];
const VI = [139, 92, 246];
const PK = [236, 72, 200];
const WH = [235, 245, 255];

export const ORB_SIZE = 176;
export const ORB_TIMING = Object.freeze({ appearMs: 520, procMs: 1700, doneMs: 900, goneMs: 400 });
const ORB_RADIUS = 36;
const PARTICLES = 190;
// «O'rta» tezlik. Namuna har kadrda `ls += (daraja − ls)·0,045`, `lf += …·0,35` qiladi — kadr tezligiga bog'liq.
// Egasi namunani 165–180 Hz ekranda ko'rgan (bu kompyuter: 165 va 180 Hz), u yerda shakl taxminan 3 barobar tez javob
// beradi. Egasi (2026-11-11): «sen menga ko'rsatgan animatsiya bilan realdagi animatsiyani orasida farq bor, sendagi norm
// edi, lekin realdagi … juda kuchsiz». Ilova 60 Hz o'lchovida (0,045) silliqlardi: sinov ovozida to'lqin tebranishi 0,38,
// namunada (180 Hz) 0,65. Shuning uchun qiymat egasi ko'rgan holatga moslandi: 1/60 s ga 0,12 (= 0,045 har kadrda,
// ~170 Hz), rang 0,7 — har qanday kadr tezligida namunadagidek (tebranish 0,63–0,64).
const SHAPE_K = 0.12;
const COLOR_K = 0.7;
// To'lqinning ovozga bog'liq qismi. Namunada 0,22. Egasi (2026-11-12), ovoz sharga yetib borishi va javobi namunadagi
// bilan bir xil o'lchangach: «hozirgidan kora 30% kuchliroq reaksiya berishi kerak, hamma jixozlarda,To'lqin kam» → ×1,3
// (0,286). Sinab ko'rgach yana: «Yana kuchaytir» → yana ×1,3 (0,372).
const WAVE_VOICE = 0.372;
const SPEED = 1;
const QUIET_LEVEL = 0.03;
// Qotib qolmaslik uchun (2026-11-11: sinov to'xtab, shar ekranda 4 daqiqa qoldi): yozish paytida diktovka oynasi
// har ~33 ms da ovoz darajasini yuboradi; 6 s hech narsa kelmasa yoki aylantirish 2 daqiqadan oshsa — shar yo'qoladi.
const REC_SILENCE_MS = 6000;
const PROC_MAX_MS = 120000;

function rgba(c, a) {
  return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + Math.max(0, Math.min(1, a)).toFixed(3) + ")";
}
function mix(a, b, k) {
  k = Math.max(0, Math.min(1, k));
  return [
    Math.round(a[0] + (b[0] - a[0]) * k),
    Math.round(a[1] + (b[1] - a[1]) * k),
    Math.round(a[2] + (b[2] - a[2]) * k),
  ];
}
function clamp(x, a, b) {
  return Math.max(a, Math.min(b, x));
}
// Tanlov sahifasining sinov ovozi (bilim/gapla-yozish-animatsiyasi-tanlov.md, «Sinov ovozi rejimi»), t — soniya.
export function testVoiceLevel(t) {
  const syl = Math.pow(Math.max(0, Math.sin(t * 8.7)), 0.7) * (0.55 + 0.45 * Math.sin(t * 2.1 + 1.3));
  const pause = t % 1.9 > 1.5 ? 0.08 : 1;
  return clamp(syl * pause + 0.07 * Math.sin(t * 27) + 0.05, 0.03, 1);
}
function lerp(a, b, k) {
  return a + (b - a) * k;
}
function ease(x) {
  x = clamp(x, 0, 1);
  return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
}
function back(x) {
  x = clamp(x, 0, 1);
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
}
function fmt(ms) {
  const s = Math.floor(ms / 1000);
  return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
}
// ovozga qarab rang: jim — havorang/ko'k, baland — binafsha/pushti
function hot(c, lf) {
  return mix(c, lf > 0.55 ? PK : VI, lf * 0.95);
}

// Shaffof rejim: soniya orqasida to'q yostiqcha — oq hujjat ustida ham o'qiladi.
function label(g, txt, x, y, size, col) {
  g.save();
  g.globalCompositeOperation = "source-over";
  g.font = "600 " + size + "px Onest, 'Segoe UI', system-ui, sans-serif";
  g.textAlign = "center";
  g.textBaseline = "middle";
  const w = g.measureText ? g.measureText(txt).width : size * 2;
  g.fillStyle = "rgba(7,10,20,.78)";
  g.beginPath();
  g.arc(x - w / 2, y, size * 0.75, Math.PI / 2, Math.PI * 1.5);
  g.arc(x + w / 2, y, size * 0.75, -Math.PI / 2, Math.PI / 2);
  g.closePath();
  g.fill();
  g.shadowColor = rgba(col, 0.9);
  g.shadowBlur = size * 0.6;
  g.fillStyle = "#F4FBFF";
  g.fillText(txt, x, y);
  g.restore();
}

// Shaffofda oq nuqtalar oq hujjatda yo'qolmasin — orqasida kichik to'q yostiqcha.
function dots(g, cx, cy, s, t) {
  const hw = s * 4.4;
  g.fillStyle = "rgba(7,10,20,.78)";
  g.beginPath();
  g.arc(cx - hw + s * 2, cy, s * 2.2, Math.PI / 2, Math.PI * 1.5);
  g.arc(cx + hw - s * 2, cy, s * 2.2, -Math.PI / 2, Math.PI / 2);
  g.closePath();
  g.fill();
  for (let i = 0; i < 3; i++) {
    const a = 0.35 + 0.65 * Math.max(0, Math.sin(t * 4 - i * 0.9));
    g.fillStyle = rgba(WH, a);
    g.beginPath();
    g.arc(cx + (i - 1) * s * 2.6, cy, s, 0, Math.PI * 2);
    g.fill();
  }
}

function check(g, cx, cy, s, k) {
  k = ease(k);
  if (k <= 0) return;
  g.save();
  g.lineCap = "round";
  g.lineJoin = "round";
  g.lineWidth = Math.max(2, s * 0.16);
  g.strokeStyle = rgba(WH, 1);
  g.shadowColor = rgba(CY, 1);
  g.shadowBlur = s * 0.7;
  const p1 = [cx - s * 0.45, cy + s * 0.02];
  const p2 = [cx - s * 0.1, cy + s * 0.36];
  const p3 = [cx + s * 0.5, cy - s * 0.32];
  const l1 = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
  const l2 = Math.hypot(p3[0] - p2[0], p3[1] - p2[1]);
  const d = (l1 + l2) * k;
  g.beginPath();
  g.moveTo(p1[0], p1[1]);
  if (d <= l1) g.lineTo(lerp(p1[0], p2[0], d / l1), lerp(p1[1], p2[1], d / l1));
  else {
    g.lineTo(p2[0], p2[1]);
    const q = (d - l1) / l2;
    g.lineTo(lerp(p2[0], p3[0], q), lerp(p2[1], p3[1], q));
  }
  g.stroke();
  g.restore();
}

function spherePts(D, N) {
  if (D.pts && D.pts.length === N) return D.pts;
  D.pts = [];
  const ga = Math.PI * (3 - Math.sqrt(5));
  let seed = 7;
  const rnd = () => {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
  for (let i = 0; i < N; i++) {
    const y = 1 - (i / (N - 1)) * 2;
    const r = Math.sqrt(1 - y * y);
    const th = ga * i;
    D.pts.push({ x: Math.cos(th) * r, y, z: Math.sin(th) * r, r: rnd(), tw: rnd() * 6.28 });
  }
  return D.pts;
}

// «Aylantirish» bosqichining k paytidagi qiymatlari — «Tayyor» shu yerdan davom etadi (sakrashsiz).
function procValues(k) {
  const tIn = ease(k * 3);
  const a = ease(k * 4);
  return {
    q: lerp(1, 0.35, tIn),
    shrink: lerp(1, 0.8, tIn),
    spin: 1.2 * ease(k),
    label: 1 - a,
    dots: a,
  };
}
const REC_VALUES = Object.freeze({ q: 1, shrink: 1, spin: 0, label: 1, dots: 0 });

// Namunadagi sphere("spin", …) — bgMode "none".
function drawSphere(g, cx, cy, R, S, D) {
  const P = spherePts(D, PARTICLES);
  const rec = S.st === "rec";
  const proc = S.st === "proc";
  const done = S.st === "done";
  const f = S.from || procValues(1);
  // Bosqichlar orasida sakrash bo'lmasin (egasi: «3ta etapdan bir biriga o'tishda … kesilib qolgandek»): hamma qiymat silliq o'tadi
  const tIn = proc ? ease(S.k * 3) : 0;
  const q = rec ? 1 : proc ? lerp(1, 0.35, tIn) : f.q * (1 - ease(S.k * 2));
  const spinExtra = proc ? 1.2 * ease(S.k) : done ? f.spin + 0.5 * ease(S.k) : 0;
  // aylanish — sekin; aylantirish paytida bir tekis
  const ry = S.t * 0.26 + spinExtra;
  const rx = 0.45;
  const cyr = Math.cos(ry);
  const syr = Math.sin(ry);
  const cxr = Math.cos(rx);
  const sxr = Math.sin(rx);
  const shrink = proc
    ? lerp(1, 0.8, tIn)
    : done
      ? f.shrink * (1 - ease(S.k * 1.5) * 0.9)
      : 1;
  const fade = done ? 1 - ease(S.k * 1.6) : 1;
  const RR = R * 0.9 * shrink;
  g.globalCompositeOperation = "source-over";
  g.shadowColor = "rgba(0,8,30,.45)";
  g.shadowBlur = 2;
  for (let k = 0; k < P.length; k++) {
    const p = P[k];
    const lat = Math.asin(p.y);
    const lon = Math.atan2(p.z, p.x);
    const disp =
      1 + (0.04 + S.ls * WAVE_VOICE) * q * Math.sin(3 * lat + S.t * 0.8) * Math.cos(2 * lon - S.t * 0.5);
    const x = p.x * disp;
    const y = p.y * disp;
    const z = p.z * disp;
    const x1 = x * cyr + z * syr;
    const z1 = -x * syr + z * cyr;
    const y1 = y * cxr - z1 * sxr;
    const z2 = y * sxr + z1 * cxr;
    const depth = clamp((z2 + 1) / 2, 0, 1);
    const tw = 0.85 + 0.15 * Math.sin(S.t * 1.5 + p.tw);
    const col = mix(hot(mix(BL, CY, depth), S.lf * (0.6 + depth * 0.4)), WH, 0);
    g.fillStyle = rgba(col, (0.22 + depth * 0.62 + S.lf * 0.08) * tw * fade);
    g.beginPath();
    g.arc(cx + x1 * RR, cy + y1 * RR, Math.max(0.3, 0.7 + depth * 1.35), 0, Math.PI * 2);
    g.fill();
  }
  g.globalCompositeOperation = "source-over";
  g.shadowBlur = 0;
  // soniya → nuqtalar → belgi: birining o'rniga ikkinchisi asta chiqadi
  const ty = cy + R * 1.42;
  const col = hot(CY, S.lf);
  const size = Math.max(10, R * 0.32);
  const dotSize = Math.max(1.5, R * 0.07);
  if (rec) label(g, fmt(S.p), cx, ty, size, col);
  if (proc) {
    const a = ease(S.k * 4);
    g.globalAlpha = 1 - a;
    label(g, fmt(S.p), cx, ty, size, col);
    g.globalAlpha = a;
    dots(g, cx, ty, dotSize, S.t);
    g.globalAlpha = 1;
  }
  if (done) {
    const out = 1 - ease(S.k * 5);
    if (f.label * out > 0) {
      g.globalAlpha = f.label * out;
      label(g, fmt(S.p), cx, ty, size, col);
    }
    g.globalAlpha = f.dots * out;
    dots(g, cx, ty, dotSize, S.t);
    g.globalAlpha = 1;
    // egasi: «ohiridagi done oq fonda korinmay qolar ekan» — belgi to'q doira nishon ustida, oq va qora fonda ham ko'rinadi
    const bk = back(S.k * 3.2);
    const br = R * 0.62 * bk;
    if (br > 0.5) {
      g.save();
      g.shadowColor = "rgba(0,0,0,.3)";
      g.shadowBlur = R * 0.3;
      g.shadowOffsetY = R * 0.06;
      g.fillStyle = "rgba(7,10,20,.9)";
      g.beginPath();
      g.arc(cx, cy, br, 0, Math.PI * 2);
      g.fill();
      g.restore();
      g.strokeStyle = rgba(hot(CY, S.lf), 0.8);
      g.lineWidth = 1.5;
      g.beginPath();
      g.arc(cx, cy, br, 0, Math.PI * 2);
      g.stroke();
    }
    check(g, cx, cy, R * 0.42, S.k * 3 - 0.25);
  }
}

// Shar orqasidagi xira doira (egasi, 2026-11-11: «blur effekti qilaylik bu animatsiya orqasiga»; «animatsiya blurning
// o'rtasida … aniq chegarali bo'lishi kerak emas, gradientli bo'lishi kerak»). Asosiy jarayon shar ostidagi joyni
// suratga oladi; bu yerda u xiralashtiriladi va markazi shar markazida, chekkasi asta yo'qoladigan doira bo'ladi.
const BACKDROP_BLUR_PX = 9;
const BACKDROP_TINT = "rgba(12,14,22,.10)";
const BACKDROP_FADE_MS = 200;

function buildBackdrop(img, rect) {
  const size = ORB_SIZE;
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const c = document.createElement("canvas");
  c.width = Math.round(size * dpr);
  c.height = Math.round(size * dpr);
  const g = c.getContext("2d");
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.filter = `blur(${BACKDROP_BLUR_PX}px)`;
  g.drawImage(img, rect.x, rect.y, rect.width, rect.height);
  g.filter = "none";
  g.fillStyle = BACKDROP_TINT;
  g.fillRect(0, 0, size, size);
  // Chekka: markazdan radiusning 45 % igacha to'liq, keyin asta yo'qoladi, oyna chetida butunlay shaffof.
  g.globalCompositeOperation = "destination-in";
  const half = size / 2;
  const mask = g.createRadialGradient(half, half, 0, half, half, half);
  mask.addColorStop(0, "rgba(0,0,0,1)");
  mask.addColorStop(0.45, "rgba(0,0,0,1)");
  mask.addColorStop(0.75, "rgba(0,0,0,.55)");
  mask.addColorStop(1, "rgba(0,0,0,0)");
  g.fillStyle = mask;
  g.fillRect(0, 0, size, size);
  g.globalCompositeOperation = "source-over";
  return c;
}

/**
 * Shar holati. Signallar: "rec" (paydo bo'lish va yozish), "proc" (aylantirish), "done" (tayyor, keyin o'zi yo'qoladi),
 * "hide" (bekor qilish yoki xato — hozirgi holatdan yo'qoladi). Har sikl o'z raqami bilan; yo'qolib bo'lgach
 * onFinished(raqam) chaqiriladi. Yangi "rec" eski sikl hali ko'rinib turganda kelsa, eskisi shu zahoti yo'qola boshlaydi
 * va ikkalasi bir-biriga silliq o'tadi.
 */
export function createGaplaOrb(canvas, { onFinished, testVoice = false } = {}) {
  const g = canvas.getContext("2d");
  let cycles = [];
  let level = QUIET_LEVEL;
  let lastLevelAt = 0;
  let ls = 0;
  let lf = 0;
  let lastNow = null;
  let raf = 0;
  let destroyed = false;

  const current = () => cycles[cycles.length - 1] || null;

  function fit() {
    const w = canvas.clientWidth || ORB_SIZE;
    const h = canvas.clientHeight || ORB_SIZE;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.globalAlpha = 1;
    g.clearRect(0, 0, w, h);
    return { w, h };
  }

  function start() {
    if (!raf && !destroyed) raf = requestAnimationFrame(frame);
  }

  function frame(now) {
    raf = 0;
    if (destroyed) return;
    const dt = lastNow === null ? 1 / 60 : Math.min(0.1, Math.max(0, (now - lastNow) / 1000));
    lastNow = now;
    const live = current();
    if (testVoice && live && live.st === "rec") {
      level = testVoiceLevel((now - live.recStart) / 1000);
      lastLevelAt = now;
    }
    if (live && live.vanishStart === null) {
      const silent = live.st === "rec" && now - Math.max(live.recStart, lastLevelAt) > REC_SILENCE_MS;
      const stuck = live.st === "proc" && now - live.procStart > PROC_MAX_MS;
      if (silent || stuck) live.vanishStart = now;
    }
    const target = live && live.st === "rec" && live.vanishStart === null ? level : QUIET_LEVEL;
    // Kadr tezligi 60 dan farq qilsa: k' = 1 − (1 − k)^(dt·60)
    ls += (target - ls) * (1 - Math.pow(1 - SHAPE_K, dt * 60));
    lf += (target - lf) * (1 - Math.pow(1 - COLOR_K, dt * 60));
    const { w, h } = fit();
    const finished = [];
    for (const c of cycles) {
      if (c.st === "done" && c.vanishStart === null && now - c.doneStart >= ORB_TIMING.doneMs) {
        c.vanishStart = c.doneStart + ORB_TIMING.doneMs;
      }
      if (c.vanishStart !== null && now - c.vanishStart >= ORB_TIMING.goneMs) {
        finished.push(c);
        continue;
      }
      const vanish = c.vanishStart === null ? 1 : 1 - ease((now - c.vanishStart) / ORB_TIMING.goneMs);
      const appear = back((now - c.start) / ORB_TIMING.appearMs);
      const scale = Math.min(appear, 1.06) * vanish;
      const k =
        c.st === "proc"
          ? (now - c.procStart) / ORB_TIMING.procMs
          : c.st === "done"
            ? (now - c.doneStart) / ORB_TIMING.doneMs
            : 0;
      const S = {
        st: c.st,
        k,
        ls,
        lf,
        t: ((now - c.start) / 1000) * SPEED,
        p: c.st === "rec" ? now - c.recStart : c.p,
        from: c.from,
      };
      if (c.backdrop && scale > 0) {
        const fadeIn = ease((now - c.backdropAt) / BACKDROP_FADE_MS);
        g.globalAlpha = clamp(scale, 0, 1) * fadeIn;
        g.drawImage(c.backdrop, 0, 0, w, h);
        g.globalAlpha = 1;
      }
      const R = ORB_RADIUS * scale;
      if (R > 2) {
        try {
          drawSphere(g, w / 2, h / 2, R, S, c.D);
        } catch {
          g.globalCompositeOperation = "source-over";
          g.globalAlpha = 1;
          g.shadowBlur = 0;
        }
      }
    }
    const rec = current();
    if (rec && rec.st === "rec" && rec.vanishStart === null) {
      const s = rec.stats;
      s.frames += 1;
      s.lsSum += ls;
      s.lsMax = Math.max(s.lsMax, ls);
      s.lfMax = Math.max(s.lfMax, lf);
    }
    if (finished.length) {
      finished.forEach(noteStats);
      cycles = cycles.filter((c) => !finished.includes(c));
      // Bo'sh kadr ekranga chiqqach xabar beramiz — oyna keyingi safar eski rasm bilan ochilmasin.
      requestAnimationFrame(() => finished.forEach((c) => onFinished?.(c.id)));
    }
    if (cycles.length) start();
    else lastNow = null;
  }

  function signal(type, id) {
    const now = performance.now();
    const c = current();
    if (type === "rec") {
      if (c && c.vanishStart === null) c.vanishStart = now;
      level = QUIET_LEVEL;
      cycles.push({
        id,
        st: "rec",
        start: now,
        recStart: now,
        procStart: null,
        doneStart: null,
        vanishStart: null,
        p: 0,
        from: null,
        D: {},
        stats: { frames: 0, levels: 0, levelSum: 0, levelMax: 0, lsSum: 0, lsMax: 0, lfMax: 0 },
      });
      start();
      return;
    }
    if (!c || c.vanishStart !== null) return;
    if (type === "proc" && c.st === "rec") {
      c.st = "proc";
      c.procStart = now;
      c.p = now - c.recStart;
    } else if (type === "done" && (c.st === "rec" || c.st === "proc")) {
      c.from = c.st === "proc" ? procValues((now - c.procStart) / ORB_TIMING.procMs) : REC_VALUES;
      if (c.st === "rec") c.p = now - c.recStart;
      c.st = "done";
      c.doneStart = now;
    } else if (type === "hide" && c.st !== "done") {
      c.vanishStart = now;
    }
    start();
  }

  function setLevel(next) {
    if (testVoice) return;
    const n = Number(next);
    if (!Number.isFinite(n)) return;
    level = clamp(n, 0, 1);
    lastLevelAt = performance.now();
    const c = current();
    if (c && c.st === "rec") {
      c.stats.levels += 1;
      c.stats.levelSum += level;
      c.stats.levelMax = Math.max(c.stats.levelMax, level);
    }
  }

  // Tashxis (egasi 2026-11-12: «Hali kuchsiz»): har sikl — yozish soniyasi, kadr/s, kelgan daraja soni/s va qiymati,
  // shakl (ls) va rang (lf). `globalThis.__gaplaOrbStats`, oxirgi 10 ta.
  function noteStats(c) {
    try {
      const s = c.stats;
      const recMs = (c.procStart ?? c.doneStart ?? c.vanishStart ?? performance.now()) - c.recStart;
      const sec = Math.max(0.001, recMs / 1000);
      const r2 = (x) => Math.round(x * 100) / 100;
      const list = (globalThis.__gaplaOrbStats ||= []);
      list.push({
        id: c.id,
        at: new Date().toISOString(),
        yozish_s: r2(sec),
        kadr_s: Math.round(s.frames / sec),
        daraja_soni_s: Math.round(s.levels / sec),
        daraja_ortacha: s.levels ? r2(s.levelSum / s.levels) : null,
        daraja_max: r2(s.levelMax),
        shakl_ortacha: s.frames ? r2(s.lsSum / s.frames) : null,
        shakl_max: r2(s.lsMax),
        rang_max: r2(s.lfMax),
        sinov: testVoice,
      });
      if (list.length > 10) list.splice(0, list.length - 10);
    } catch {
      // tashxis ishni to'xtatmasin
    }
  }

  function setBackdrop(id, payload) {
    const cycle = cycles.find((c) => c.id === id);
    const rect = payload?.rect;
    if (!cycle || !payload?.dataUrl || !rect) return;
    const img = new Image();
    img.onload = () => {
      if (destroyed || !cycles.includes(cycle)) return;
      try {
        cycle.backdrop = buildBackdrop(img, rect);
        cycle.backdropAt = performance.now();
        start();
      } catch {
        cycle.backdrop = null;
      }
    };
    img.src = payload.dataUrl;
  }

  function destroy() {
    destroyed = true;
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    cycles = [];
  }

  return { signal, setLevel, setBackdrop, destroy };
}
