// Gapla: to'rt rejim — Tez, O'rta, Sekin (Gapla ko'prigi) va Lokal (RubaiSTT kompyuterda).
// Rejim tray menyusidan bir bosishda almashadi: main jarayon «gapla-set-mode» yuboradi,
// shu hook sozlamani o'zgartiradi va joriy rejimni main'ga qaytaradi (menyuda belgi uchun).
import { useEffect } from "react";
import { useSettingsStore } from "../stores/settingsStore";
import GAPLA from "../constants/gapla.json";

interface GaplaMode {
  id: string;
  label: string;
  model?: string;
  local?: boolean;
}

const MODES = GAPLA.modes as GaplaMode[];

interface GaplaElectronApi {
  onGaplaSetMode?: (callback: (modeId: string) => void) => (() => void) | void;
  reportGaplaMode?: (modeId: string) => void;
}

function gaplaApi(): GaplaElectronApi | undefined {
  return (window as unknown as { electronAPI?: GaplaElectronApi }).electronAPI;
}

export function currentGaplaMode(state: {
  useLocalWhisper: boolean;
  cloudTranscriptionProvider: string;
  cloudTranscriptionModel: string;
}): string {
  if (state.useLocalWhisper) return "lokal";
  if (state.cloudTranscriptionProvider !== "custom") return "";
  return MODES.find((mode) => mode.model === state.cloudTranscriptionModel)?.id ?? "";
}

export function applyGaplaMode(modeId: string): void {
  const mode = MODES.find((m) => m.id === modeId);
  if (!mode) return;
  const store = useSettingsStore.getState();
  if (mode.local) {
    store.setCloudTranscriptionForAllScopes({
      useLocalWhisper: true,
      localTranscriptionProvider: "whisper",
      whisperModel: GAPLA.localWhisperModel,
    });
    return;
  }
  store.setCloudTranscriptionForAllScopes({
    useLocalWhisper: false,
    cloudTranscriptionMode: "byok",
    cloudTranscriptionProvider: "custom",
    cloudTranscriptionModel: mode.model ?? GAPLA.cloudModel,
  });
  // Ko'prik kalit bilan «custom» yo'lidan boradi; Settings'da Cloud Providers → Custom ko'rinsin.
  store.setTranscriptionMode("providers");
}

export function useGaplaModes(): void {
  const modeId = useSettingsStore(currentGaplaMode);

  useEffect(() => {
    gaplaApi()?.reportGaplaMode?.(modeId);
  }, [modeId]);

  useEffect(() => {
    const unsubscribe = gaplaApi()?.onGaplaSetMode?.((id) => applyGaplaMode(id));
    return () => {
      if (typeof unsubscribe === "function") unsubscribe();
    };
  }, []);
}
