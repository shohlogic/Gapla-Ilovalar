import React, { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, Check, Loader2, Lock, RefreshCw, Trash2 } from "./icons";

// Gapla: umumiy bufer oynasi (G8) — Alt+B bilan ochiladi. Element tanlansa to'liq matn kompyuter buferiga ko'chiriladi.
// Egasi (2026-11-11, Android haqida): «har safar bufer tugmasiga bosganimda yangi yuklayapti» — hamma jihozda bir xil:
// oxirgi ro'yxat darhol chiqadi (asosiy jarayonda saqlangan), serverdan yangisi jimgina olinib, ro'yxat sakramasdan
// almashadi. Yuklash belgisi faqat saqlangan ro'yxat yo'q paytda. Kalit va server so'rovlari asosiy jarayonda.

const SPIN_DELAY_MS = 300;

function agoText(ms) {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  if (seconds < 60) return "hozirgina";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} daqiqa oldin`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} soat oldin`;
  const days = Math.floor(hours / 24);
  return days === 1 ? "kecha" : `${days} kun oldin`;
}

function relativeTime(unixSeconds) {
  return agoText(Date.now() - Number(unixSeconds || 0) * 1000);
}

function preview(text) {
  return String(text || "").replace(/\s+/g, " ").trim() || "(bo'sh qator)";
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

function PinIcon({ filled, className }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true">
      <path
        d="M9 3h6l-1 5 3 3v2h-4v6l-1 2-1-2v-6H7v-2l3-3-1-5Z"
        fill={filled ? "currentColor" : "none"}
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// Ro'yxat umuman yo'q paytdagi to'liq xabar.
const ERROR_TEXT = {
  NO_KEY: "Gapla kaliti topilmadi. Sozlamalarda diktovka kaliti borligini tekshiring.",
  NETWORK: "Server bilan bog'lanib bo'lmadi. Internetni tekshirib, qayta urinib ko'ring.",
  AUTH: "Server kalitni qabul qilmadi. Sozlamalardagi Gapla kalitini tekshiring.",
  GONE: "Bu nusxa serverda topilmadi — muddati o'tgan yoki o'chirilgan bo'lishi mumkin.",
  OTHER: "Nimadir ishlamadi. Qayta urinib ko'ring.",
};

// Sarlavha ostidagi bir qatorli holat — ro'yxat surilmasligi uchun qisqa.
const SHORT_ERROR = {
  NO_KEY: "Gapla kaliti topilmadi",
  NETWORK: "Internet yo'q",
  AUTH: "Server kalitni qabul qilmadi",
  GONE: "Bu nusxa serverda yo'q",
  OTHER: "Server javob bermadi",
};

const DEFAULT_SUBTITLE = "Hamma jihozdagi nusxalar. Tanlasangiz — kompyuter buferiga ko'chadi.";

export default function GaplaBuferOverlay() {
  const api = window.electronAPI;
  const [items, setItems] = useState(null); // null — saqlangan ro'yxat ham yo'q
  const [loadError, setLoadError] = useState(null);
  const [staleCode, setStaleCode] = useState(null);
  const [savedAt, setSavedAt] = useState(0);
  const [spin, setSpin] = useState(false);
  const [activeId, setActiveId] = useState(null); // null — eng yuqoridagi
  const [busyId, setBusyId] = useState(null);
  const [copiedId, setCopiedId] = useState(null);
  const [notice, setNotice] = useState(null);
  const listRef = useRef(null);
  const refreshSeq = useRef(0);
  const itemsRef = useRef(null);
  const removedRef = useRef(new Set());
  itemsRef.current = items;

  const refresh = useCallback(async () => {
    const seq = ++refreshSeq.current;
    const spinTimer = setTimeout(() => {
      if (seq === refreshSeq.current) setSpin(true);
    }, SPIN_DELAY_MS);
    const result = await api?.gaplaBuferList?.();
    clearTimeout(spinTimer);
    if (seq !== refreshSeq.current) return;
    setSpin(false);
    if (result?.ok) {
      const fresh = (Array.isArray(result.data) ? result.data : []).filter(
        (item) => !removedRef.current.has(item.id)
      );
      setItems(fresh);
      setSavedAt(Date.now());
      setLoadError(null);
      setStaleCode(null);
    } else {
      const code = result?.code || "OTHER";
      if (itemsRef.current === null) setLoadError(code);
      else setStaleCode(code);
    }
  }, [api]);

  const resetTransient = useCallback(() => {
    setNotice(null);
    setCopiedId(null);
    setBusyId(null);
    setActiveId(null);
    removedRef.current.clear();
    listRef.current?.scrollTo?.({ top: 0 });
  }, []);

  // Alt+B: saqlangan ro'yxat xabar bilan keladi — darhol ko'rsatiladi, keyin serverdan jimgina yangilanadi.
  const onOpened = useCallback(
    (cached) => {
      resetTransient();
      setStaleCode(null);
      if (cached && typeof cached === "object") {
        if (Array.isArray(cached.items)) {
          setItems(cached.items);
          setSavedAt(Number(cached.savedAt) || 0);
          setLoadError(null);
        } else {
          setItems(null);
        }
      }
      void refresh();
    },
    [refresh, resetTransient]
  );

  useEffect(() => {
    let alive = true;
    // Avval tinglovchi, keyin so'rov: asosiy jarayon shu so'rovdan keyin «ochildi» xabarini yuboradi.
    const off = api?.onGaplaBuferOpened?.(onOpened);
    // Oyna yashirin tayyorlanganda — faqat saqlangan ro'yxat o'qiladi, tarmoqqa so'rov yo'q.
    void api?.gaplaBuferCached?.().then((result) => {
      if (!alive || !result?.ok) return;
      if (result.data?.open) {
        onOpened(result.data);
        return;
      }
      if (itemsRef.current === null && Array.isArray(result.data?.items)) {
        setItems(result.data.items);
        setSavedAt(Number(result.data.savedAt) || 0);
      }
    });
    // Oyna fokusni yo'qotsa yashiriladi — vaqtinchalik belgilar tozalanadi, keyingi ochilishda eski kadr miltillamaydi.
    window.addEventListener("blur", resetTransient);
    return () => {
      alive = false;
      off?.();
      window.removeEventListener("blur", resetTransient);
    };
  }, [api, onOpened, resetTransient]);

  const list = items || [];
  const foundIndex = list.findIndex((item) => item.id === activeId);
  const activeIndex = foundIndex >= 0 ? foundIndex : 0;

  const dropLocally = useCallback((id) => {
    removedRef.current.add(id);
    setItems((prev) => (prev ? prev.filter((item) => item.id !== id) : prev));
  }, []);

  const copyItem = useCallback(
    async (item) => {
      if (!item || busyId) return;
      setBusyId(item.id);
      setNotice(null);
      const result = await api?.gaplaBuferCopy?.(item.id);
      setBusyId(null);
      if (result?.ok) {
        setCopiedId(item.id);
        setTimeout(() => api?.gaplaBuferClose?.(), 450);
      } else if (result?.code === "GONE") {
        dropLocally(item.id);
        setNotice("Bu nusxa serverda yo'q — ro'yxatdan olindi.");
      } else {
        setNotice(`Nusxalanmadi. ${SHORT_ERROR[result?.code] || SHORT_ERROR.OTHER}.`);
      }
    },
    [api, busyId, dropLocally]
  );

  const togglePin = useCallback(
    async (item) => {
      if (!item) return;
      const next = !item.qadalgan;
      const setPinned = (value) =>
        setItems((prev) =>
          prev
            ? sortItems(prev.map((x) => (x.id === item.id ? { ...x, qadalgan: value } : x)))
            : prev
        );
      setActiveId(item.id);
      setNotice(null);
      setPinned(next);
      const result = await api?.gaplaBuferPin?.(item.id, next);
      if (!result?.ok) {
        setPinned(Boolean(item.qadalgan));
        setNotice(`Qadash o'zgarmadi. ${SHORT_ERROR[result?.code] || SHORT_ERROR.OTHER}.`);
      }
    },
    [api]
  );

  const removeItem = useCallback(
    async (item) => {
      if (!item) return;
      const index = list.findIndex((x) => x.id === item.id);
      const neighbour = list[index + 1] || list[index - 1] || null;
      if (activeId === item.id) setActiveId(neighbour ? neighbour.id : null);
      setNotice(null);
      dropLocally(item.id);
      const result = await api?.gaplaBuferDelete?.(item.id);
      if (!result?.ok) {
        removedRef.current.delete(item.id);
        setItems((prev) => sortItems([item, ...(prev || []).filter((x) => x.id !== item.id)]));
        setNotice(`O'chirilmadi. ${SHORT_ERROR[result?.code] || SHORT_ERROR.OTHER}.`);
      }
    },
    [api, activeId, dropLocally, list]
  );

  useEffect(() => {
    const onKey = (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        api?.gaplaBuferClose?.();
        return;
      }
      if (list.length === 0) return;
      if (event.key === "ArrowDown") {
        event.preventDefault();
        setActiveId(list[Math.min(list.length - 1, activeIndex + 1)].id);
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        setActiveId(list[Math.max(0, activeIndex - 1)].id);
      } else if (event.key === "Enter") {
        event.preventDefault();
        void copyItem(list[activeIndex]);
      } else if (event.key === "Delete") {
        event.preventDefault();
        void removeItem(list[activeIndex]);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [api, activeIndex, copyItem, list, removeItem]);

  useEffect(() => {
    if (activeId === null) return;
    listRef.current
      ?.querySelector(`[data-index="${activeIndex}"]`)
      ?.scrollIntoView({ block: "nearest" });
  }, [activeId, activeIndex]);

  const statusText = notice
    ? notice
    : staleCode
      ? `${SHORT_ERROR[staleCode] || SHORT_ERROR.OTHER}. Ro'yxat ${
          savedAt ? `${agoText(Date.now() - savedAt)} yangilangan` : "oldin saqlangan"
        }.`
      : null;

  return (
    <div className="gapla-bufer-window flex h-screen flex-col bg-background text-foreground select-none">
      <header className="flex items-center justify-between gap-3 px-4 pb-2 pt-3">
        <div className="min-w-0">
          <h1 className="text-[15px]! font-semibold! leading-tight! tracking-normal!">Bufer</h1>
          <p
            className={`flex items-center gap-1 truncate text-[11.5px] leading-[1.45] ${
              statusText ? "text-foreground/85" : "text-muted-foreground"
            }`}
            title={statusText || DEFAULT_SUBTITLE}
            aria-live="polite"
          >
            {statusText && <AlertCircle className="size-3 shrink-0 text-muted-foreground" />}
            <span className="truncate">{statusText || DEFAULT_SUBTITLE}</span>
          </p>
        </div>
        <button
          type="button"
          onClick={() => void refresh()}
          className="shrink-0 rounded-md p-1.5 text-muted-foreground hover:bg-surface-2 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
          aria-label="Ro'yxatni yangilash"
          title="Ro'yxatni yangilash"
        >
          <RefreshCw className={`size-4 ${spin ? "animate-spin" : ""}`} />
        </button>
      </header>

      <div ref={listRef} className="min-h-0 flex-1 overflow-y-auto px-2 pb-2" role="listbox">
        {items === null && !loadError && (
          <div className="flex h-full items-center justify-center gap-2 text-[13px] text-muted-foreground">
            <Loader2 className="size-4 animate-spin" /> Yuklanmoqda…
          </div>
        )}

        {items === null && loadError && (
          <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center">
            <AlertCircle className="size-6 text-muted-foreground" />
            <p className="text-[13px]">{ERROR_TEXT[loadError] || ERROR_TEXT.OTHER}</p>
            <button
              type="button"
              onClick={() => {
                setLoadError(null);
                void refresh();
              }}
              className="rounded-md border border-border px-3 py-1.5 text-[12.5px] font-medium hover:bg-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
            >
              Qayta urinish
            </button>
          </div>
        )}

        {items !== null && items.length === 0 && (
          <div className="flex h-full flex-col items-center justify-center gap-1 px-6 text-center">
            <p className="text-[13px] font-medium">Hozircha nusxa yo'q</p>
            <p className="text-[12px] text-muted-foreground">
              Istalgan jihozda matn nusxalasangiz, shu yerda ko'rinadi. Nusxa 3 kun saqlanadi, qadalgani — doim.
            </p>
          </div>
        )}

        {list.map((item, index) => {
          const isActive = index === activeIndex;
          const isBusy = busyId === item.id;
          const isCopied = copiedId === item.id;
          return (
            <div
              key={item.id}
              data-index={index}
              role="option"
              aria-selected={isActive}
              onMouseEnter={() => setActiveId(item.id)}
              onClick={() => void copyItem(item)}
              className={`group relative mb-1 cursor-pointer rounded-lg border px-3 py-2 transition-colors duration-100 ${
                isActive ? "border-border bg-surface-2" : "border-transparent hover:bg-surface-1"
              }`}
            >
              <div className="flex items-start gap-2 pr-14">
                {item.maxfiy && (
                  <Lock className="mt-[3px] size-3.5 shrink-0 text-muted-foreground" aria-label="Maxfiy nusxa" />
                )}
                <p className="line-clamp-2 break-words text-[13px] leading-[1.4]">{preview(item.boshi)}</p>
              </div>
              <div className="mt-1 flex items-center gap-1.5 text-[11.5px] text-muted-foreground">
                {item.qadalgan && <PinIcon filled className="size-3 text-foreground/80" />}
                <span>{item.qurilma || "Noma'lum jihoz"}</span>
                <span aria-hidden="true">·</span>
                <span>{relativeTime(item.vaqt)}</span>
                {item.uzunlik > 200 && (
                  <>
                    <span aria-hidden="true">·</span>
                    <span>{Number(item.uzunlik).toLocaleString("ru-RU")} belgi</span>
                  </>
                )}
                {isCopied && (
                  <span className="ml-auto flex items-center gap-1 font-medium text-foreground">
                    <Check className="size-3.5" /> Nusxalandi
                  </span>
                )}
                {isBusy && !isCopied && <Loader2 className="ml-auto size-3.5 animate-spin" />}
              </div>
              <div
                className={`absolute right-2 top-2 flex gap-0.5 ${
                  isActive ? "opacity-100" : "opacity-0 group-hover:opacity-100"
                }`}
              >
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    void togglePin(item);
                  }}
                  className="rounded-md p-1 text-muted-foreground hover:bg-surface-3 hover:text-foreground"
                  aria-label={item.qadalgan ? "Qadashni olish" : "Qadash"}
                  title={item.qadalgan ? "Qadashni olish" : "Qadash — 3 kundan keyin ham qoladi"}
                >
                  <PinIcon filled={item.qadalgan} className="size-3.5" />
                </button>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    void removeItem(item);
                  }}
                  className="rounded-md p-1 text-muted-foreground hover:bg-surface-3 hover:text-foreground"
                  aria-label="O'chirish"
                  title="O'chirish (Delete)"
                >
                  <Trash2 className="size-3.5" />
                </button>
              </div>
            </div>
          );
        })}
      </div>

      <footer className="border-t border-border/60 px-4 py-2 text-[11px] text-muted-foreground">
        ↑ ↓ — tanlash · Enter — nusxalash · Delete — o'chirish · Esc — yopish
      </footer>
    </div>
  );
}
