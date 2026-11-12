import {
  isLocalContextLimitError,
  LocalReasoningError,
  UNSUPPORTED_LANGUAGE_MESSAGE,
} from '@/lib/localReasoning';
import { UPGRADE_REQUIRED_MESSAGE } from '@/lib/policyMessages';

export const CHAT_CONNECTION_ERROR_MESSAGE = "Ulanishni tekshirib, qayta urinib ko'ring.";
export const CHAT_ON_DEVICE_UNAVAILABLE_MESSAGE = 'Qurilmadagi AI hozir mavjud emas.';
export const CHAT_CONTEXT_LIMIT_MESSAGE =
  "Bu savolga qurilmadagi AI sig'dira oladiganidan ko'proq ma'lumot kerak. Qisqaroq savol bering yoki yangi chat boshlang.";
// Note chat has already retried with less of the note by then, so the note itself is what's too big.
export const NOTE_CHAT_CONTEXT_LIMIT_MESSAGE = 'Bu qayd qurilmadagi AI uchun juda uzun.';
export const CHAT_GUARDRAIL_MESSAGE =
  "Qurilmadagi AI bu savolga javob bermadi. Savolni boshqacha so'rab ko'ring.";
export const CHAT_OUTPUT_LIMIT_MESSAGE =
  "Javob qurilmadagi AI uchun juda uzun chiqdi. Aniqroq savol berib ko'ring.";
export const CHAT_NOTES_READ_ERROR_MESSAGE = "Qaydlaringizni o'qib bo'lmadi. Qayta urinib ko'ring.";
export const CHAT_EMPTY_ANSWER_MESSAGE = "Javob bo'sh keldi. Qayta urinib ko'ring.";
export const CHAT_SESSION_EXPIRED_MESSAGE =
  'Sessiyangiz muddati tugadi. Chatni davom ettirish uchun qayta kiring.';
export const CHAT_RATE_LIMITED_MESSAGE =
  "Foydalanish limitiga yetdingiz. Keyinroq qayta urinib ko'ring.";
export const CHAT_SERVER_ERROR_MESSAGE = "Gapla hozir javob bera olmadi. Qayta urinib ko'ring.";
export const CHAT_REQUEST_FAILED_MESSAGE =
  "Gapla bu savolni qabul qila olmadi. Qayta urinib ko'ring.";

// Policy refusals say what to do, so they're shown as they are. They are being worded in Uzbek
// ("Tashkilotingiz …"), and an English one may still arrive, so both are recognised.
const ORGANIZATION_POLICY = /^Your organization|tashkilot/i;

/** The turn couldn't search or read the notes on this phone, so nothing left it. */
export class ChatNotesReadError extends Error {
  readonly cause?: unknown;

  constructor(cause?: unknown) {
    super('Could not read notes for chat');
    this.name = 'ChatNotesReadError';
    this.cause = cause;
  }
}

/** The model answered with nothing to show (only its thinking, say), so the turn can be retried. */
export class ChatEmptyAnswerError extends Error {
  constructor() {
    super('Chat answer was empty');
    this.name = 'ChatEmptyAnswerError';
  }
}

// Read by shape rather than instanceof, so this module doesn't pull the API client, and with it
// the auth store, into everything that words a chat error.
const apiErrorStatus = (error: unknown): number | null => {
  if (!(error instanceof Error) || error.name !== 'ApiError') return null;
  const { status } = error as Error & { status?: unknown };
  return typeof status === 'number' ? status : null;
};

// The server answered, so the connection is fine: what went wrong is said instead.
const toApiErrorMessage = (status: number): string => {
  if (status === 401) return CHAT_SESSION_EXPIRED_MESSAGE;
  if (status === 429) return CHAT_RATE_LIMITED_MESSAGE;
  if (status >= 500) return CHAT_SERVER_ERROR_MESSAGE;
  return CHAT_REQUEST_FAILED_MESSAGE;
};

export interface ChatErrorMessageOptions {
  surface?: 'chat' | 'noteChat';
}

// On-device requests never touch the network, so none of them reads as a connection problem.
// LOCAL_REASONING_UNAVAILABLE carries copy written from the device's readiness (Apple Intelligence
// off, model still downloading, ...) that says what to do, so it is shown as is. A guardrail or an
// output limit gives the same answer on a retry, so their copy says what to change instead.
const toLocalReasoningMessage = (error: LocalReasoningError): string => {
  if (error.code === 'APPLE_LLM_UNSUPPORTED_LANGUAGE') return UNSUPPORTED_LANGUAGE_MESSAGE;
  if (error.code === 'APPLE_LLM_GUARDRAIL') return CHAT_GUARDRAIL_MESSAGE;
  if (error.code === 'APPLE_LLM_OUTPUT_LIMIT') return CHAT_OUTPUT_LIMIT_MESSAGE;
  if (error.code === 'LOCAL_REASONING_UNAVAILABLE' && error.message.trim()) return error.message;
  return CHAT_ON_DEVICE_UNAVAILABLE_MESSAGE;
};

// Provider and network errors carry raw text that means nothing to the user, so only the cases
// with something to act on get their own copy; timeouts, fetch failures and the rest read as a
// connection problem. A Cloud error status gets copy of its own, never the server's text.
export const toChatErrorMessage = (
  error: unknown,
  { surface = 'chat' }: ChatErrorMessageOptions = {},
): string => {
  if (isLocalContextLimitError(error)) {
    return surface === 'noteChat' ? NOTE_CHAT_CONTEXT_LIMIT_MESSAGE : CHAT_CONTEXT_LIMIT_MESSAGE;
  }
  if (error instanceof LocalReasoningError) return toLocalReasoningMessage(error);
  if (error instanceof ChatNotesReadError) return CHAT_NOTES_READ_ERROR_MESSAGE;
  if (error instanceof ChatEmptyAnswerError) return CHAT_EMPTY_ANSWER_MESSAGE;
  if (error instanceof Error && ORGANIZATION_POLICY.test(error.message)) {
    return error.message;
  }
  if (error instanceof Error && error.message === UPGRADE_REQUIRED_MESSAGE) return error.message;
  const status = apiErrorStatus(error);
  if (status !== null) return toApiErrorMessage(status);
  // Route refusals and provider rejections are marked as not worth retrying, and their messages
  // say what to fix (a missing key, an unsupported model).
  if (
    error instanceof Error &&
    (error as { retryable?: unknown }).retryable === false &&
    error.message
  ) {
    return error.message;
  }
  return CHAT_CONNECTION_ERROR_MESSAGE;
};
