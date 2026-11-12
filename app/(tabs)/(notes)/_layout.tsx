import { Stack } from 'expo-router';
import { customHeaderStackOptions, glassStackOptions } from '@/config/navigation';

export default function NotesLayout() {
  return (
    <Stack screenOptions={glassStackOptions}>
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="notes" options={{ headerShown: false }} />
      <Stack.Screen name="[id]" options={customHeaderStackOptions} />
      <Stack.Screen name="actions" options={{ title: 'Amallar', headerLargeTitle: false }} />
      <Stack.Screen
        name="meeting-record"
        options={{ title: 'Uchrashuvni yozish', headerLargeTitle: false }}
      />
      <Stack.Screen
        name="voice-profiles"
        options={{ title: 'Ovoz profillari', headerLargeTitle: false }}
      />
      <Stack.Screen name="voice-profile" options={{ title: 'Profil', headerLargeTitle: false }} />
      <Stack.Screen
        name="voice-enrollment"
        options={{ title: 'Ovoz namunasi', headerLargeTitle: false }}
      />
    </Stack>
  );
}
