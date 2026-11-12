import { Stack, router } from 'expo-router';
import { Pressable } from 'react-native';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { safeHaptics } from '@/lib/utils';
import { customHeaderStackOptions, glassStackOptions } from '@/config/navigation';
import { WORKFLOW_LABELS, parseWorkflow } from '@/lib/aiWorkflows';

// iOS 26 wraps custom header buttons in their own liquid-glass capsule, so this
// back button is a bare chevron — the native bar supplies the glass. Adding our
// own GlassBackButton here would nest a glass capsule inside the native one.
// (Custom-header screens like AccountScreen/NoteEditor use GlassBackButton
// because they render no native header to provide the glass.)
function HeaderBackButton() {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Orqaga"
      hitSlop={12}
      onPress={() => {
        safeHaptics('selection');
        router.back();
      }}
      style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1 })}
    >
      <SystemIcon name="chevron.left" mdName="ChevronLeft" size={22} color="brand" />
    </Pressable>
  );
}

function renderHeaderLeft({ canGoBack }: { canGoBack?: boolean }) {
  return canGoBack ? <HeaderBackButton /> : null;
}

export default function AccountLayout() {
  return (
    <Stack
      screenOptions={{
        ...glassStackOptions,
        headerBackVisible: false,
        headerLeft: renderHeaderLeft,
      }}
    >
      <Stack.Screen name="index" options={customHeaderStackOptions} />
      <Stack.Screen name="profile" options={{ title: 'Profil', headerLargeTitle: false }} />
      <Stack.Screen name="referral" options={{ title: 'Taklif', headerLargeTitle: false }} />
      <Stack.Screen name="ai-models" options={{ title: 'AI modellari', headerLargeTitle: false }} />
      <Stack.Screen
        name="ai-workflow"
        options={({ route }) => {
          const scope = parseWorkflow((route.params as { scope?: string })?.scope);
          return { title: scope ? WORKFLOW_LABELS[scope] : '', headerLargeTitle: false };
        }}
      />
      <Stack.Screen
        name="dictation-agent"
        options={{ title: 'Ovozli yordamchi', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="keyboard-tone"
        options={{ title: 'Klaviatura ohangi', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="hardware-keyboard"
        options={{ title: 'Tashqi klaviatura', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="cleanup-prompt"
        options={{ title: "Tozalash ko'rsatmasi", headerLargeTitle: false }}
      />
      <Stack.Screen
        name="preferences"
        options={{ title: 'Afzalliklar', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="google-calendar"
        options={{ title: 'Google Kalendar', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="transcription-language"
        options={{ title: 'Matnga aylantirish tili', headerLargeTitle: false }}
      />
      <Stack.Screen name="privacy" options={{ title: "Maxfiylik va ma'lumotlar", headerLargeTitle: false }} />
      <Stack.Screen
        name="model-download"
        options={{ title: 'Matnga aylantirish modellari', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="diarization-model"
        options={{ title: 'Gapiruvchilarni ajratish', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="parakeet-benchmark"
        options={{ title: 'Parakeet Benchmark', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="licenses"
        options={{ title: 'Litsenziyalar va mualliflar', headerLargeTitle: false }}
      />
    </Stack>
  );
}
