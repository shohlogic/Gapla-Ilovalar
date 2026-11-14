// Gapla: umumiy bufer (G8) — Alt+B oynasi uchun saqlangan ro'yxat va to'liq matnlar (electronsiz, sinaladigan qism).
// Egasi (2026-11-11, Android haqida): «har safar bufer tugmasiga bosganimda yangi yuklayapti» — hamma jihozda bir xil:
// oyna oxirgi ro'yxatni darhol ko'rsatadi, serverdan yangisi jimgina olinadi; to'liq matn bir marta olingach saqlanadi.
const crypto = require("crypto");

const CACHE_VERSION = 1;
const LIST_LIMIT = 50;
const PREVIEW_CHARS = 200;
const SECRET_PREVIEW = "●●●●●●●●";

// Kesh qaysi kalitga tegishli — kalitning o'zi emas, qisqa izi saqlanadi; kalit almashsa eski ro'yxat ko'rsatilmaydi.
function keyOwner(key) {
  if (!key) return null;
  return crypto.createHash("sha256").update(String(key)).digest("hex").slice(0, 16);
}

// Server tartibi: qadalganlar oldin, keyin oxirgi nusxalangan vaqt bo'yicha.
function sortItems(items) {
  return items
    .slice()
    .sort(
      (a, b) =>
        Number(Boolean(b.qadalgan)) - Number(Boolean(a.qadalgan)) ||
        Number(b.vaqt || 0) - Number(a.vaqt || 0)
    );
}

class BuferCache {
  constructor() {
    this.owner = null;
    this.items = null; // null — bu kalit bilan ro'yxat hali hech qachon olinmagan
    this.texts = new Map(); // id → to'liq matn
    this.savedAt = 0;
  }

  _ensureOwner(owner) {
    if (this.owner === owner) return;
    this.owner = owner;
    this.items = null;
    this.texts.clear();
    this.savedAt = 0;
  }

  snapshot(owner) {
    if (!owner || owner !== this.owner) return { items: null, savedAt: 0 };
    return { items: this.items, savedAt: this.savedAt };
  }

  setList(owner, items, now = Date.now()) {
    this._ensureOwner(owner);
    this.items = sortItems(items).slice(0, LIST_LIMIT);
    this.savedAt = now;
    const ids = new Set(this.items.map((item) => item.id));
    for (const id of this.texts.keys()) if (!ids.has(id)) this.texts.delete(id);
  }

  getText(owner, id) {
    if (owner !== this.owner) return undefined;
    return this.texts.get(id);
  }

  setText(owner, id, text) {
    this._ensureOwner(owner);
    this.texts.set(id, text);
  }

  // Kompyuterning o'z nusxasi serverga tushgach — ro'yxatda darhol ko'rinadi, to'liq matni allaqachon bor.
  rememberOwn(owner, { matn, qurilma, maxfiy }, id, now = Date.now()) {
    if (id === undefined || id === null) return;
    this._ensureOwner(owner);
    this.texts.set(id, matn);
    if (this.items === null) return;
    const existing = this.items.find((item) => item.id === id);
    const entry = {
      ...(existing || {}),
      id,
      boshi: maxfiy ? SECRET_PREVIEW : matn.slice(0, PREVIEW_CHARS),
      uzunlik: matn.length,
      qurilma,
      vaqt: Math.floor(now / 1000),
      qadalgan: Boolean(existing?.qadalgan),
      maxfiy: Boolean(maxfiy),
    };
    this.items = sortItems([entry, ...this.items.filter((item) => item.id !== id)]).slice(0, LIST_LIMIT);
  }

  setPinned(owner, id, qadalgan) {
    if (owner !== this.owner || !this.items) return;
    this.items = sortItems(
      this.items.map((item) => (item.id === id ? { ...item, qadalgan: Boolean(qadalgan) } : item))
    );
  }

  remove(owner, id) {
    if (owner !== this.owner) return;
    this.texts.delete(id);
    if (this.items) this.items = this.items.filter((item) => item.id !== id);
  }

  // Diskka: maxfiy nusxaning to'liq matni yozilmaydi (u faqat xotirada turadi).
  serialize() {
    const secret = new Set((this.items || []).filter((item) => item.maxfiy).map((item) => item.id));
    const texts = [...this.texts].filter(([id]) => !secret.has(id));
    return JSON.stringify({ v: CACHE_VERSION, owner: this.owner, savedAt: this.savedAt, items: this.items, texts });
  }

  load(json) {
    try {
      const data = JSON.parse(json);
      if (data?.v !== CACHE_VERSION || typeof data.owner !== "string") return false;
      this.owner = data.owner;
      this.items = Array.isArray(data.items) ? data.items : null;
      this.savedAt = Number(data.savedAt) || 0;
      this.texts = new Map(
        Array.isArray(data.texts) ? data.texts.filter((pair) => Array.isArray(pair) && typeof pair[1] === "string") : []
      );
      return true;
    } catch {
      return false;
    }
  }
}

module.exports = { BuferCache, keyOwner, sortItems, LIST_LIMIT, PREVIEW_CHARS, SECRET_PREVIEW };
