import React, { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, Copy, Loader2, Mic, Square, X } from "./icons";
import { getPlatform } from "../utils/platform";
import { formatHotkeyLabel } from "../utils/hotkeys";

// Mac'da tugma Option+T, joylash Cmd+V (G61); Windows'da Alt+T va Ctrl+V.
const IS_MAC = getPlatform() === "darwin";
const OCHISH_TUGMASI = formatHotkeyLabel("Alt+T");
const JOYLASH_TUGMASI = IS_MAC ? "Cmd+V" : "Ctrl+V";

// Gapla tarjimoni (G56, 2026-11-13) — Alt+T oynasi. Namuna: Android 1.4.9 (GaplaTarjimonActivity.kt), yozuvlar va
// tartib bir xil. Egasi: «har safar avtomatik 2 ta variant beradi, birinchisi birga bir tarjima, ikkinchisi esa gramatik
// jixatdan yahshilangan va biroz qisqartirilgan varinat bo'ladi. men xohalaganimni tarjima tanlab osongina kopya qila
// olishim lozim». Server so'rovi, bufer va joylash asosiy jarayonda (gaplaTarjimaWindow.js); kalit oynaga berilmaydi.

const TILLAR = [
  ["uz", "O'zbekcha"],
  ["ru", "Русский"],
  ["en", "English"],
];
const TIL_KALIT = "gaplaTarjimaTil";
const TOXTALISH_MS = 1200; // yozishdagi to'xtalishdan keyin o'zi tarjima qiladi (Android'dagi kabi)
const MAX_BELGI = 20000;
const XABAR_MS = 1600;

const tilNomi = (kod) => TILLAR.find(([k]) => k === kod)?.[1] || kod;

function xatoMatni(status) {
  switch (status) {
    case 0:
      return "Internet yo'q yoki server javob bermadi. Qayta urinib ko'ring.";
    case 400:
      return "So'rov noto'g'ri. Matnni tekshirib, qayta urinib ko'ring.";
    case 401:
    case 403:
      return "Gapla kaliti yo'q yoki noto'g'ri. Uni Gapla sozlamalarida kiriting.";
    case 404:
      return "Tarjima xizmati hali ishga tushmagan.";
    case 413:
      return "Matn juda uzun: 20 000 belgidan oshmasin.";
    case 429:
      return "So'rov juda ko'p. Birozdan keyin qayta urinib ko'ring.";
    default:
      return "Tarjima chiqmadi, qayta urinib ko'ring.";
  }
}

function oqiTil() {
  try {
    const v = localStorage.getItem(TIL_KALIT);
    return TILLAR.some(([k]) => k === v) ? v : "auto";
  } catch {
    return "auto";
  }
}

// Tarjima belgisi 文A (Material «translate», Apache-2.0) — uchala ilovada bir xil, globus emas (egasi qarori).
export function TarjimaIcon({ className }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true" fill="currentColor">
      <path d="M12.87 15.07l-2.54-2.51.03-.03A17.52 17.52 0 0014.07 6H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z" />
    </svg>
  );
}

function PasteIcon({ className }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true" fill="currentColor">
      <path d="M19 2h-4.18C14.4.84 13.3 0 12 0S9.6.84 9.18 2H5c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm7 18H5V4h2v3h10V4h2v16z" />
    </svg>
  );
}

const outlineBtn =
  "inline-flex h-9 items-center gap-1.5 rounded-full border border-border px-3.5 text-[13px] font-medium text-foreground transition-colors hover:bg-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40 disabled:cursor-default disabled:opacity-50";

function VariantKarta({ sarlavha, matn, nusxaOlindi, onNusxa, onJoylash }) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => onNusxa(matn)}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onNusxa(matn);
        }
      }}
      className="cursor-pointer rounded-2xl border border-border/70 bg-surface-2 px-3.5 pb-2 pt-3 transition-colors hover:border-border hover:bg-surface-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
      title="Bosing — nusxa olinadi"
    >
      <p className="text-[12.5px] font-semibold text-primary">{sarlavha}</p>
      <p className="mt-1 whitespace-pre-wrap break-words text-[14.5px] leading-[1.45] select-text">{matn}</p>
      <div className="mt-1.5 flex items-center justify-end gap-1">
        {nusxaOlindi && <span className="mr-auto text-[12px] font-medium text-foreground/80">Nusxa olindi</span>}
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            onJoylash(matn);
          }}
          className="rounded-full px-3 py-1.5 text-[13px] font-medium text-primary hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
          title={`${OCHISH_TUGMASI} dan oldingi oynadagi maydonga joylaydi`}
        >
          Joylash
        </button>
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            onNusxa(matn);
          }}
          className="inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-[13px] font-medium text-primary hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
        >
          <Copy className="size-3.5" /> Nusxa
        </button>
      </div>
    </div>
  );
}

export default function GaplaTarjimonOverlay() {
  const api = typeof window !== "undefined" ? window.electronAPI : null;
  const [matn, setMatn] = useState("");
  const [til, setTil] = useState(oqiTil);
  const [natija, setNatija] = useState(null);
  const [xato, setXato] = useState(null);
  const [yuklanmoqda, setYuklanmoqda] = useState(false);
  const [yozish, setYozish] = useState("idle"); // diktovka holati: idle | preparing | recording | processing
  const [xabar, setXabar] = useState(null);
  const [nusxaTur, setNusxaTur] = useState(null);
  const [zudlik, setZudlik] = useState(0); // qo'yish yoki diktovka — kutmasdan tarjima
  const maydonRef = useRef(null);
  const kutmasdanRef = useRef(false);
  const oxirgiRef = useRef(null); // [matn, til] — xuddi shu so'rov qayta yuborilmaydi
  const sorovRef = useRef(0);
  const xabarTimer = useRef(null);

  const korsat = useCallback((text) => {
    setXabar(text);
    if (xabarTimer.current) clearTimeout(xabarTimer.current);
    xabarTimer.current = setTimeout(() => setXabar(null), XABAR_MS);
  }, []);

  const tarjimaQil = useCallback(
    async (majburiy = false) => {
      const toza = matn.trim();
      if (!toza) {
        setNatija(null);
        setXato(null);
        return;
      }
      if (!majburiy && oxirgiRef.current?.[0] === toza && oxirgiRef.current?.[1] === til && natija) return;
      if (toza.length > MAX_BELGI) {
        setXato(xatoMatni(413));
        return;
      }
      const id = ++sorovRef.current;
      setYuklanmoqda(true);
      setXato(null);
      const javob = await api?.gaplaTarjimaTranslate?.(toza, til);
      if (id !== sorovRef.current) return; // eskirgan javob
      setYuklanmoqda(false);
      if (javob?.ok) {
        setNatija(javob.data);
        setNusxaTur(null);
        oxirgiRef.current = [toza, til];
      } else {
        setXato(xatoMatni(javob?.status ?? 0));
      }
    },
    [api, matn, til, natija]
  );

  // Yozishdagi qisqa to'xtalish, til almashishi, qo'yish yoki diktovka — o'zi tarjima qiladi.
  useEffect(() => {
    if (!matn.trim()) {
      sorovRef.current += 1;
      setNatija(null);
      setXato(null);
      setYuklanmoqda(false);
      return undefined;
    }
    const darhol = kutmasdanRef.current;
    kutmasdanRef.current = false;
    const t = setTimeout(() => void tarjimaQil(), darhol ? 0 : TOXTALISH_MS);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [matn, til, zudlik]);

  const maydongaQosh = useCallback((qism) => {
    const el = maydonRef.current;
    setMatn((oldin) => {
      const bosh = el ? el.selectionStart ?? oldin.length : oldin.length;
      const oxir = el ? el.selectionEnd ?? oldin.length : oldin.length;
      const chap = oldin.slice(0, bosh);
      const ong = oldin.slice(oxir);
      const bitishuv = chap && !/\s$/.test(chap) && !/^\s/.test(qism) ? " " : "";
      const yangi = chap + bitishuv + qism + ong;
      const kursor = (chap + bitishuv + qism).length;
      requestAnimationFrame(() => {
        if (maydonRef.current) {
          maydonRef.current.focus();
          maydonRef.current.setSelectionRange(kursor, kursor);
        }
      });
      return yangi;
    });
    kutmasdanRef.current = true;
    setZudlik((z) => z + 1);
  }, []);

  const qoyish = useCallback(async () => {
    const text = await api?.gaplaTarjimaReadClipboard?.();
    if (!text) {
      korsat("Buferda matn yo'q");
      return;
    }
    maydongaQosh(text);
  }, [api, korsat, maydongaQosh]);

  const gapirish = useCallback(async () => {
    maydonRef.current?.focus();
    const javob = await api?.gaplaTarjimaDictate?.();
    if (javob?.recording) setYozish("preparing");
  }, [api]);

  const nusxa = useCallback(
    async (text, tur) => {
      await api?.gaplaTarjimaCopy?.(text);
      setNusxaTur(tur);
      korsat("Nusxa olindi");
    },
    [api, korsat]
  );

  const joylash = useCallback(
    async (text) => {
      const javob = await api?.gaplaTarjimaPlace?.(text);
      if (javob?.ok && !javob.pasted && javob.reason === "accessibility") {
        korsat(`Joylash uchun Maxsus imkoniyatlar ruxsati kerak — matn buferda, ${JOYLASH_TUGMASI} bosing`);
      } else if (javob?.ok && !javob.pasted) {
        korsat(`Maydonga joylab bo'lmadi — matn buferda, ${JOYLASH_TUGMASI} bosing`);
      }
    },
    [api, korsat]
  );

  const tilTanla = (kod) => {
    setTil(kod);
    try {
      localStorage.setItem(TIL_KALIT, kod);
    } catch {
      // saqlanmasa ham shu ochilishda ishlaydi
    }
  };

  // Har ochilishda toza oyna (Android'dagi kabi), maydonda kursor.
  const ochildi = useCallback(() => {
    sorovRef.current += 1;
    setMatn("");
    setNatija(null);
    setXato(null);
    setYuklanmoqda(false);
    setNusxaTur(null);
    setXabar(null);
    oxirgiRef.current = null;
    setTil(oqiTil());
    setTimeout(() => maydonRef.current?.focus(), 60);
  }, []);

  useEffect(() => {
    const offOpen = api?.onGaplaTarjimaOpened?.(() => ochildi());
    const offDictated = api?.onGaplaTarjimaDictated?.((text) => {
      setYozish("idle");
      if (String(text || "").trim()) maydongaQosh(String(text).trim());
    });
    const offState = api?.onGaplaTarjimaDictationState?.((state) => setYozish(state || "idle"));
    void api?.gaplaTarjimaReady?.().then((r) => {
      if (r?.open) ochildi();
    });
    return () => {
      offOpen?.();
      offDictated?.();
      offState?.();
    };
  }, [api, ochildi, maydongaQosh]);

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        api?.gaplaTarjimaClose?.();
      } else if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        void tarjimaQil(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [api, tarjimaQil]);

  const yozmoqda = yozish === "recording" || yozish === "preparing";
  const ishlanmoqda = yozish === "processing";

  return (
    <div className="flex h-screen flex-col bg-background text-foreground">
      <header className="flex items-center gap-2 px-4 pb-1 pt-3 [-webkit-app-region:drag]">
        <TarjimaIcon className="size-5 shrink-0 text-primary" />
        <h1 className="text-[15px]! font-semibold! leading-tight! tracking-normal!">Tarjimon</h1>
        <span className="text-[11.5px] text-muted-foreground">{OCHISH_TUGMASI}</span>
        <button
          type="button"
          onClick={() => api?.gaplaTarjimaClose?.()}
          className="ml-auto rounded-full p-1.5 text-muted-foreground hover:bg-surface-2 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40 [-webkit-app-region:no-drag]"
          aria-label="Yopish"
          title="Yopish (Esc)"
        >
          <X className="size-4" />
        </button>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-3">
        <div className="flex gap-2 pt-1" role="radiogroup" aria-label="Qaysi tilga">
          {TILLAR.map(([kod, nom]) => (
            <button
              key={kod}
              type="button"
              role="radio"
              aria-checked={til === kod}
              onClick={() => tilTanla(kod)}
              className={`h-8 rounded-full border px-3.5 text-[13px] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40 ${
                til === kod
                  ? "border-transparent bg-primary text-primary-foreground"
                  : "border-border text-foreground hover:bg-surface-2"
              }`}
            >
              {nom}
            </button>
          ))}
        </div>
        {til === "auto" && (
          <p className="mt-2 text-[12px] leading-snug text-muted-foreground">
            Til tanlanmagan: o'zbekcha matn ruschaga, boshqa til o'zbekchaga o'giriladi.
          </p>
        )}

        <textarea
          ref={maydonRef}
          value={matn}
          onChange={(e) => setMatn(e.target.value)}
          placeholder="Matnni yozing, qo'ying yoki ayting"
          // ingliz imlo tekshiruvi o'zbekcha va ruscha so'zlarni qizil chiziq bilan belgilardi
          spellCheck={false}
          rows={4}
          className="mt-3 block max-h-44 min-h-24 w-full resize-none rounded-2xl border border-border bg-surface-1 px-3.5 py-2.5 text-[14.5px] leading-[1.45] text-foreground placeholder:text-muted-foreground focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/20"
        />

        <div className="mt-2.5 flex items-center gap-2">
          <button type="button" onClick={() => void qoyish()} className={outlineBtn}>
            <PasteIcon className="size-4" /> Qo'yish
          </button>
          <button
            type="button"
            onClick={() => void gapirish()}
            disabled={ishlanmoqda}
            className={`${outlineBtn} ${yozmoqda ? "border-primary text-primary" : ""}`}
          >
            {ishlanmoqda ? (
              <Loader2 className="size-4 animate-spin" />
            ) : yozmoqda ? (
              <Square className="size-3.5" />
            ) : (
              <Mic className="size-4" />
            )}
            {ishlanmoqda ? "Yozilmoqda…" : yozmoqda ? "To'xtatish" : "Gapirish"}
          </button>
          <button
            type="button"
            onClick={() => void tarjimaQil(true)}
            disabled={!matn.trim()}
            className="ml-auto h-9 rounded-full bg-primary px-4 text-[13px] font-semibold text-primary-foreground transition-opacity hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40 disabled:opacity-40"
            title="Hozir tarjima qilish (Ctrl+Enter)"
          >
            Tarjima
          </button>
        </div>

        {yuklanmoqda && (
          <div className="mt-3 h-1 overflow-hidden rounded-full bg-surface-3" aria-label="Tarjima qilinmoqda">
            <div className="h-full w-1/3 animate-[gapla-tarjima-yuk_1.1s_ease-in-out_infinite] rounded-full bg-primary" />
          </div>
        )}
        {xato && (
          <p className="mt-3 flex items-start gap-1.5 text-[13px] leading-snug text-destructive" role="alert">
            <AlertCircle className="mt-0.5 size-4 shrink-0" /> {xato}
          </p>
        )}

        {natija && (
          <div className="mt-3 space-y-2.5" aria-live="polite">
            {natija.manba && natija.til && (
              <p className="text-[12px] font-medium text-muted-foreground">
                {tilNomi(natija.manba)} → {tilNomi(natija.til)}
              </p>
            )}
            <VariantKarta
              sarlavha="Aniq tarjima"
              matn={natija.aniq}
              nusxaOlindi={nusxaTur === "aniq"}
              onNusxa={(t) => void nusxa(t, "aniq")}
              onJoylash={(t) => void joylash(t)}
            />
            {natija.silliq && (
              <VariantKarta
                sarlavha="Silliq va qisqa"
                matn={natija.silliq}
                nusxaOlindi={nusxaTur === "silliq"}
                onNusxa={(t) => void nusxa(t, "silliq")}
                onJoylash={(t) => void joylash(t)}
              />
            )}
          </div>
        )}
      </div>

      {xabar && (
        <div className="pointer-events-none absolute inset-x-0 bottom-4 flex justify-center">
          <span className="rounded-full bg-foreground px-4 py-2 text-[13px] font-medium text-background shadow-lg">
            {xabar}
          </span>
        </div>
      )}
      <style>{`@keyframes gapla-tarjima-yuk{0%{transform:translateX(-100%)}100%{transform:translateX(300%)}}`}</style>
    </div>
  );
}
