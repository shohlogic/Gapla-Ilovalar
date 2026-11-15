// Gapla (G66, owner 2026-11-15): every finished dictation goes into the Gapla clipboard on the server, as the computer
// does — «iphone dan 15 soniyalik gapirdim, u matnga aylantirdi va darhol bufferga avtomatik saqlab qoydi»; his choice
// «Faqat Gapla buferi»: the phone's own clipboard (UIPasteboard) gets nothing new.
//
// Same request as the keyboard's clipboard page (plugins/keyboard-extension/ios/GaplaClipboard.swift, add): `POST
// <Gapla>/v1/bufer` with `{matn, qurilma, maxfiy}` and the dictation key. Sent from the app, which already holds the
// text, so the keyboard does no extra work. In the background: no network or a server error never stops or slows the
// dictation and shows nothing. Secret fields never get here: iOS shows no custom keyboard in a password field, and the
// app has none. The text is never logged.
import { Platform } from 'react-native';
import { bridgeEndpoint, gaplaServerKey } from './keyboardServerKeySync';

const TIMEOUT_MS = 15_000;

function qurilma(): string {
  return Platform.OS === 'ios' && Platform.isPad ? 'iPad' : 'iPhone';
}

/** Adds the dictation to the Gapla clipboard. Resolves true once the server took it; never throws. */
export async function gaplaBufergaQosh(matn: string): Promise<boolean> {
  const text = matn.trim();
  if (!text) return false;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const key = await gaplaServerKey();
    if (!key) return false;
    const response = await fetch(`${bridgeEndpoint().replace(/\/+$/, '')}/bufer`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ matn: text, qurilma: qurilma(), maxfiy: false }),
      signal: controller.signal,
    });
    return response.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}
