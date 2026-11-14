import React, { useEffect, useRef } from "react";
import { createGaplaOrb, ORB_SIZE } from "./gaplaOrb";

// Gapla: ekran o'rtasidagi shaffof oyna (176×176) — yozish paytidagi zarra shar (G47).
// Holat va ovoz darajasi diktovka oynasidan asosiy jarayon orqali keladi; sichqoncha oyna orqali o'tib ketadi.
export default function DictationOrbOverlay() {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const orb = createGaplaOrb(canvas, {
      onFinished: (id) => window.electronAPI?.dictationOrbFinished?.(id),
      // `Gapla.exe --orb-sinov`: mikrofon o'rniga tanlov sahifasining sinov ovozi — sahifa bilan yonma-yon solishtirish uchun.
      testVoice: new URLSearchParams(window.location.search).get("orb-sinov") === "1",
    });
    const offSignal = window.electronAPI?.onDictationOrbSignal?.((payload) => {
      orb.signal(payload?.type, payload?.id);
    });
    const offLevel = window.electronAPI?.onDictationOrbLevel?.((level) => orb.setLevel(level));
    const offBackdrop = window.electronAPI?.onDictationOrbBackdrop?.((payload) =>
      orb.setBackdrop(payload?.id, payload)
    );
    // Tinglovchilar ulangach asosiy jarayonga aytiladi — undan oldingi signallar navbatda kutadi.
    window.electronAPI?.dictationOrbReady?.();
    return () => {
      offSignal?.();
      offLevel?.();
      offBackdrop?.();
      orb.destroy();
    };
  }, []);

  return (
    <div
      className="dictation-window gapla-orb-window"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        pointerEvents: "none",
        userSelect: "none",
      }}
      aria-hidden="true"
    >
      <canvas ref={canvasRef} style={{ width: ORB_SIZE, height: ORB_SIZE, display: "block" }} />
    </div>
  );
}
