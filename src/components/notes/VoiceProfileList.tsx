import { Pressable, View } from 'react-native';
import { Text } from '@/components/ui/Text';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { GroupedList } from './GroupedList';
import { SectionHeader } from './SectionHeader';
import { SpeakerAvatar } from './SpeakerAvatar';
import { SwipeableCard, type RestoreRow } from '@/components/ui/SwipeableCard';
import type { SpeakerProfile } from '@/data/types';

interface VoiceProfileListProps {
  profiles: SpeakerProfile[];
  onEnrollOwner: () => void;
  onEnrollSpeaker: () => void;
  onOpenProfile: (profile: SpeakerProfile) => void;
  /** `restore` slides a swiped row back; call it if the user cancels the delete. */
  onDelete: (profile: SpeakerProfile, restore: RestoreRow) => void;
  onDeleteAll?: () => void;
}

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

const formatAddedAt = (value: string | null): string => {
  if (!value) return "Shu qurilmada qo'shilgan";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Shu qurilmada qo'shilgan";
  return `${date.getDate()}-${UZ_MONTHS[date.getMonth()]}da qo'shilgan`;
};

const formatMeta = (profile: SpeakerProfile): string => {
  const samples = `${profile.sampleCount} ta namuna`;
  return `${samples} · ${formatAddedAt(profile.createdAt)}`;
};

export function VoiceProfileList({
  profiles,
  onEnrollOwner,
  onEnrollSpeaker,
  onOpenProfile,
  onDelete,
  onDeleteAll,
}: VoiceProfileListProps) {
  if (profiles.length === 0) {
    return (
      <GroupedList>
        <GroupedList.Row contentInsetLeft={16}>
          <View className="items-center gap-3 py-8">
            <SystemIcon
              name="waveform.circle"
              mdName="AudioLines"
              size={36}
              color="quaternaryLabel"
            />
            <View className="items-center gap-1">
              <Text className="text-[17px] font-semibold text-label">
                Gapiruvchilarni avtomatik belgilash
              </Text>
              <Text className="text-center text-[15px] leading-5 text-tertiaryLabel">
                Qisqa ovoz namunasini yozib oling: Gapla keyingi uchrashuv transkriptlarida
                «1-gapiruvchi» o&apos;rniga sizni taniydi. Qurilmada matnga aylantirishda ishlaydi.
                Ovoz namunalari shu qurilmada qoladi va ularni istalgan vaqtda o&apos;chirish mumkin.
              </Text>
            </View>
            <Pressable
              onPress={onEnrollOwner}
              accessibilityRole="button"
              accessibilityLabel="Ovozingizni o'rgatish"
              testID="voice-profile-enroll-owner-empty"
              className="mt-1 h-10 items-center justify-center rounded-[10px] bg-brand px-4"
              style={({ pressed }) => ({ opacity: pressed ? 0.85 : 1, borderCurve: 'continuous' })}
            >
              <Text className="text-[15px] font-semibold text-white">Ovozingizni o&apos;rgatish</Text>
            </Pressable>
          </View>
        </GroupedList.Row>
      </GroupedList>
    );
  }

  const hasOwner = profiles.some((profile) => profile.isOwner === 1);

  return (
    <View>
      <SectionHeader label="Gapiruvchilar" />
      <GroupedList dividerInset={64}>
        {profiles.map((profile) => (
          <SwipeableCard key={profile.id} onDelete={(restore) => onDelete(profile, restore)} inset>
            <GroupedList.Row
              onPress={() => onOpenProfile(profile)}
              accessibilityRole="button"
              accessibilityLabel={`${profile.displayName}, ${formatMeta(profile)}`}
              testID={`voice-profile-row-${profile.id}`}
              contentInsetLeft={64}
              leadingIconSlot={
                <SpeakerAvatar name={profile.displayName} isOwner={profile.isOwner === 1} />
              }
            >
              <View className="flex-row items-center gap-2">
                <View className="min-w-0 flex-1">
                  <View className="flex-row flex-wrap items-center gap-2">
                    <Text className="text-[17px] font-semibold text-label">
                      {profile.displayName}
                    </Text>
                    {profile.isOwner === 1 ? (
                      <View
                        className="rounded-md bg-tertiarySystemFill px-2 py-0.5"
                        testID={`voice-profile-owner-badge-${profile.id}`}
                      >
                        <Text className="text-[12px] font-semibold text-secondaryLabel">Siz</Text>
                      </View>
                    ) : null}
                  </View>
                  <Text className="mt-0.5 text-[13px] text-secondaryLabel" numberOfLines={1}>
                    {formatMeta(profile)}
                  </Text>
                </View>
                <SystemIcon
                  name="chevron.right"
                  mdName="ChevronRight"
                  size={14}
                  color="tertiaryLabel"
                />
              </View>
            </GroupedList.Row>
          </SwipeableCard>
        ))}
      </GroupedList>

      <View className="mt-6">
        <GroupedList dividerInset={16}>
          {hasOwner ? null : (
            <GroupedList.Row
              onPress={onEnrollOwner}
              accessibilityRole="button"
              accessibilityLabel="Ovozingizni o'rgatish"
              testID="voice-profile-enroll-owner"
              contentInsetLeft={16}
            >
              <Text className="text-[17px] font-medium text-brand">Ovozingizni o&apos;rgatish</Text>
            </GroupedList.Row>
          )}
          <GroupedList.Row
            onPress={onEnrollSpeaker}
            accessibilityRole="button"
            accessibilityLabel="Boshqa odam ovozini qo'shish"
            testID="voice-profile-enroll-speaker"
            contentInsetLeft={16}
          >
            <View className="flex-row items-center gap-2">
              <SystemIcon name="plus" mdName="Plus" size={17} color="brand" />
              <Text className="text-[17px] font-medium text-brand">Boshqa odam ovozini qo&apos;shish</Text>
            </View>
          </GroupedList.Row>
        </GroupedList>
      </View>

      <Text className="mt-2 px-4 text-[13px] leading-5 text-secondaryLabel">
        Ovoz profillari faqat shu qurilmada saqlanadi. Ular keyingi uchrashuv transkriptlarida
        gapiruvchilarni belgilashga yordam beradi va ularni istalgan vaqtda o&apos;chirish mumkin.
      </Text>

      {onDeleteAll ? (
        <View className="mt-6">
          <GroupedList dividerInset={16}>
            <GroupedList.Row
              onPress={onDeleteAll}
              accessibilityRole="button"
              accessibilityLabel="Hamma profillarni o'chirish"
              testID="voice-profile-delete-all"
              contentInsetLeft={16}
            >
              <Text className="text-center text-[17px] font-medium text-systemRed">
                Hamma profillarni o&apos;chirish
              </Text>
            </GroupedList.Row>
          </GroupedList>
        </View>
      ) : null}
    </View>
  );
}
