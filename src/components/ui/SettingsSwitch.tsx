import React from 'react';
import { Switch, type SwitchProps } from 'react-native';
import { BRAND } from '@/config/colors';

// Yoqilgan holat Gapla mandarini — kompyuter ilovasidagi almashtirgichlar bilan bir xil (G54).
const SWITCH_TRACK_ON = BRAND;

export function SettingsSwitch(props: SwitchProps) {
  return <Switch trackColor={{ true: SWITCH_TRACK_ON, false: undefined }} {...props} />;
}
