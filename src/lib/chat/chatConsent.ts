import type { ChatSendGateOptions } from '@/hooks/useChatSendGate';
import type { ProcessingMode } from '@/types';

export const CHAT_TAB_CONSENT_MESSAGE =
  "Chat bu so'rov uchun savolingizni, ayrim qaydlaringizni va keyingi 7 kungacha bo'lgan kalendaringizni siz tanlagan AI xizmatiga yuboradi. Maxfiylik va sinxronlash sozlamalaringiz o'zgarmaydi.";

// Only Local Mode asks before a Chat tab question leaves this iPhone.
export const chatTabGateOptions = (activeMode: ProcessingMode): ChatSendGateOptions => ({
  consentMessage: activeMode === 'private' ? CHAT_TAB_CONSENT_MESSAGE : null,
  source: 'chat_tab',
});
