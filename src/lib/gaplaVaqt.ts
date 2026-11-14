// Gapla (G64): dictation timing. Each step writes one line (job, step, time in ms, a few numbers,
// never the text) through the native side to the device log and a small App Group file
// (modules/app-group-storage/ios/GaplaVaqt.swift). The keyboard writes its own steps into the same
// file. Also the three headers the Gapla server writes into its log for every audio request.
import { Platform } from 'react-native';
import { AppGroupStorage } from '../../modules/app-group-storage/src';

let currentJob: string | null = null;
let recordingStoppedAtMs: number | null = null;

/** A recording stopped: the following lines and the next audio request belong to it. */
export function gaplaVaqtBoshla(job: string, stoppedAtMs: number): void {
  currentJob = job;
  recordingStoppedAtMs = stoppedAtMs;
}

/** One step of the current dictation. */
export function gaplaVaqt(
  qadam: string,
  extra: Record<string, string | number | boolean | null | undefined> = {},
): void {
  const parts = Object.entries(extra)
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([key, value]) => `${key}=${String(value).replace(/\s+/g, '_')}`);
  AppGroupStorage.gaplaVaqt(qadam, currentJob, parts.length ? parts.join(' ') : null);
}

export function gaplaQurilma(): 'ipad' | 'iphone' {
  return Platform.OS === 'ios' && Platform.isPad ? 'ipad' : 'iphone';
}

/**
 * Headers for one audio request to the Gapla server. The stop time is given once: a later retry
 * of an old recording is sent without it instead of claiming hours of delay.
 */
export function gaplaVaqtSarlavhalari(): Record<string, string> {
  const headers: Record<string, string> = { 'X-Gapla-Qurilma': gaplaQurilma() };
  if (recordingStoppedAtMs !== null) {
    headers['X-Gapla-Yozuv-Tugadi'] = String(Math.round(recordingStoppedAtMs));
    recordingStoppedAtMs = null;
  }
  headers['X-Gapla-Yuborildi'] = String(Date.now());
  return headers;
}
