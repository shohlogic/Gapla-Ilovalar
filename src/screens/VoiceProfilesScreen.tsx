import { useCallback, useEffect } from 'react';
import { ScrollView, View } from 'react-native';
import { router } from 'expo-router';
import { VoiceProfileList } from '@/components/notes/VoiceProfileList';
import type { RestoreRow } from '@/components/ui/SwipeableCard';
import { useSuperwallGate } from '@/hooks/useSuperwallGate';
import { useNotesStore } from '@/store/useNotesStore';
import { confirmDestructive } from '@/lib/alerts';
import { SUPERWALL_PLACEMENTS } from '@/lib/superwall';
import { safeHaptics } from '@/lib/utils';
import type { SpeakerProfile } from '@/data/types';

const notesPath = (path: string): string => `/(tabs)/(notes)/${path}`;

export default function VoiceProfilesScreen() {
  const profiles = useNotesStore((state) => state.voiceProfiles);
  const loadVoiceProfiles = useNotesStore((state) => state.loadVoiceProfiles);
  const deleteVoiceProfile = useNotesStore((state) => state.deleteVoiceProfile);
  const deleteAllVoiceProfiles = useNotesStore((state) => state.deleteAllVoiceProfiles);
  const { register: registerSuperwallGate } = useSuperwallGate();

  useEffect(() => {
    loadVoiceProfiles();
  }, [loadVoiceProfiles]);

  const openOwnerEnrollment = useCallback(() => {
    router.push(notesPath('voice-enrollment?owner=1'));
  }, []);

  const openSpeakerEnrollment = useCallback(() => {
    registerSuperwallGate({
      placement: SUPERWALL_PLACEMENTS.voiceProfileAdditionalSpeaker,
      params: { existingProfileCount: profiles.length },
      requiresAccount: false,
      feature: () => {
        router.push(notesPath('voice-enrollment?owner=0'));
      },
    }).catch(() => {});
  }, [profiles.length, registerSuperwallGate]);

  const openProfile = useCallback((profile: SpeakerProfile) => {
    router.push(notesPath(`voice-profile?profileId=${profile.id}`));
  }, []);

  const deleteProfile = useCallback(
    (profile: SpeakerProfile, restore: RestoreRow) => {
      confirmDestructive(
        "Ovoz profilini o'chirish",
        `${profile.displayName} shu qurilmadan o'chiriladi. Avvalgi transkriptlardagi qulflangan gapiruvchi nomlari saqlanib qoladi.`,
        () => {
          deleteVoiceProfile(profile.id);
          safeHaptics('warning');
        },
        { onCancel: restore },
      );
    },
    [deleteVoiceProfile],
  );

  const deleteAll = useCallback(() => {
    confirmDestructive(
      "Hamma ovoz profillarini o'chirish",
      "Hamma ovoz profillari shu qurilmadan o'chiriladi. Avvalgi transkriptlardagi qulflangan nomlar saqlanib qoladi.",
      () => {
        deleteAllVoiceProfiles();
        safeHaptics('warning');
      },
    );
  }, [deleteAllVoiceProfiles]);

  return (
    <View className="flex-1 bg-systemBackground">
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
      >
        <VoiceProfileList
          profiles={profiles}
          onEnrollOwner={openOwnerEnrollment}
          onEnrollSpeaker={openSpeakerEnrollment}
          onOpenProfile={openProfile}
          onDelete={deleteProfile}
          onDeleteAll={profiles.length > 0 ? deleteAll : undefined}
        />
      </ScrollView>
    </View>
  );
}
