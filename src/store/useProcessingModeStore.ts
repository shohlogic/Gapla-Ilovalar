import { create } from 'zustand';
import { ProcessingMode } from '../types';

interface ProcessingModeState {
  activeMode: ProcessingMode;
  isUserOverride: boolean;
  setActiveMode: (mode: ProcessingMode, userInitiated?: boolean) => void;
  resetToDefault: (mode: ProcessingMode) => void;
}

// Gapla: dictation always goes to the Gapla bridge, which is a 'providers' selection. The on-device
// ('private') and Cloud modes do not exist in this app, so every request to switch to them is
// answered with 'providers'. The parameters are kept so existing callers need no change.
const GAPLA_ACTIVE_MODE: ProcessingMode = 'providers';

export const useProcessingModeStore = create<ProcessingModeState>((set) => ({
  activeMode: GAPLA_ACTIVE_MODE,
  isUserOverride: false,
  setActiveMode: (_mode, userInitiated = false) =>
    set({
      activeMode: GAPLA_ACTIVE_MODE,
      isUserOverride: userInitiated,
    }),
  resetToDefault: (_mode) =>
    set({
      activeMode: GAPLA_ACTIVE_MODE,
      isUserOverride: false,
    }),
}));
