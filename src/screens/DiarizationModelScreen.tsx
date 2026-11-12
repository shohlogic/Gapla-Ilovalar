import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Text } from '@/components/ui/Text';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { useNotesStore } from '@/store/useNotesStore';
import { confirmDestructive } from '@/lib/alerts';
import { safeHaptics } from '@/lib/utils';
import { Sentry } from '@/lib/sentry';

// The diarizer's native module downloads in one shot with no progress callback and no delete API,
// so this screen models simple lifecycle states rather than mirroring the Whisper progress bar.
type ModelStatus = 'checking' | 'unavailable' | 'idle' | 'downloading' | 'ready' | 'error';

export default function DiarizationModelScreen() {
  const router = useRouter();
  const isDiarizerAvailable = useNotesStore((state) => state.isDiarizerAvailable);
  const isDiarizerModelReady = useNotesStore((state) => state.isDiarizerModelReady);
  const downloadDiarizerModel = useNotesStore((state) => state.downloadDiarizerModel);
  const isDiarizerModelDownloading = useNotesStore((state) => state.isDiarizerModelDownloading);
  const deleteDiarizerModel = useNotesStore((state) => state.deleteDiarizerModel);
  const [status, setStatus] = useState<ModelStatus>('checking');
  const [error, setError] = useState<string | null>(null);

  // Starts the download, or follows one another screen already started.
  const download = useCallback(async () => {
    setError(null);
    setStatus('downloading');
    try {
      await downloadDiarizerModel();
      safeHaptics('success');
      setStatus('ready');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Yuklab olib bo'lmadi");
      setStatus('error');
      Sentry.captureException(caught, { tags: { feature: 'diarization-model-settings' } });
    }
  }, [downloadDiarizerModel]);

  const refresh = useCallback(async () => {
    try {
      if (!(await isDiarizerAvailable())) {
        setStatus('unavailable');
        return;
      }
      if (isDiarizerModelDownloading()) {
        await download();
        return;
      }
      setStatus((await isDiarizerModelReady()) ? 'ready' : 'idle');
    } catch (caught) {
      setStatus('unavailable');
      Sentry.captureException(caught, { tags: { feature: 'diarization-model-settings' } });
    }
  }, [download, isDiarizerAvailable, isDiarizerModelDownloading, isDiarizerModelReady]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const handleDownload = useCallback(async () => {
    safeHaptics('light');
    await download();
  }, [download]);

  const handleDelete = useCallback(() => {
    confirmDestructive(
      "Gapiruvchi modelini o'chirish",
      "Qurilmadagi gapiruvchi modeli o'chirilsinmi? Uchrashuvlarni matnga aylantirish uchun uni qayta yuklab olish kerak bo'ladi.",
      async () => {
        try {
          await deleteDiarizerModel();
          safeHaptics('warning');
          setError(null);
          setStatus('idle');
        } catch (caught) {
          setError(caught instanceof Error ? caught.message : "O'chirib bo'lmadi");
          setStatus('error');
          Sentry.captureException(caught, { tags: { feature: 'diarization-model-settings' } });
        }
      },
    );
  }, [deleteDiarizerModel]);

  if (status === 'checking') {
    return (
      <View className="flex-1 items-center justify-center bg-systemBackground px-6">
        <ActivityIndicator size="large" />
        <Text className="mt-3 text-sm text-secondaryLabel">Model tekshirilmoqda…</Text>
      </View>
    );
  }

  if (status === 'unavailable') {
    return (
      <View className="flex-1 items-center justify-center bg-systemBackground px-6">
        <View
          style={{ borderCurve: 'continuous' }}
          className="w-full rounded-[10px] bg-secondarySystemGroupedBackground p-5"
        >
          <Text className="mb-2 text-center text-base font-semibold text-label">
            Bu qurilmada mavjud emas
          </Text>
          <Text className="text-center text-sm text-secondaryLabel">
            Uchrashuvlarni matnga aylantirish Apple Neural Engine'da ishlaydi va iOS 17 yoki undan
            yangisini talab qiladi (Expo Go'da ishlamaydi).
          </Text>
        </View>
      </View>
    );
  }

  const isReady = status === 'ready';
  const isDownloading = status === 'downloading';

  return (
    <ScrollView
      className="flex-1 bg-systemBackground"
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 16, paddingBottom: 32 }}
    >
      <Text className="mb-4 px-1 text-sm text-secondaryLabel">
        Uchrashuv yozuvlarida kim gapirayotganini belgilash uchun kerak.
      </Text>

      <View
        style={{ borderCurve: 'continuous' }}
        className="rounded-[10px] bg-secondarySystemGroupedBackground p-4"
      >
        <View className="flex-row items-start justify-between">
          <View className="flex-1 pr-3">
            <View className="mb-1.5 flex-row items-center gap-2">
              <Text className="text-[17px] font-semibold text-label">Gapiruvchi modeli</Text>
              {isReady ? (
                <View
                  style={{ borderCurve: 'continuous' }}
                  className="rounded-md bg-systemGreen/15 px-2 py-0.5"
                >
                  <Text className="text-[11px] font-semibold text-systemGreen">
                    Yuklab olingan
                  </Text>
                </View>
              ) : null}
            </View>
            <Text className="text-sm text-secondaryLabel">
              Gapiruvchilarni ajratib, belgilaydi. Hammasi qurilmada ishlaydi.
            </Text>
            <Text className="mt-0.5 text-xs text-tertiaryLabel">
              ~100 MB · bir marta yuklab olinadi
            </Text>

            {isDownloading ? (
              <View className="mt-3 flex-row items-center gap-2">
                <ActivityIndicator size="small" />
                <Text className="text-xs text-secondaryLabel">Yuklab olinmoqda…</Text>
              </View>
            ) : null}

            {status === 'error' && error ? (
              <Text className="mt-2 text-xs text-systemRed">{error}</Text>
            ) : null}
          </View>

          {isReady ? (
            <Pressable
              onPress={handleDelete}
              style={({ pressed }) => ({
                opacity: pressed ? 0.85 : 1,
                transform: [{ scale: pressed ? 0.97 : 1 }],
                borderCurve: 'continuous',
              })}
              className="h-9 w-9 items-center justify-center rounded-lg bg-systemRed/15"
            >
              <SystemIcon name="trash" mdName="Trash2" size={17} color="systemRed" />
            </Pressable>
          ) : isDownloading ? (
            <View className="h-9 w-9 items-center justify-center">
              <ActivityIndicator size="small" />
            </View>
          ) : (
            <Pressable
              onPress={handleDownload}
              style={({ pressed }) => ({
                opacity: pressed ? 0.85 : 1,
                transform: [{ scale: pressed ? 0.97 : 1 }],
                borderCurve: 'continuous',
              })}
              className="h-9 w-9 items-center justify-center rounded-lg bg-brand"
            >
              <SystemIcon name="arrow.down.circle.fill" mdName="Download" size={18} color="#FFF" />
            </Pressable>
          )}
        </View>
      </View>

      <View
        style={{ borderCurve: 'continuous' }}
        className="mt-5 rounded-[10px] bg-secondarySystemGroupedBackground p-4"
      >
        <Text className="mb-1.5 text-sm font-semibold text-label">Qurilmada va maxfiy</Text>
        <Text className="text-xs leading-[18px] text-secondaryLabel">
          Gapiruvchilarni ajratish to'liq qurilmangizda ishlaydi — yozuvlar undan chiqmaydi. Bir
          marta yuklab oling: bu ekrandan chiqsangiz ham model saqlanib qoladi.
        </Text>
        <Pressable
          onPress={() => {
            if (router.canGoBack()) router.back();
            else router.replace('/(account)');
          }}
          style={({ pressed }) => ({
            opacity: pressed ? 0.85 : 1,
            transform: [{ scale: pressed ? 0.98 : 1 }],
            borderCurve: 'continuous',
          })}
          className="mt-3 items-center rounded-lg bg-tertiarySystemFill py-2.5"
        >
          <Text className="text-sm font-medium text-label">Tayyor</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}
