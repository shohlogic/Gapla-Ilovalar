import { create } from 'zustand';
import { UserConfig } from '../types';
import type { InferenceSelection, MobileInferenceScope } from '../lib/mobileProviders';
import { GAPLA_DEFAULT_MODE, gaplaModelName } from '../lib/gaplaMode';
import { StorageService } from '../services/storage/StorageService';
import {
  localModeUpgradeConfig,
  noteChatSplitConfig,
  notesLocalModeSplitConfig,
} from '../lib/inferenceModes';
import { withoutRetiredModels } from '../lib/retiredModels';
import { useProcessingModeStore } from './useProcessingModeStore';

interface ConfigState {
  config: UserConfig | null;
  isLoading: boolean;
  error: string | null;
  loadConfig: () => Promise<void>;
  updateConfig: (config: Partial<UserConfig>) => Promise<void>;
  resetConfig: () => Promise<void>;
}

// Gapla: speech goes to the Gapla bridge (Gemini with the Uzbek-Russian prompt). The server and
// model come filled in; the owner adds only the bridge key under AI Models → Dictation.
const GAPLA_BRIDGE: InferenceSelection = {
  mode: 'providers',
  providerId: 'custom',
  // Shown in settings; each request sends the mode picked at that moment (src/lib/gaplaMode.ts).
  modelId: gaplaModelName(GAPLA_DEFAULT_MODE),
  endpoint: 'https://gapla.xaliljonov.uz/v1',
};

const defaultConfig: UserConfig = {
  // Gapla has one way to dictate: the bridge above. 'providers' sends dictation to the saved
  // provider selection (getTranscriptionProvider -> 'byok'); there is no on-device or Cloud mode.
  defaultMode: 'providers',
  appleLocalIntelligenceEnabled: true,
  localModeUpgraded: true,
  noteChatSplit: true,
  notesLocalModeSplit: true,
  inference: { dictation: GAPLA_BRIDGE, upload: GAPLA_BRIDGE },
  rememberedInference: {
    dictation: { custom: GAPLA_BRIDGE },
    upload: { custom: GAPLA_BRIDGE },
  },
};

// Gapla: a saved config from before the bridge-only app (Private or Cloud mode, an on-device or
// Cloud selection for dictation or uploads) moves to the bridge. A dictation or upload selection
// that already uses a provider is the user's own and stays. On-device and Cloud selections for the
// other workflows are dropped, so they are simply unset. Returns the same object when nothing
// changes, so a migrated config is not saved again.
function gaplaBridgeConfig(config: UserConfig): UserConfig {
  const inference = { ...config.inference };
  const remembered = { ...config.rememberedInference };
  let changed = config.defaultMode !== 'providers';
  for (const scope of ['dictation', 'upload'] as const) {
    if (inference[scope]?.mode !== 'providers') {
      inference[scope] = GAPLA_BRIDGE;
      remembered[scope] = { ...remembered[scope], custom: GAPLA_BRIDGE };
      changed = true;
    }
  }
  for (const scope of ['cleanup', 'notes', 'noteChat', 'agent'] as MobileInferenceScope[]) {
    const mode = inference[scope]?.mode;
    if (mode === 'local' || mode === 'openwhispr') {
      delete inference[scope];
      changed = true;
    }
  }
  if (!changed) return config;
  return { ...config, defaultMode: 'providers', inference, rememberedInference: remembered };
}

export const useConfigStore = create<ConfigState>((set, get) => ({
  config: null,
  isLoading: false,
  error: null,

  loadConfig: async () => {
    set({ isLoading: true, error: null });
    try {
      const config = await StorageService.getConfig();
      // A config from before Local Mode's Cloud defaults is upgraded before anything reads it, so
      // its uploads and cleanup never reach Cloud; one from before note chat had a selection of its
      // own keeps the one it shared; and one from before note formatting left Local Mode keeps its
      // notes on this iPhone. A selection of a model its provider shut down moves to the
      // replacement. A failed save upgrades it again next launch.
      const localModeConfig =
        !config || config.localModeUpgraded
          ? config
          : { ...config, ...localModeUpgradeConfig(config) };
      const noteChatConfig =
        !localModeConfig || localModeConfig.noteChatSplit
          ? localModeConfig
          : { ...localModeConfig, ...noteChatSplitConfig(localModeConfig) };
      const upgradedConfig = withoutRetiredModels(
        !noteChatConfig
          ? defaultConfig
          : noteChatConfig.notesLocalModeSplit
            ? noteChatConfig
            : { ...noteChatConfig, ...notesLocalModeSplitConfig(noteChatConfig) },
      );
      const resolvedConfig = gaplaBridgeConfig(upgradedConfig);
      if (config && resolvedConfig !== config) {
        await StorageService.saveConfig(resolvedConfig).catch(() => undefined);
      }
      useProcessingModeStore.getState().resetToDefault(resolvedConfig.defaultMode);
      set({ config: resolvedConfig, isLoading: false });
    } catch (error) {
      set({
        error: (error as Error).message,
        isLoading: false,
        config: defaultConfig,
      });
      useProcessingModeStore.getState().resetToDefault(defaultConfig.defaultMode);
    }
  },

  updateConfig: async (updates: Partial<UserConfig>) => {
    const currentConfig = get().config || defaultConfig;
    const newConfig = { ...currentConfig, ...updates };

    set({ isLoading: true, error: null });
    try {
      await StorageService.saveConfig(newConfig);
      const modeStore = useProcessingModeStore.getState();
      if (!modeStore.isUserOverride) {
        modeStore.resetToDefault(newConfig.defaultMode);
      }
      set({ config: newConfig, isLoading: false });
    } catch (error) {
      set({ error: (error as Error).message, isLoading: false });
    }
  },

  resetConfig: async () => {
    set({ isLoading: true, error: null });
    try {
      await StorageService.clearConfig();
      useProcessingModeStore.getState().resetToDefault(defaultConfig.defaultMode);
      set({ config: defaultConfig, isLoading: false });
    } catch (error) {
      set({ error: (error as Error).message, isLoading: false });
    }
  },
}));
