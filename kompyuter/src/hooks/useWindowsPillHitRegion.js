import { useLayoutEffect } from "react";

// Gapla (egasi, 2026-11-11: «o'ng chekkasida turadigan kichik logoni atrofida hechnimani bosib bo'lmayapti»):
// Windows'da diktovka oynasi faqat tugma (va uning yonidagi bekor qilish tugmasi) ustida bosishni olsin.
// Renderer tugmaning joyini asosiy jarayonga aytib turadi, kursorni asosiy jarayon kuzatadi
// (windowManager.setMainWindowHitRegion). Menyu, xabar, panel ochiq bo'lsa yoki sudralayotganda — butun oyna.
const SAMPLE_MS = 100;

function unionRect(root) {
  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  const add = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return;
    left = Math.min(left, r.left);
    top = Math.min(top, r.top);
    right = Math.max(right, r.right);
    bottom = Math.max(bottom, r.bottom);
  };
  add(root);
  root.querySelectorAll("*").forEach(add);
  if (!Number.isFinite(left)) return { x: 0, y: 0, width: 0, height: 0 };
  return {
    x: Math.floor(left),
    y: Math.floor(top),
    width: Math.ceil(right - left),
    height: Math.ceil(bottom - top),
  };
}

export function useWindowsPillHitRegion({ pillRef, captureWindow, pillInteractive }) {
  useLayoutEffect(() => {
    const api = window.electronAPI;
    if (api?.getPlatform?.() !== "win32" || !api.setMainWindowHitRegion) return undefined;
    if (captureWindow) {
      api.setMainWindowHitRegion(null);
      return undefined;
    }
    let last = "";
    const sample = () => {
      const el = pillRef.current;
      const region =
        pillInteractive && el ? unionRect(el) : { x: 0, y: 0, width: 0, height: 0 };
      const key = `${region.x},${region.y},${region.width},${region.height}`;
      if (key === last) return;
      last = key;
      api.setMainWindowHitRegion(region);
    };
    sample();
    const timer = setInterval(sample, SAMPLE_MS);
    return () => clearInterval(timer);
  }, [captureWindow, pillInteractive, pillRef]);
}
