// Gapla: jihozlararo umumiy bufer (G8) — kompyuter qismi, asosiy jarayonda.
// Egasi (2026-11-11): «hamma jixozlarimdan qilgan kopyalarimni hammasi server orqali … ko'rinadigan qilsak»; «faqat gapla
// nusxalarini emas, har qanday kopyalangan matnni olishi kerak … uzunlik chegarasi qo'yiladi»; «pc da ham bufferni ko'ra
// olish imkonim bo'lishi lozim, buning uchun alt b ishlatmoqchiman»; parollar: «nusxalanaversin. har qanday matn nusxalansin».
// Server kelishuvi: Gapla-Keyboard/bilim/gapla-bufer-reja.md, «Server qismi».
const fs = require("fs");
const { clipboard, net, Notification, safeStorage } = require("electron");
const debugLogger = require("./debugLogger");
const { BuferCache, keyOwner, LIST_LIMIT } = require("./gaplaBuferCache");

const MAX_CHARS = 100_000;
const POLL_MS = 1000;
const RETRY_MS = 30_000;
const QUEUE_LIMIT = 20;
const PERSIST_DELAY_MS = 800;
const REQUEST_TIMEOUT_MS = 10_000;
// O'chirilgan nusxa shu paytda kelayotgan eski ro'yxat javobi bilan qaytib chiqmasin.
const REMOVED_MEMORY_MS = 15_000;
// Kesh faylida nusxalarning to'liq matni turadi (kalit va parol ham bo'lishi mumkin) — Windows hisobi bilan
// shifrlanadi (safeStorage, DPAPI): boshqa foydalanuvchi yoki ko'chirilgan disk uni o'qiy olmaydi.
const CACHE_MAGIC = Buffer.from("GBC1");
const DEVICE = "Kompyuter";
// Parol menejerlari va «maxfiy» nusxa qiluvchi dasturlar qo'yadigan Windows formatlari.
const SECRET_FORMATS = ["ExcludeClipboardContentFromMonitorProcessing"];
const ZERO_DWORD_FORMATS = ["CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"];

function formatCount(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

class GaplaBufer {
  constructor({ baseUrl, getKey, cacheFile, legacyCacheFile }) {
    this.baseUrl = String(baseUrl || "").replace(/\/+$/, "") + "/bufer";
    this.getKey = getKey;
    this.lastText = null;
    this.ownWrite = null;
    this.queue = [];
    this.timer = null;
    this.retryTimer = null;
    this.flushing = false;
    this.cacheFile = cacheFile || null;
    this.legacyCacheFile = legacyCacheFile || null;
    this.cache = new BuferCache();
    this.persistTimer = null;
    this.persistChain = Promise.resolve();
    this.recentlyRemoved = new Map();
    this._loadCache();
  }

  _owner() {
    return keyOwner(this.getKey?.() || "");
  }

  _encode(text) {
    try {
      if (safeStorage?.isEncryptionAvailable?.()) {
        return Buffer.concat([CACHE_MAGIC, safeStorage.encryptString(text)]);
      }
    } catch (error) {
      debugLogger.warn("Gapla bufer cache encrypt failed", { error: error?.message }, "bufer");
    }
    return Buffer.from(text, "utf8");
  }

  _decode(buffer) {
    if (buffer.subarray(0, CACHE_MAGIC.length).equals(CACHE_MAGIC)) {
      return safeStorage.decryptString(buffer.subarray(CACHE_MAGIC.length));
    }
    return buffer.toString("utf8");
  }

  _loadCache() {
    if (!this.cacheFile) return;
    try {
      if (fs.existsSync(this.cacheFile)) {
        this.cache.load(this._decode(fs.readFileSync(this.cacheFile)));
      } else if (this.legacyCacheFile && fs.existsSync(this.legacyCacheFile)) {
        // Birinchi nusxa (2026-11-11) ochiq JSON yozardi — o'qib, shifrlangan faylga o'tkaziladi.
        if (this.cache.load(fs.readFileSync(this.legacyCacheFile, "utf8"))) this._schedulePersist();
      }
    } catch (error) {
      debugLogger.warn("Gapla bufer cache read failed", { error: error?.message }, "bufer");
    }
    if (this.legacyCacheFile) {
      try {
        fs.rmSync(this.legacyCacheFile, { force: true });
      } catch {
        // keyingi ishga tushishda qayta urinadi
      }
    }
  }

  // Yozish: avval .tmp, keyin almashtirish — yarim yozilgan fayl qolmaydi.
  _schedulePersist() {
    if (!this.cacheFile) return;
    clearTimeout(this.persistTimer);
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      const data = this._encode(this.cache.serialize());
      const tmp = `${this.cacheFile}.tmp`;
      this.persistChain = this.persistChain
        .then(() => fs.promises.writeFile(tmp, data))
        .then(() => fs.promises.rename(tmp, this.cacheFile))
        .catch((error) => debugLogger.warn("Gapla bufer cache write failed", { error: error?.message }, "bufer"));
    }, PERSIST_DELAY_MS);
    this.persistTimer.unref?.();
  }

  persistNow() {
    if (!this.cacheFile || !this.persistTimer) return;
    clearTimeout(this.persistTimer);
    this.persistTimer = null;
    try {
      const tmp = `${this.cacheFile}.tmp`;
      fs.writeFileSync(tmp, this._encode(this.cache.serialize()));
      fs.renameSync(tmp, this.cacheFile);
    } catch (error) {
      debugLogger.warn("Gapla bufer cache write failed", { error: error?.message }, "bufer");
    }
  }

  start() {
    if (this.timer) return;
    // Ishga tushgandagi bufer — eski nusxa, yuborilmaydi; faqat bundan keyingi nusxalar.
    this.lastText = this._readText();
    this.timer = setInterval(() => this._poll(), POLL_MS);
    this.timer.unref?.();
  }

  stop() {
    clearInterval(this.timer);
    clearTimeout(this.retryTimer);
    this.timer = null;
    this.retryTimer = null;
  }

  _readText() {
    try {
      return clipboard.readText() || "";
    } catch {
      return null;
    }
  }

  _isSecret() {
    try {
      if (SECRET_FORMATS.some((f) => clipboard.has(f))) return true;
      return ZERO_DWORD_FORMATS.some((f) => {
        if (!clipboard.has(f)) return false;
        const buf = clipboard.readBuffer(f);
        return buf.length >= 4 && buf.readUInt32LE(0) === 0;
      });
    } catch {
      return false;
    }
  }

  _poll() {
    const text = this._readText();
    if (text === null || text === this.lastText) return;
    this.lastText = text;
    if (this.ownWrite !== null && text === this.ownWrite) {
      this.ownWrite = null;
      return;
    }
    if (!text.trim()) return;
    if (text.length > MAX_CHARS) {
      this._notify(
        "Nusxa juda katta, saqlanmadi",
        `${formatCount(text.length)} belgi — umumiy buferga ${formatCount(MAX_CHARS)} belgigacha nusxa yuboriladi.`
      );
      return;
    }
    this.queue.push({ matn: text, qurilma: DEVICE, maxfiy: this._isSecret() });
    if (this.queue.length > QUEUE_LIMIT) this.queue.splice(0, this.queue.length - QUEUE_LIMIT);
    void this._flush();
  }

  _notify(title, body) {
    try {
      if (Notification.isSupported()) new Notification({ title, body, silent: true }).show();
    } catch (error) {
      debugLogger.warn("Gapla bufer notification failed", { error: error?.message }, "bufer");
    }
  }

  async _request(path, { method = "GET", body, timeoutMs = REQUEST_TIMEOUT_MS } = {}) {
    const key = this.getKey?.() || "";
    if (!key) {
      const error = new Error("Gapla kaliti yo'q");
      error.code = "NO_KEY";
      throw error;
    }
    // Internet osilib qolsa oyna «aylanayotgan» belgida uzoq qolmasin.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    let data = null;
    try {
      response = await net.fetch(this.baseUrl + path, {
        method,
        headers: {
          Authorization: `Bearer ${key}`,
          ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });
      try {
        data = await response.json();
      } catch {
        data = null;
      }
    } finally {
      clearTimeout(timer);
    }
    if (!response.ok) {
      const error = new Error(`HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return data;
  }

  // Internet bo'lmasa nusxa navbatda turadi; 30 s da va keyingi nusxada qayta urinadi.
  async _flush() {
    if (this.flushing) return;
    this.flushing = true;
    try {
      while (this.queue.length) {
        const item = this.queue[0];
        try {
          const owner = this._owner();
          const result = await this._request("", { method: "POST", body: item });
          this.queue.shift();
          if (owner) {
            this.cache.rememberOwn(owner, item, result?.id);
            this._schedulePersist();
          }
        } catch (error) {
          if (error.status && error.status < 500 && error.status !== 429) {
            // 400/401/413 — qayta yuborish foyda bermaydi.
            debugLogger.warn("Gapla bufer item rejected", { status: error.status }, "bufer");
            this.queue.shift();
            continue;
          }
          clearTimeout(this.retryTimer);
          this.retryTimer = setTimeout(() => void this._flush(), RETRY_MS);
          this.retryTimer.unref?.();
          break;
        }
      }
    } finally {
      this.flushing = false;
    }
  }

  // Alt+B oynasi uchun — kalit faqat asosiy jarayonda qoladi.
  // Saqlangan ro'yxat: tarmoqsiz, darhol. Serverga so'rov faqat list() da — Alt+B bosilganda.
  cached() {
    return this.cache.snapshot(this._owner());
  }

  async list() {
    void this._flush();
    const owner = this._owner();
    const data = await this._request(`?soni=${LIST_LIMIT}`);
    const now = Date.now();
    for (const [id, at] of this.recentlyRemoved) if (now - at > REMOVED_MEMORY_MS) this.recentlyRemoved.delete(id);
    const items = (Array.isArray(data?.elementlar) ? data.elementlar : []).filter(
      (item) => !this.recentlyRemoved.has(item.id)
    );
    if (owner) {
      this.cache.setList(owner, items);
      this._schedulePersist();
    }
    return items;
  }

  async copy(id) {
    const owner = this._owner();
    let text = owner ? this.cache.getText(owner, id) : undefined;
    if (typeof text !== "string" || !text) {
      const data = await this._request(`/${encodeURIComponent(id)}`);
      text = typeof data?.matn === "string" ? data.matn : "";
      if (!text) throw new Error("Bo'sh matn");
      if (owner) {
        this.cache.setText(owner, id, text);
        this._schedulePersist();
      }
    }
    this.ownWrite = text;
    clipboard.writeText(text);
    return { uzunlik: text.length };
  }

  async pin(id, qadalgan) {
    const owner = this._owner();
    const result = await this._request(`/${encodeURIComponent(id)}/qadash`, {
      method: "POST",
      body: { qadalgan: Boolean(qadalgan) },
    });
    if (owner) {
      this.cache.setPinned(owner, id, qadalgan);
      this._schedulePersist();
    }
    return result;
  }

  // Serverda allaqachon yo'q (404) — o'chirilgan deb hisoblanadi.
  async remove(id) {
    const owner = this._owner();
    try {
      await this._request(`/${encodeURIComponent(id)}`, { method: "DELETE" });
    } catch (error) {
      if (error?.status !== 404) throw error;
    }
    this.recentlyRemoved.set(id, Date.now());
    if (owner) {
      this.cache.remove(owner, id);
      this._schedulePersist();
    }
    return { id };
  }
}

module.exports = { GaplaBufer, MAX_CHARS };
