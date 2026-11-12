import { Stack } from 'expo-router';
import { customHeaderStackOptions, glassStackOptions } from '@/config/navigation';

export default function ChatLayout(): React.JSX.Element {
  return (
    <Stack screenOptions={glassStackOptions}>
      <Stack.Screen name="index" options={customHeaderStackOptions} />
      <Stack.Screen name="[id]" options={customHeaderStackOptions} />
      <Stack.Screen name="history" options={customHeaderStackOptions} />
      <Stack.Screen name="note/[id]" options={customHeaderStackOptions} />
      <Stack.Screen name="note/actions" options={{ title: 'Amallar', headerLargeTitle: false }} />
      <Stack.Screen
        name="note/voice-enrollment"
        options={{ title: 'Ovoz namunasi', headerLargeTitle: false }}
      />
    </Stack>
  );
}
