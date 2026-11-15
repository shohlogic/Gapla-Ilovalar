// Gapla tarjimoni (G56, owner 2026-11-12): the page the keyboard's 文A button opens (app/tarjimon.tsx). Same layout
// and behaviour as Android (GaplaTarjimonActivity.kt): language chips, a text field that takes typing, the clipboard
// and Gapla dictation, the «Tarjima» button, and two variants — «Aniq tarjima» and «Silliq va qisqa».
//
// Why a page in the app and not a panel in the keyboard: here the field is an ordinary text field, so the Gapla
// keyboard types into it, paste works, and dictation runs as in the app. A field inside the keyboard would need every
// key routed by hand (the reason Android opens a window too).
//
// G65 (owner 2026-11-14): «hamma jixozlarda men tarjima so'zini bosganimdan keyin tarjima qilishi kerak». Nothing but
// the «Tarjima» button starts a translation: not a pause in typing, not a language change, not a paste or dictation.
// The button is off while the field is empty and shows a spinner while it works.
//
// «Joylash» (opened from another app's keyboard): the picked variant is copied, handed to the keyboard through the App
// Group (gapla_tarjima_joylash, KeyboardViewController.insertPendingTranslation) and the app returns to the field it came
// from, where the keyboard types it in.
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  AppState,
  KeyboardAvoidingView,
  Pressable,
  ScrollView,
  TextInput,
  View,
  type NativeSyntheticEvent,
  type TextInputSelectionChangeEventData,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Application from 'expo-application';
import * as Clipboard from 'expo-clipboard';
import { Text } from '@/components/ui/Text';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { Toast } from '@/components/ui/Toast';
import { APP_BACKGROUND, BRAND } from '@/config/colors';
import { useAudioRecording } from '@/hooks/useAudioRecording';
import {
  TARJIMA_TILLARI,
  TarjimaXato,
  tarjimaQil,
  tarjimaTilNomi,
  type TarjimaNatija,
  type TarjimaTil,
} from '@/lib/gaplaTarjima';
import { isMicPermissionError, isNoSpeechError, showMicPermissionAlert } from '@/lib/permissions';
import { markTarjimonBackgrounded, setTarjimonActive } from '@/lib/tarjimonHolat';
import { AppGroupStorage } from '../../modules/app-group-storage/src';

const TIL_KALIT = 'gapla_tarjimon_til';
// Read by the keyboard (KeyboardHandoffProvider.consumePendingTranslation).
const JOYLASH_KALIT = 'gapla_tarjima_joylash';
const JOYLASH_VAQT_KALIT = 'gapla_tarjima_joylash_ms';

function savedTil(): TarjimaTil {
  try {
    const saved = AppGroupStorage.getItem(TIL_KALIT);
    return TARJIMA_TILLARI.some((item) => item.id === saved) ? (saved as TarjimaTil) : 'auto';
  } catch {
    return 'auto';
  }
}

/**
 * The keyboard was in another app (not Gapla itself), so «Joylash» can go back there. The host's bundle is not always
 * known (iOS may hide it from the keyboard); a link from the keyboard without it still counts as another app.
 */
function isOtherApp(source: string | null, hostBundle: string | null): boolean {
  if (source !== 'keyboard') return false;
  if (!hostBundle) return true;
  const own = Application.applicationId?.toLowerCase();
  const host = hostBundle.trim().toLowerCase();
  return !own || !(host === own || host.startsWith(`${own}.`));
}

function dismiss(): void {
  if (router.canGoBack()) {
    router.back();
  } else {
    router.replace('/(tabs)/(record)');
  }
}

export default function TarjimonScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ source?: string; hostBundle?: string }>();
  const source = typeof params.source === 'string' ? params.source : null;
  const hostBundle = typeof params.hostBundle === 'string' ? params.hostBundle : null;
  const fromOtherApp = isOtherApp(source, hostBundle);

  const [til, setTil] = useState<TarjimaTil>(savedTil);
  const [matn, setMatn] = useState('');
  const [natija, setNatija] = useState<TarjimaNatija | null>(null);
  const [xato, setXato] = useState<string | null>(null);
  const [yuklanmoqda, setYuklanmoqda] = useState(false);
  const [toast, setToast] = useState<{ message: string; id: number } | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const selectionRef = useRef({ start: 0, end: 0 });
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = useCallback((message: string) => {
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    setToast({ message, id: Date.now() });
    toastTimerRef.current = setTimeout(() => setToast(null), 2500);
  }, []);

  // Holds the app on this page across returns from the background (src/lib/tarjimonHolat.ts).
  useEffect(() => {
    setTarjimonActive(true);
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'background') markTarjimonBackgrounded();
    });
    return () => {
      subscription.remove();
      setTarjimonActive(false);
      abortRef.current?.abort();
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    };
  }, []);

  // Emptying the field drops the old translation too. A new one comes only from the button (G65).
  useEffect(() => {
    if (matn.trim()) return;
    abortRef.current?.abort();
    abortRef.current = null;
    setNatija(null);
    setXato(null);
    setYuklanmoqda(false);
  }, [matn]);

  /** Puts text where the cursor is, replacing a selection, as Android does. */
  const insertAtCursor = useCallback((piece: string) => {
    setMatn((previous) => {
      const start = Math.min(selectionRef.current.start, previous.length);
      const end = Math.min(Math.max(selectionRef.current.end, start), previous.length);
      const before = previous.slice(0, start);
      const gap = before && !/\s$/.test(before) && !/^\s/.test(piece) ? ' ' : '';
      const next = before + gap + piece + previous.slice(end);
      const caret = start + gap.length + piece.length;
      selectionRef.current = { start: caret, end: caret };
      return next;
    });
  }, []);

  const recording = useAudioRecording({
    saveToHistory: false,
    onComplete: (text) => {
      const spoken = text.trim();
      if (spoken) insertAtCursor(spoken);
    },
    onError: (error) => {
      if (isMicPermissionError(error)) {
        if (!error.nativePromptShown) showMicPermissionAlert();
        return;
      }
      if (isNoSpeechError(error)) {
        showToast('Gap eshitilmadi');
        return;
      }
      setXato(error.message);
    },
  });

  const toggleRecording = useCallback(() => {
    if (recording.isRecording) {
      void recording.stopRecording();
    } else if (!recording.isProcessing) {
      void recording.startRecording();
    }
  }, [recording]);

  const qoyish = useCallback(async () => {
    const clip = await Clipboard.getStringAsync().catch(() => '');
    if (!clip) {
      showToast("Buferda matn yo'q");
      return;
    }
    insertAtCursor(clip);
  }, [insertAtCursor, showToast]);

  const chooseTil = useCallback((next: TarjimaTil) => {
    setTil(next);
    AppGroupStorage.setItem(TIL_KALIT, next);
  }, []);

  /** Only from the «Tarjima» button (G65): nothing else starts a translation. */
  const tarjima = useCallback(async () => {
    const text = matn.trim();
    if (!text || yuklanmoqda) return;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setYuklanmoqda(true);
    setXato(null);
    try {
      const result = await tarjimaQil(text, til, controller.signal);
      if (!controller.signal.aborted) setNatija(result);
    } catch (error) {
      if (controller.signal.aborted) return;
      setXato(error instanceof TarjimaXato ? error.message : "Tarjima chiqmadi, qayta urinib ko'ring.");
    } finally {
      if (abortRef.current === controller) {
        abortRef.current = null;
        setYuklanmoqda(false);
      }
    }
  }, [matn, til, yuklanmoqda]);

  const nusxa = useCallback(
    async (text: string) => {
      await Clipboard.setStringAsync(text);
      showToast('Nusxa olindi');
    },
    [showToast],
  );

  const joylash = useCallback(
    async (text: string) => {
      await Clipboard.setStringAsync(text);
      AppGroupStorage.setItem(JOYLASH_KALIT, text);
      AppGroupStorage.setItem(JOYLASH_VAQT_KALIT, String(Date.now()));
      const outcome = await AppGroupStorage.returnToPreviousApp();
      if (outcome.status === 'opened') {
        dismiss();
        return;
      }
      showToast("Nusxa olindi. Oldingi ilovaga qayting: matn o'zi qo'yiladi.");
    },
    [showToast],
  );

  const yopish = useCallback(() => {
    if (fromOtherApp) void AppGroupStorage.returnToPreviousApp();
    dismiss();
  }, [fromOtherApp]);

  const canTranslate = matn.trim().length > 0 && !yuklanmoqda;
  const micLabel = recording.isRecording
    ? "To'xtatish"
    : recording.isProcessing
      ? 'Yozilmoqda…'
      : 'Gapirish';

  return (
    <KeyboardAvoidingView behavior="padding" style={{ flex: 1, backgroundColor: APP_BACKGROUND }}>
      <ScrollView
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ paddingTop: Math.max(insets.top, 16), paddingBottom: insets.bottom + 24 }}
      >
        <View className="flex-row items-center px-4 pb-3">
          <SystemIcon name="translate" size={22} color="brand" />
          <Text
            accessibilityRole="header"
            className="ml-2 flex-1 text-[22px] text-label"
            style={{ fontWeight: '600' }}
          >
            Tarjimon
          </Text>
          <Pressable
            onPress={yopish}
            accessibilityRole="button"
            accessibilityLabel="Yopish"
            hitSlop={8}
            className="h-9 w-9 items-center justify-center rounded-full bg-tertiarySystemFill active:opacity-70"
          >
            <SystemIcon name="xmark" size={14} color="secondaryLabel" />
          </Pressable>
        </View>

        <View className="flex-row flex-wrap gap-2 px-4">
          {TARJIMA_TILLARI.map((item) => {
            const selected = til === item.id;
            return (
              <Pressable
                key={item.id}
                onPress={() => chooseTil(item.id)}
                accessibilityRole="button"
                accessibilityState={{ selected }}
                className={`rounded-full px-4 py-2 active:opacity-80 ${
                  selected ? 'bg-primary' : 'border border-border bg-secondarySystemGroupedBackground'
                }`}
              >
                <Text
                  className={`text-[15px] ${selected ? 'text-primary-foreground' : 'text-label'}`}
                  style={{ fontWeight: selected ? '600' : '400' }}
                >
                  {item.nom}
                </Text>
              </Pressable>
            );
          })}
        </View>

        {til === 'auto' ? (
          <Text className="mx-4 mt-2 text-[13px] text-secondaryLabel">
            Til tanlanmagan: o'zbekcha matn ruschaga, boshqa til o'zbekchaga o'giriladi.
          </Text>
        ) : null}

        <TextInput
          value={matn}
          onChangeText={setMatn}
          onSelectionChange={(event: NativeSyntheticEvent<TextInputSelectionChangeEventData>) => {
            selectionRef.current = event.nativeEvent.selection;
          }}
          placeholder="Matnni yozing, qo'ying yoki ayting"
          multiline
          autoFocus
          textAlignVertical="top"
          className="mx-4 mt-3 rounded-2xl border border-border bg-secondarySystemGroupedBackground px-4 py-3 text-[17px] text-label"
          style={{ minHeight: 112, maxHeight: 220 }}
        />

        <View className="mx-4 mt-3 flex-row items-center gap-2">
          <Pressable
            onPress={() => void qoyish()}
            accessibilityRole="button"
            className="h-10 flex-row items-center rounded-full border border-border bg-secondarySystemGroupedBackground px-3.5 active:opacity-70"
          >
            <SystemIcon name="doc.on.clipboard" size={15} color="label" />
            <Text className="ml-1.5 text-[15px] text-label">Qo'yish</Text>
          </Pressable>
          <Pressable
            onPress={toggleRecording}
            disabled={recording.isProcessing && !recording.isRecording}
            accessibilityRole="button"
            className="h-10 flex-row items-center rounded-full border border-border bg-secondarySystemGroupedBackground px-3.5 active:opacity-70"
          >
            {recording.isProcessing && !recording.isRecording ? (
              <ActivityIndicator size="small" />
            ) : (
              <SystemIcon
                name={recording.isRecording ? 'stop.fill' : 'mic.fill'}
                size={15}
                color={recording.isRecording ? 'systemRed' : 'label'}
              />
            )}
            <Text className="ml-1.5 text-[15px] text-label">{micLabel}</Text>
          </Pressable>
          <View className="flex-1" />
          {/* G65: the only way to translate. Off on an empty field, a spinner while it works. */}
          <Pressable
            onPress={() => void tarjima()}
            disabled={!canTranslate}
            accessibilityRole="button"
            accessibilityState={{ disabled: !canTranslate, busy: yuklanmoqda }}
            className="h-10 flex-row items-center rounded-full bg-primary px-4 active:opacity-80"
            style={{ opacity: canTranslate || yuklanmoqda ? 1 : 0.4 }}
          >
            {yuklanmoqda ? (
              <ActivityIndicator size="small" color="#FFFFFF" />
            ) : (
              <SystemIcon name="translate" size={15} color="#FFFFFF" />
            )}
            <Text className="ml-1.5 text-[15px] text-primary-foreground" style={{ fontWeight: '600' }}>
              Tarjima
            </Text>
          </Pressable>
        </View>

        {xato ? <Text className="mx-4 mt-3 text-[15px] text-systemRed">{xato}</Text> : null}

        {natija ? (
          <View className="mt-4">
            {natija.manba && natija.til ? (
              <Text className="mx-4 text-[13px] text-secondaryLabel">
                {tarjimaTilNomi(natija.manba)} → {tarjimaTilNomi(natija.til)}
              </Text>
            ) : null}
            <VariantKarta
              sarlavha="Aniq tarjima"
              matn={natija.aniq}
              joylashBor={fromOtherApp}
              onNusxa={nusxa}
              onJoylash={joylash}
            />
            {natija.silliq.trim() ? (
              <VariantKarta
                sarlavha="Silliq va qisqa"
                matn={natija.silliq}
                joylashBor={fromOtherApp}
                onNusxa={nusxa}
                onJoylash={joylash}
              />
            ) : null}
          </View>
        ) : null}
      </ScrollView>
      <Toast message={toast?.message ?? ''} visible={toast !== null} showId={toast?.id} />
    </KeyboardAvoidingView>
  );
}

function VariantKarta({
  sarlavha,
  matn,
  joylashBor,
  onNusxa,
  onJoylash,
}: {
  sarlavha: string;
  matn: string;
  joylashBor: boolean;
  onNusxa: (text: string) => void | Promise<void>;
  onJoylash: (text: string) => void | Promise<void>;
}) {
  return (
    <Pressable
      onPress={() => void onNusxa(matn)}
      accessibilityRole="button"
      accessibilityHint="Nusxa oladi"
      className="mx-4 mt-2 rounded-2xl border border-border bg-secondarySystemGroupedBackground px-4 pb-2 pt-3 active:opacity-90"
    >
      <Text className="text-[14px]" style={{ fontWeight: '600', color: BRAND }}>
        {sarlavha}
      </Text>
      {/* The server keeps the line breaks (G63); Text shows them as they are. */}
      <Text selectable className="mt-1 text-[17px] leading-6 text-label">
        {matn}
      </Text>
      <View className="mt-1 flex-row justify-end gap-1">
        {joylashBor ? (
          <Pressable
            onPress={() => void onJoylash(matn)}
            accessibilityRole="button"
            hitSlop={6}
            className="flex-row items-center rounded-full px-3 py-2 active:opacity-60"
          >
            <SystemIcon name="arrow.down.doc" size={15} color="brand" />
            <Text className="ml-1 text-[15px]" style={{ fontWeight: '600', color: BRAND }}>
              Joylash
            </Text>
          </Pressable>
        ) : null}
        <Pressable
          onPress={() => void onNusxa(matn)}
          accessibilityRole="button"
          hitSlop={6}
          className="flex-row items-center rounded-full px-3 py-2 active:opacity-60"
        >
          <SystemIcon name="doc.on.doc" size={15} color="brand" />
          <Text className="ml-1 text-[15px]" style={{ fontWeight: '600', color: BRAND }}>
            Nusxa
          </Text>
        </Pressable>
      </View>
    </Pressable>
  );
}
