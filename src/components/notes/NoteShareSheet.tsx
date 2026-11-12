import { useEffect, useState, type ReactNode } from 'react';
import {
  AccessibilityInfo,
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  View,
  useColorScheme,
} from 'react-native';
import { MenuView, type MenuAction } from '@react-native-menu/menu';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Text } from '@/components/ui/Text';
import { GlassIconButton } from '@/components/ui/GlassIconButton';
import { SystemIcon, type LucideIconName } from '@/components/ui/SystemIcon';
import { INVALID_EMAIL_ERROR, useNoteSharing } from '@/hooks/useNoteSharing';
import { useSuperwallGate } from '@/hooks/useSuperwallGate';
import { SUPERWALL_PLACEMENTS } from '@/lib/superwall';
import { confirmDestructive } from '@/lib/alerts';
import { isValidEmail } from '@/lib/utils';
import { useConfigStore } from '@/store/useConfigStore';
import { useNotesStore } from '@/store/useNotesStore';
import { useUsageStore } from '@/store/useUsageStore';
import { requestSync } from '@/sync/syncEngine';
import { useSyncStore } from '@/sync/useSyncStore';
import { emailDomain, isPersonalEmailDomain } from '@/lib/notes/noteShareDomains';
import { isShareVisibilityAllowed } from '@/lib/notes/noteSharePolicy';
import { isScopeGrant } from '@/lib/notes/noteShareAccess';
import type { ShareVisibility } from '@/data/remote/noteSharingTypes';
import { GroupedList } from './GroupedList';
import { NoteShareAccessList } from './NoteShareAccessList';
import { NoteShareInviteField } from './NoteShareInviteField';
import { ShareActionRow, ShareActionStrip } from './NoteShareActions';
import { RowIcon } from './NoteSharePrincipal';
import { ShareTextButton } from './ShareTextButton';

export interface NoteShareSheetProps {
  noteId: number;
  onClose: () => void;
  onFlushDraft: () => void;
  onExport: (format: 'md' | 'txt') => void;
}

const VISIBILITY_REACH: Record<ShareVisibility, number> = {
  private: 0,
  invited: 1,
  domain: 2,
  link: 3,
};

const VISIBILITY_LABEL: Record<ShareVisibility, string> = {
  private: 'Faqat siz',
  link: 'Havolasi borlarning hammasi',
  domain: 'Tashkilotingiz',
  invited: 'Taklif qilinganlar',
};

const VISIBILITY_ICON: Record<ShareVisibility, [sfName: string, mdName: LucideIconName]> = {
  private: ['lock', 'Lock'],
  link: ['globe', 'Globe'],
  domain: ['building.2', 'Building2'],
  invited: ['person.2', 'Users'],
};

const VISIBILITY_CHOICES = ['link', 'domain', 'invited'] as const;
const VISIBILITY_ACTION_PREFIX = 'visibility:';
const REPLACE_LINK_ID = 'replace-link';
const DISABLE_SHARING_ID = 'disable-sharing';

function describeAccess(
  visibility: ShareVisibility | undefined,
  domains: string[],
  isTeamNote: boolean,
): string {
  switch (visibility) {
    case 'link':
      return "Havolasi bor har kim ko'ra oladi";
    case 'domain':
      return `${domains.join(', ')} dagi havolasi bor har kim ko'ra oladi`;
    case 'invited':
      return "Faqat siz qo'shgan odamlar ocha oladi";
    default:
      return isTeamNote ? "Bu bo'limdan tashqariga ulashilmagan" : 'Hech kimga ulashilmagan';
  }
}

/** Announces each new message to VoiceOver. */
function useAnnouncement(text: string | null): void {
  useEffect(() => {
    if (text) AccessibilityInfo.announceForAccessibility(text);
  }, [text]);
}

/** Explanatory text as the first row of a card. */
function MessageRow({
  children,
  tone = 'secondary',
}: {
  children: ReactNode;
  tone?: 'secondary' | 'error';
}) {
  return (
    <GroupedList.Row>
      <Text
        accessibilityRole={tone === 'error' ? 'alert' : undefined}
        className={
          tone === 'error' ? 'text-[15px] text-systemRed' : 'text-[15px] text-secondaryLabel'
        }
      >
        {children}
      </Text>
    </GroupedList.Row>
  );
}

function LoadingRow({ label }: { label: string }) {
  return (
    <GroupedList.Row>
      <View className="flex-row items-center gap-2">
        <ActivityIndicator size="small" />
        <Text className="text-[15px] text-secondaryLabel">{label}</Text>
      </View>
    </GroupedList.Row>
  );
}

function SectionLabel({ children }: { children: string }) {
  return (
    <Text className="px-1 text-[13px] uppercase tracking-wider text-secondaryLabel">
      {children}
    </Text>
  );
}

/** Supporting text under a card, like a grouped list's section footer. */
function SectionFooter({ children }: { children: ReactNode }) {
  return <Text className="px-4 text-[12px] text-secondaryLabel">{children}</Text>;
}

export function NoteShareSheet({ noteId, onClose, onFlushDraft, onExport }: NoteShareSheetProps) {
  const sharing = useNoteSharing(noteId, onFlushDraft);
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const scheme = useColorScheme();
  const cloudBackupEnabled = useConfigStore((state) => state.config?.cloudBackupEnabled ?? true);
  const setNotePrivacy = useNotesStore((state) => state.setNotePrivacy);
  const spaces = useNotesStore((state) => state.spaces);
  const usage = useUsageStore((state) => state.usage);
  const subscriptionRequired = useSyncStore((state) => state.subscriptionRequired);
  const { register: registerSuperwallGate } = useSuperwallGate();
  const [email, setEmail] = useState('');
  const [privacyError, setPrivacyError] = useState<string | null>(null);
  const businessDomain = emailDomain(sharing.user?.email ?? '');
  const domainEligible = Boolean(businessDomain && !isPersonalEmailDomain(businessDomain));
  const note = sharing.note;
  const signedOut = !sharing.user || sharing.user.isAnonymous;
  const privateNote = note?.isPrivate === 1;
  const isTeamNote = spaces.some((space) => space.id === note?.spaceId && space.kind === 'team');
  // With backup off, an uploaded note's existing sharing stays manageable, but nothing that
  // needs a fresh upload (new links, invitations, visibility changes) can succeed.
  const backupOff = !cloudBackupEnabled && !isTeamNote;
  const localOnly = privateNote || (backupOff && !note?.remoteId);
  // A running operation loads the settings itself, including right after the note's first upload.
  const unknown = Boolean(
    note?.remoteId &&
      !sharing.state &&
      !sharing.loading &&
      !sharing.busy &&
      !localOnly &&
      !signedOut,
  );
  const canManage = sharing.state?.access.can_manage_access !== false;
  const visibility = sharing.state?.share.visibility;
  const shared = Boolean(visibility && visibility !== 'private');
  const canDisablePrevious = Boolean(privateNote && note?.remoteId && shared && canManage);
  // Adding someone to a paused share turns it back on, which restores everyone it paused.
  const pausedAccess =
    visibility === 'private' &&
    Boolean(sharing.state?.access.grants.some((grant) => !isScopeGrant(grant)));
  // Uploading a personal note is what needs Pro; a note already in the cloud stays manageable.
  const upgradeRequired =
    (usage ? !usage.isSubscribed : subscriptionRequired) && !isTeamNote && !note?.remoteId;
  // New edits to a note already in the cloud still need Pro to sync before they can be shared.
  const editsNeedPro =
    (usage ? !usage.isSubscribed : subscriptionRequired) && !isTeamNote && Boolean(note?.remoteId);
  const managed = !signedOut && !localOnly && !upgradeRequired && !sharing.loading && !unknown;
  const allowed = (target: ShareVisibility): boolean =>
    isShareVisibilityAllowed(sharing.sharingMode, target);
  const offered = (target: ShareVisibility): boolean => visibility === target || allowed(target);
  const linkManaged = Boolean(visibility && shared && canManage && allowed(visibility));
  const canAddPeople = canManage && !backupOff && allowed('invited');
  const scrollContentStyle = { paddingHorizontal: 24, paddingBottom: insets.bottom + 24, gap: 18 };
  // Hex literal: the native menu can't serialize PlatformColor.
  const menuIconColor = scheme === 'dark' ? 'rgba(255, 255, 255, 0.95)' : 'rgba(0, 0, 0, 0.85)';
  // Waiting for the upload can be abandoned; a sharing change in flight must finish to keep its link.
  const closable = !sharing.busy || sharing.cancellable;
  const close = (): void => {
    if (closable) onClose();
  };
  useAnnouncement(sharing.error);
  useAnnouncement(privacyError);
  useAnnouncement(sharing.message);
  const openPrivacySettings = (): void => {
    onClose();
    router.push('/(account)/privacy');
  };

  const changeVisibility = (target: ShareVisibility): void => {
    if (sharing.busy || !canManage || target === visibility) return;
    if (target === 'private') {
      confirmDestructive(
        "Tashqi ulashish o'chirilsinmi?",
        "Havolalar ishlamay qoladi, siz qo'shgan va taklif qilgan odamlar kira olmay qoladi. Qayta ulashsangiz, yangi havola yaratiladi va qo'shgan odamlaringiz qaytadi. Xatdagi havolalar ishlashi uchun takliflarni qayta yuboring. Jamoa bo'limi yoki ish maydoni orqali kirishga bu ta'sir qilmaydi.",
        () => sharing.setVisibility('private'),
        { destructiveLabel: "Tashqi ulashishni o'chirish" },
      );
      return;
    }
    const apply = (): void => {
      if (target === 'domain') sharing.setVisibility(target, [businessDomain]);
      else sharing.setVisibility(target);
    };
    if (
      !visibility ||
      visibility === 'private' ||
      VISIBILITY_REACH[target] <= VISIBILITY_REACH[visibility]
    ) {
      apply();
      return;
    }
    // The existing token survives the switch, so links already sent reach the wider audience.
    Alert.alert(
      target === 'link' ? 'Qayd hammaga ochilsinmi?' : `${businessDomain} bilan ulashilsinmi?`,
      target === 'link'
        ? "Havolasi bor har kim bu qaydni ko'ra oladi, havolani avval yuborganlaringiz ham."
        : `${businessDomain} pochtasi bilan kirgan har kim havola orqali bu qaydni ko'ra oladi.`,
      [
        { text: 'Bekor qilish', style: 'cancel' },
        { text: target === 'link' ? 'Hammaga ochish' : 'Ulashish', onPress: apply },
      ],
    );
  };

  const enableCloudSync = (): void => {
    Alert.alert(
      'Bulutli sinxronlash yoqilsinmi?',
      "Bu qayd hisobingizga yuklanadi. Ulashish uchun baribir alohida amal kerak bo'ladi.",
      [
        { text: 'Bekor qilish', style: 'cancel' },
        {
          text: 'Sinxronlashni yoqish',
          onPress: async () => {
            setPrivacyError(null);
            try {
              await setNotePrivacy(noteId, false);
            } catch {
              setPrivacyError("Sinxronlashni yoqib bo'lmadi. Qayta urinib ko'ring.");
            }
          },
        },
      ],
    );
  };

  const replaceLink = (): void => {
    confirmDestructive(
      'Havola almashtirilsinmi?',
      "Avvalgi havola ishlamay qoladi, taklif xatlarida yuborilgan havolalar ham. Yangi havolani kirishi kerak bo'lgan odamlarga ulashing.",
      () => sharing.replaceLink(),
      { destructiveLabel: 'Havolani almashtirish' },
    );
  };

  const resumeSharing = (add: () => void): void => {
    if (!pausedAccess) {
      add();
      return;
    }
    Alert.alert(
      'Ulashish qayta yoqilsinmi?',
      "Kimnidir qo'shsangiz, tashqi ulashish qayta yoqiladi. Avval qo'shgan yoki taklif qilgan odamlaringiz yana kira oladi.",
      [
        { text: 'Bekor qilish', style: 'cancel' },
        { text: 'Ulashishni yoqish', onPress: add },
      ],
    );
  };

  const invite = (): void => {
    const address = email.trim();
    if (!address || sharing.busy) return;
    const send = async (): Promise<void> => {
      if (await sharing.inviteEmail(email)) setEmail('');
    };
    // An invalid address is reported straight away rather than after the confirmation.
    if (isValidEmail(address)) resumeSharing(send);
    else send();
  };

  const upgrade = (): void => {
    registerSuperwallGate({
      placement: SUPERWALL_PLACEMENTS.cloudSyncRequired,
      params: { source: 'note_share_sheet', isSubscribed: usage?.isSubscribed ?? false },
      feature: () => {
        useUsageStore
          .getState()
          .load(true)
          .catch(() => {})
          .finally(() => requestSync('manual'));
      },
    }).catch(() => {});
  };

  const accessMenu: MenuAction[] = [];
  if (canManage && !backupOff) {
    const choices = VISIBILITY_CHOICES.filter((target) =>
      target === 'domain' ? domainEligible && offered('domain') : offered(target),
    );
    if (choices.length > 0) {
      accessMenu.push({
        id: 'visibility',
        title: '',
        displayInline: true,
        subactions: choices.map((target) => ({
          id: `${VISIBILITY_ACTION_PREFIX}${target}`,
          title: target === 'invited' ? 'Faqat taklif qilinganlar' : VISIBILITY_LABEL[target],
          subtitle: target === 'domain' ? businessDomain : undefined,
          image: VISIBILITY_ICON[target][0],
          imageColor: menuIconColor,
          state: visibility === target ? 'on' : 'off',
          attributes: { disabled: sharing.busy },
        })),
      });
    }
  }
  const linkActions: MenuAction[] = [];
  if (linkManaged && !backupOff) {
    linkActions.push({
      id: REPLACE_LINK_ID,
      title: 'Havolani almashtirish',
      image: 'arrow.triangle.2.circlepath',
      imageColor: menuIconColor,
      attributes: { disabled: sharing.busy },
    });
  }
  if (shared && canManage) {
    linkActions.push({
      id: DISABLE_SHARING_ID,
      title: "Tashqi ulashishni o'chirish",
      image: 'lock',
      imageColor: '#FF3B30',
      attributes: { destructive: true, disabled: sharing.busy },
    });
  }
  if (linkActions.length > 0) {
    accessMenu.push({ id: 'link', title: '', displayInline: true, subactions: linkActions });
  }

  const pressAccessMenu = (id: string): void => {
    if (id === REPLACE_LINK_ID) replaceLink();
    else if (id === DISABLE_SHARING_ID) changeVisibility('private');
    else if (id.startsWith(VISIBILITY_ACTION_PREFIX))
      changeVisibility(id.slice(VISIBILITY_ACTION_PREFIX.length) as ShareVisibility);
  };

  const accessTitle =
    shared || !isTeamNote
      ? VISIBILITY_LABEL[visibility ?? 'private']
      : "Jamoa bo'limidagi hamma";
  const accessDetail = pausedAccess
    ? "Tashqi ulashish o'chiq"
    : describeAccess(visibility, sharing.state?.share.domain_allowlist ?? [], isTeamNote);
  const [accessIcon, accessMdIcon] = VISIBILITY_ICON[shared && visibility ? visibility : 'private'];
  const accessRowContent = (
    <View className="flex-row items-center gap-3 px-4 py-3">
      <RowIcon name={accessIcon} mdName={accessMdIcon} tone="brand" />
      <View className="min-w-0 flex-1">
        <Text className="text-[15px] font-medium text-label">{accessTitle}</Text>
        <Text className="text-[12px] text-secondaryLabel">{accessDetail}</Text>
      </View>
      {accessMenu.length > 0 && (
        <SystemIcon
          name="chevron.up.chevron.down"
          mdName="ChevronsUpDown"
          size={13}
          color={sharing.busy ? 'quaternaryLabel' : 'tertiaryLabel'}
        />
      )}
    </View>
  );
  const accessRow =
    accessMenu.length > 0 ? (
      <MenuView
        actions={accessMenu}
        onPressAction={({ nativeEvent }) => pressAccessMenu(nativeEvent.event)}
        shouldOpenOnLongPress={false}
      >
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Umumiy kirish"
          accessibilityValue={{ text: `${accessTitle}. ${accessDetail}` }}
          accessibilityHint="Bu qaydni kim ocha olishini o'zgartiradi"
          className="active:bg-tertiarySystemFill"
        >
          {accessRowContent}
        </Pressable>
      </MenuView>
    ) : (
      <View accessible accessibilityLabel={`Umumiy kirish: ${accessTitle}. ${accessDetail}`}>
        {accessRowContent}
      </View>
    );

  let accessStrip: ReactNode = null;
  if (linkManaged && sharing.hasLink) {
    accessStrip = (
      <ShareActionStrip
        disabled={sharing.busy}
        actions={[
          {
            label: 'Havolani nusxalash',
            icon: 'doc.on.doc',
            mdIcon: 'Copy',
            onPress: () => sharing.copyLink(),
          },
          {
            label: 'Ulashish',
            accessibilityLabel: 'Havolani ulashish',
            icon: 'square.and.arrow.up',
            mdIcon: 'Share',
            onPress: () => sharing.shareLink(),
          },
          {
            label: 'Ochish',
            accessibilityLabel: 'Brauzerda ochish',
            icon: 'safari',
            mdIcon: 'Compass',
            onPress: () => sharing.openLink(),
          },
        ]}
      />
    );
  } else if (linkManaged) {
    accessStrip = (
      <Text className="px-4 py-3 text-[13px] text-secondaryLabel">
        {backupOff
          ? "To'liq havola bu qurilmada saqlanmagan."
          : "To'liq havola bu qurilmada saqlanmagan. Yangisini olish uchun havolani almashtiring."}
      </Text>
    );
  } else if (!shared && canManage && !backupOff && allowed('link')) {
    accessStrip = (
      <ShareActionStrip
        disabled={sharing.busy}
        actions={[
          {
            label: 'Havola yaratish',
            icon: 'link',
            mdIcon: 'Link',
            onPress: () => changeVisibility('link'),
          },
        ]}
      />
    );
  }

  // In the sharing view, feedback sits next to the controls that trigger it rather than below the list.
  const feedback: ReactNode = (
    <>
      {sharing.error && !unknown && !(privateNote && note?.remoteId) && (
        <View className="gap-1 px-1">
          <Text accessibilityRole="alert" className="text-[13px] text-systemRed">
            {sharing.error}
          </Text>
          <View className="flex-row flex-wrap gap-x-6">
            {managed && editsNeedPro && (
              <ShareTextButton label="Pro'ga o'tish" onPress={upgrade} />
            )}
            {managed && note?.remoteId && (
              <ShareTextButton
                label="Yangilash"
                accessibilityLabel="Ulashish sozlamalarini yangilash"
                disabled={sharing.busy}
                onPress={() => sharing.refresh()}
              />
            )}
          </View>
        </View>
      )}
      {privacyError && (
        <Text accessibilityRole="alert" className="px-1 text-[13px] text-systemRed">
          {privacyError}
        </Text>
      )}
      {sharing.message && (
        <Text accessibilityRole="alert" className="px-1 text-[13px] text-secondaryLabel">
          {sharing.message}
        </Text>
      )}
    </>
  );

  const inviteField = canAddPeople ? (
    <NoteShareInviteField
      value={email}
      onChangeText={(value) => {
        setEmail(value);
        if (sharing.error === INVALID_EMAIL_ERROR) sharing.dismissError();
      }}
      onInvite={invite}
      remoteId={note?.remoteId ?? undefined}
      access={sharing.state?.access}
      invitations={sharing.state?.invitations}
      busy={sharing.busy}
      onAddPrincipal={(principal) => {
        setEmail('');
        resumeSharing(() => sharing.addPrincipal(principal));
      }}
    />
  ) : null;

  return (
    <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={close}>
      <View className="flex-1 bg-systemBackground">
        <View className="flex-row items-center justify-between px-6 pb-4 pt-8">
          <Text accessibilityRole="header" className="text-[22px] font-bold text-label">
            Qaydni ulashish
          </Text>
          {closable && (
            <GlassIconButton onPress={close} accessibilityLabel="Ulashish oynasini yopish">
              <SystemIcon name="xmark" mdName="X" size={15} color="secondaryLabel" />
            </GlassIconButton>
          )}
        </View>
        <ScrollView
          keyboardShouldPersistTaps="handled"
          automaticallyAdjustKeyboardInsets
          contentContainerStyle={scrollContentStyle}
        >
          {sharing.busy && (
            <View className="flex-row items-center gap-2 px-1" accessibilityRole="alert">
              <ActivityIndicator size="small" />
              <Text className="text-[13px] text-secondaryLabel">Ulashish yangilanmoqda…</Text>
            </View>
          )}
          {signedOut ? null : localOnly ? (
            <GroupedList dividerInset={16}>
              <MessageRow>
                {backupOff
                  ? "Bulutga zaxira nusxa o'chiq. Shaxsiy qaydlarni ulashish uchun uni Maxfiylik va ma'lumotlar bo'limida yoqing."
                  : 'Ulashishdan oldin bu qayd uchun sinxronlashni yoqing.'}
              </MessageRow>
              {note?.remoteId && !sharing.loading && (
                <MessageRow>
                  {shared
                    ? "Avvalgi havola hali ishlayotgan bo'lishi mumkin."
                    : "Bulutdagi avvalgi nusxa hali o'chirilmagan bo'lishi mumkin."}
                </MessageRow>
              )}
              {sharing.loading && note?.remoteId && (
                <LoadingRow label="Avvalgi ulashish tekshirilmoqda…" />
              )}
              {sharing.error && note?.remoteId && (
                <MessageRow tone="error">{sharing.error}</MessageRow>
              )}
              {sharing.error && note?.remoteId && (
                <ShareActionRow label="Qayta urinish" onPress={() => sharing.refresh()} />
              )}
              {canDisablePrevious && (
                <ShareActionRow
                  label="Avvalgi havolani o'chirish"
                  destructive
                  disabled={sharing.busy || sharing.loading}
                  onPress={() => changeVisibility('private')}
                />
              )}
              {backupOff ? (
                <ShareActionRow
                  label="Maxfiylik sozlamalarini ochish"
                  disabled={sharing.busy}
                  onPress={openPrivacySettings}
                />
              ) : (
                <ShareActionRow
                  label="Sinxronlashni yoqish"
                  accessibilityLabel="Bu qayd uchun sinxronlashni yoqish"
                  disabled={sharing.busy}
                  onPress={enableCloudSync}
                />
              )}
            </GroupedList>
          ) : upgradeRequired ? (
            <GroupedList dividerInset={16}>
              <MessageRow>
                Ulashganda qayd bulutdagi hisobingizga yuklanadi. Buning uchun Pro kerak.
              </MessageRow>
              <ShareActionRow label="Pro'ga o'tish" onPress={upgrade} />
            </GroupedList>
          ) : sharing.loading ? (
            <View className="flex-row items-center gap-3 px-1 py-3">
              <ActivityIndicator />
              <Text className="text-secondaryLabel">Ulashish sozlamalari yuklanmoqda…</Text>
            </View>
          ) : unknown ? (
            <GroupedList dividerInset={16}>
              <MessageRow>{sharing.error || "Ulashish sozlamalarini yuklab bo'lmadi."}</MessageRow>
              <ShareActionRow label="Qayta urinish" onPress={() => sharing.refresh()} />
            </GroupedList>
          ) : (
            <>
              {backupOff && (
                <GroupedList dividerInset={16}>
                  <MessageRow>
                    Bulutga zaxira nusxa o'chiq. Qayd kimga ulashilganini o'zgartirish uchun uni
                    Maxfiylik va ma'lumotlar bo'limida yoqing.
                  </MessageRow>
                  <ShareActionRow
                    label="Maxfiylik sozlamalarini ochish"
                    disabled={sharing.busy}
                    onPress={openPrivacySettings}
                  />
                </GroupedList>
              )}
              <View className="gap-2">
                <SectionLabel>Umumiy kirish</SectionLabel>
                <GroupedList dividerInset={0}>
                  {accessRow}
                  {accessStrip}
                </GroupedList>
                {canManage && !backupOff && sharing.sharingMode === 'domain_only' && (
                  <SectionFooter>
                    Tashkilotingiz faqat kompaniya domeni ichida ulashishga ruxsat beradi.
                  </SectionFooter>
                )}
                {canManage && !backupOff && sharing.sharingMode === 'disabled' && (
                  <SectionFooter>
                    Tashkilotingiz qaydlarni tashqariga ulashishga ruxsat bermaydi.
                  </SectionFooter>
                )}
              </View>
              {feedback}
              {sharing.state ? (
                <NoteShareAccessList
                  key={`${sharing.user?.id}:${note?.remoteId}`}
                  access={sharing.state.access}
                  invitations={sharing.state.invitations}
                  paused={visibility === 'private'}
                  canInvite={allowed('invited')}
                  busy={sharing.busy}
                  inviteField={inviteField}
                  onUpdateGrant={(grant, permission) => sharing.updateGrant(grant, permission)}
                  onRemoveGrant={(grant) => sharing.removeGrant(grant)}
                  onRevokeInvitation={(invitation) => sharing.revokeInvitation(invitation)}
                  onResendInvitation={(invitation) => sharing.resendInvitation(invitation)}
                />
              ) : (
                inviteField && (
                  <View className="gap-2">
                    <SectionLabel>Odamlarni taklif qilish</SectionLabel>
                    <GroupedList>{inviteField}</GroupedList>
                  </View>
                )
              )}
            </>
          )}
          {!managed && feedback}
          <View className="gap-2">
            <SectionLabel>Eksport</SectionLabel>
            <GroupedList>
              <GroupedList.Row
                onPress={() => onExport('md')}
                accessibilityRole="button"
                accessibilityLabel="Markdown sifatida eksport qilish"
                leadingIconSlot={<RowIcon name="doc.richtext" mdName="FileCode" />}
              >
                <Text className="text-[15px] text-label">Markdown</Text>
              </GroupedList.Row>
              <GroupedList.Row
                onPress={() => onExport('txt')}
                accessibilityRole="button"
                accessibilityLabel="Oddiy matn sifatida eksport qilish"
                leadingIconSlot={<RowIcon name="doc.plaintext" mdName="FileText" />}
              >
                <Text className="text-[15px] text-label">Oddiy matn</Text>
              </GroupedList.Row>
            </GroupedList>
          </View>
        </ScrollView>
      </View>
    </Modal>
  );
}
