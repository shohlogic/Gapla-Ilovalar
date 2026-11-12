import { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Text } from '@/components/ui/Text';
import { GroupedList } from '@/components/notes/GroupedList';
import { SectionHeader } from '@/components/notes/SectionHeader';
import { SpeakerAvatar } from '@/components/notes/SpeakerAvatar';
import { useNotesStore } from '@/store/useNotesStore';
import { confirmDestructive } from '@/lib/alerts';
import { safeHaptics } from '@/lib/utils';
import { iosColor } from '@/config/colors';
import { AppFont } from '@/lib/fonts';

// Hermes may have no `uz` Intl data, so the month names are written by hand.
const UZ_MONTHS = [
  'yanvar',
  'fevral',
  'mart',
  'aprel',
  'may',
  'iyun',
  'iyul',
  'avgust',
  'sentabr',
  'oktabr',
  'noyabr',
  'dekabr',
];

const formatDate = (value: string | null): string => {
  if (!value) return 'Shu qurilmada';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Shu qurilmada';
  return `${date.getFullYear()}-yil ${date.getDate()}-${UZ_MONTHS[date.getMonth()]}`;
};

function FieldRow({
  label,
  value,
  placeholder,
  keyboardType,
  autoCapitalize,
  onChangeText,
  onBlur,
  testID,
}: {
  label: string;
  value: string;
  placeholder?: string;
  keyboardType?: 'default' | 'email-address';
  autoCapitalize?: 'none' | 'words';
  onChangeText: (next: string) => void;
  onBlur: () => void;
  testID?: string;
}) {
  return (
    <View className="min-h-[50px] flex-row items-center px-4">
      <Text className="w-[84px] text-[16px] text-secondaryLabel">{label}</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        onBlur={onBlur}
        onSubmitEditing={onBlur}
        placeholder={placeholder}
        placeholderTextColor={iosColor('tertiaryLabel')}
        keyboardType={keyboardType}
        autoCapitalize={autoCapitalize}
        autoCorrect={false}
        returnKeyType="done"
        testID={testID}
        className="flex-1 py-3 text-[17px] text-label"
        style={{ fontFamily: AppFont.regular }}
      />
    </View>
  );
}

export default function VoiceProfileDetailScreen() {
  const params = useLocalSearchParams<{ profileId?: string }>();
  const router = useRouter();
  const profileId = params.profileId ? Number(params.profileId) : null;

  const profiles = useNotesStore((state) => state.voiceProfiles);
  const loadVoiceProfiles = useNotesStore((state) => state.loadVoiceProfiles);
  const updateVoiceProfile = useNotesStore((state) => state.updateVoiceProfile);
  const deleteVoiceProfile = useNotesStore((state) => state.deleteVoiceProfile);

  const profile = profiles.find((item) => item.id === profileId) ?? null;

  const [name, setName] = useState(profile?.displayName ?? '');
  const [email, setEmail] = useState(profile?.email ?? '');
  const syncedId = useRef<number | null>(null);
  const sawProfile = useRef(false);

  useEffect(() => {
    loadVoiceProfiles();
  }, [loadVoiceProfiles]);

  useEffect(() => {
    if (profile && syncedId.current !== profile.id) {
      syncedId.current = profile.id;
      setName(profile.displayName);
      setEmail(profile.email ?? '');
    }
  }, [profile]);

  // Leave once the profile is gone — deleted here, or a stale id once profiles load.
  useEffect(() => {
    if (profile) {
      sawProfile.current = true;
      return;
    }
    if (sawProfile.current || profiles.length > 0) {
      router.back();
    }
  }, [profile, profiles.length, router]);

  const commitName = useCallback(() => {
    if (!profile) return;
    const trimmed = name.trim();
    if (!trimmed) {
      setName(profile.displayName);
      return;
    }
    if (trimmed !== profile.displayName) {
      updateVoiceProfile(profile.id, { displayName: trimmed });
    }
  }, [name, profile, updateVoiceProfile]);

  const commitEmail = useCallback(() => {
    if (!profile) return;
    const trimmed = email.trim();
    const next = trimmed.length > 0 ? trimmed : null;
    if (next !== (profile.email ?? null)) {
      updateVoiceProfile(profile.id, { email: next });
    }
  }, [email, profile, updateVoiceProfile]);

  const retrain = useCallback(() => {
    if (!profile) return;
    router.push(`/(tabs)/(notes)/voice-enrollment?profileId=${profile.id}`);
  }, [profile, router]);

  const remove = useCallback(() => {
    if (!profile) return;
    confirmDestructive(
      "Ovoz profilini o'chirish",
      `${profile.displayName} shu qurilmadan o'chiriladi. Avvalgi transkriptlardagi qulflangan gapiruvchi nomlari saqlanib qoladi.`,
      () => {
        deleteVoiceProfile(profile.id);
        safeHaptics('warning');
      },
    );
  }, [profile, deleteVoiceProfile]);

  if (!profile) {
    return <View className="flex-1 bg-systemBackground" />;
  }

  const isOwner = profile.isOwner === 1;

  return (
    <View className="flex-1 bg-systemBackground">
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
      >
        <View className="items-center gap-2.5 pb-1 pt-2">
          <SpeakerAvatar name={profile.displayName} isOwner={isOwner} size={76} />
          <View className="flex-row items-center gap-2">
            <Text accessibilityRole="header" className="text-[22px] font-bold text-label">
              {profile.displayName}
            </Text>
            {isOwner ? (
              <View className="rounded-md bg-tertiarySystemFill px-2 py-0.5">
                <Text className="text-[12px] font-semibold text-secondaryLabel">Siz</Text>
              </View>
            ) : null}
          </View>
        </View>

        <SectionHeader label="Ism" />
        <GroupedList dividerInset={16}>
          <FieldRow
            label="Ism"
            value={name}
            autoCapitalize="words"
            onChangeText={setName}
            onBlur={commitName}
            testID="voice-profile-name-input"
          />
          <FieldRow
            label="Email"
            value={email}
            placeholder="Ixtiyoriy"
            keyboardType="email-address"
            autoCapitalize="none"
            onChangeText={setEmail}
            onBlur={commitEmail}
            testID="voice-profile-email-input"
          />
        </GroupedList>
        <Text className="mt-2 px-4 text-[13px] leading-5 text-secondaryLabel">
          Email qo&apos;shsangiz, keyinchalik uchrashuv qaydlari bu gapiruvchini kalendar taklifnomalari
          bilan bog&apos;lay oladi.
        </Text>

        <SectionHeader label="Ovoz namunasi" />
        <GroupedList dividerInset={16}>
          <View className="min-h-[46px] flex-row items-center justify-between px-4 py-3">
            <Text className="text-[16px] text-secondaryLabel">Namunalar</Text>
            <Text className="text-[16px] font-medium text-label">{profile.sampleCount}</Text>
          </View>
          <View className="min-h-[46px] flex-row items-center justify-between px-4 py-3">
            <Text className="text-[16px] text-secondaryLabel">Qo&apos;shilgan</Text>
            <Text className="text-[16px] font-medium text-label">
              {formatDate(profile.createdAt)}
            </Text>
          </View>
          <GroupedList.Row
            onPress={retrain}
            accessibilityRole="button"
            accessibilityLabel="Ovozni qayta o'rgatish"
            testID="voice-profile-reenroll"
            contentInsetLeft={16}
          >
            <Text className="text-[17px] font-medium text-brand">Ovozni qayta o&apos;rgatish</Text>
          </GroupedList.Row>
        </GroupedList>
        <Text className="mt-2 px-4 text-[13px] leading-5 text-secondaryLabel">
          Qayta o&apos;rgatish bu ovoz namunasini almashtiradi. Avvalgi transkriptlardagi belgilar
          o&apos;zgarmaydi.
        </Text>

        <View className="mt-6">
          <GroupedList dividerInset={16}>
            <GroupedList.Row
              onPress={remove}
              accessibilityRole="button"
              accessibilityLabel="Profilni o'chirish"
              testID="voice-profile-delete"
              contentInsetLeft={16}
            >
              <Text className="text-center text-[17px] font-medium text-systemRed">
                Profilni o&apos;chirish
              </Text>
            </GroupedList.Row>
          </GroupedList>
        </View>
      </ScrollView>
    </View>
  );
}
