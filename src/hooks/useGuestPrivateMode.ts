import { useEffect } from 'react';
import { useAuthStore } from '@/store/useAuthStore';
import { useProcessingModeStore } from '@/store/useProcessingModeStore';

/**
 * Gapla: a guest has no Cloud and no on-device model, so a stored or default 'cloud' or 'private'
 * preference moves to the bridge mode ('providers'), where dictation goes to the Gapla server.
 * (The mode store already answers every switch with 'providers'; this is the safety net.)
 *
 * Keyed on `isGuest`, not on the absence of a user: a fresh install has no
 * user until its anonymous onboarding session lands.
 */
export function useGuestPrivateMode(): void {
  const isInitialized = useAuthStore((state) => state.isInitialized);
  const isGuest = useAuthStore((state) => state.isGuest);
  const activeMode = useProcessingModeStore((state) => state.activeMode);

  useEffect(() => {
    if (!isInitialized) return;
    if (isGuest && activeMode !== 'providers') {
      useProcessingModeStore.getState().setActiveMode('providers');
    }
  }, [isInitialized, isGuest, activeMode]);
}
