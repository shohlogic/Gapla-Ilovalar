// Gapla: nutqsiz yozuv filtri — ko'prikdagi qoidaning aynan nusxasi
// (loyihalar/loyiha-gapla-server-koprik/koprik.py: ovoz_olchovi, nutqsiz_sabab).
// Lokal rejim ko'prikka bormaydi, shuning uchun bo'sh yozuvdan RubaiSTT gap to'qimasin deb
// shu yerda tekshiriladi. Chegaralar gapla.json → speechFilter.
import GAPLA_DEFAULTS from "../constants/gapla.json";

const SAMPLE_RATE = 16000;
const CHUNK = 480; // 30 ms
const MAX_SECONDS = 120; // uzun yozuvning boshi yetadi

// Har 30 ms bo'lakning o'rtacha quvvati, 0…1 (int16 / 32768 ning kvadrati bilan bir xil).
export function chunkPowers(samples) {
  const n = Math.min(samples.length, SAMPLE_RATE * MAX_SECONDS);
  const powers = [];
  for (let i = 0; i + CHUNK <= n; i += CHUNK) {
    let sum = 0;
    for (let j = i; j < i + CHUNK; j++) sum += samples[j] * samples[j];
    powers.push(sum / CHUNK);
  }
  return powers;
}

function loudSeconds(powers, db) {
  const threshold = 10 ** (db / 10);
  let count = 0;
  for (const p of powers) if (p > threshold) count += 1;
  return (count * CHUNK) / SAMPLE_RATE;
}

// Yozuv tashlanishi kerak bo'lsa — sababi, bo'lmasa null.
export function speechlessReason(durationSeconds, powers, cfg = GAPLA_DEFAULTS.speechFilter) {
  if (durationSeconds < GAPLA_DEFAULTS.minSpeechSeconds || !powers.length) {
    return `short ${durationSeconds.toFixed(2)} s`;
  }
  const sorted = [...powers].sort((a, b) => a - b);
  const floorDb = 10 * Math.log10(sorted[Math.floor(sorted.length / 10)] + 1e-12);
  const relativeDb = Math.max(cfg.floorDb, floorDb + cfg.relativeDb);
  if (
    loudSeconds(powers, cfg.absoluteDb) < cfg.speechSeconds &&
    loudSeconds(powers, relativeDb) < cfg.speechSeconds
  ) {
    return `speechless ${durationSeconds.toFixed(1)} s`;
  }
  return null;
}

async function toArrayBuffer(source) {
  if (!source) return null;
  if (typeof Blob !== "undefined" && source instanceof Blob) return source.arrayBuffer();
  if (source instanceof ArrayBuffer) return source.slice(0);
  if (ArrayBuffer.isView(source)) {
    return source.buffer.slice(source.byteOffset, source.byteOffset + source.byteLength);
  }
  return null;
}

// Yozuvni 16 kHz mono qilib o'qiydi va tekshiradi. O'qib bo'lmasa — null: filtr qo'llanmaydi,
// yozuv odatdagidek ishlanadi (ko'prikdagi kabi).
export async function detectSpeechless(source) {
  let context = null;
  try {
    const buffer = await toArrayBuffer(source);
    if (!buffer || buffer.byteLength === 0) return null;
    context = new AudioContext({ sampleRate: SAMPLE_RATE });
    const audio = await context.decodeAudioData(buffer);
    const length = audio.length;
    const mono = new Float32Array(length);
    for (let c = 0; c < audio.numberOfChannels; c++) {
      const channel = audio.getChannelData(c);
      for (let i = 0; i < length; i++) mono[i] += channel[i] / audio.numberOfChannels;
    }
    return speechlessReason(length / SAMPLE_RATE, chunkPowers(mono));
  } catch {
    return null;
  } finally {
    context?.close?.().catch?.(() => {});
  }
}
