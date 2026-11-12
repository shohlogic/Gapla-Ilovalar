// Gapla: one-tap cleanup mode switch (Tez, O'rta, Sekin) under the record button.
import React from 'react';
import { Pressable, View } from 'react-native';
import { Text } from './Text';
import { BRAND } from '@/config/colors';
import { safeHaptics } from '@/lib/utils';
import { GAPLA_MODES, useGaplaMode } from '@/lib/gaplaMode';

export function GaplaModeSelector({ disabled = false }: { disabled?: boolean }) {
  const [mode, setMode] = useGaplaMode();
  return (
    <View
      accessibilityRole="radiogroup"
      accessibilityLabel="Tozalash rejimi"
      className="mt-4 flex-row rounded-full bg-tertiarySystemFill p-1"
    >
      {GAPLA_MODES.map((item) => {
        const selected = item.id === mode;
        return (
          <Pressable
            key={item.id}
            disabled={disabled}
            onPress={() => {
              if (selected) return;
              safeHaptics('selection');
              setMode(item.id);
            }}
            accessibilityRole="radio"
            accessibilityState={{ selected, disabled }}
            accessibilityLabel={item.title}
            className="rounded-full px-3 py-1.5 active:opacity-80"
            style={selected ? { backgroundColor: BRAND } : undefined}
          >
            <Text
              className={
                selected ? 'text-xs font-bold text-white' : 'text-xs font-medium text-secondaryLabel'
              }
            >
              {item.title}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
