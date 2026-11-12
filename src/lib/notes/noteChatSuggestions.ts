export interface NoteChatSuggestion {
  label: string;
  prompt: string;
}

// The prompt is the user's own question: it is sent as typed and shown in the chat as their message,
// so it is written in Uzbek like the label (the model answers in the question's language).
const MEETING_SUGGESTIONS: readonly NoteChatSuggestion[] = [
  {
    label: 'Vazifalarni sanab ber',
    prompt: "Yuqoridagi uchrashuvdan keyin men bajarishim kerak bo'lgan keyingi qadamlar qaysilar?",
  },
  {
    label: 'Keyingi xatni yoz',
    prompt:
      "Yuqoridagi uchrashuv bo'yicha keyingi xatni yozib ber: qisqa xulosa, qarorlar va keyingi qadamlar.",
  },
  {
    label: 'Asosiy qarorlar',
    prompt: 'Yuqoridagi uchrashuvda qanday qarorlar qabul qilindi?',
  },
  {
    label: 'Savol-javoblar',
    prompt: 'Yuqoridagi uchrashuvda berilgan savollarni va ularga berilgan javoblarni sanab ber.',
  },
];

const NOTE_SUGGESTIONS: readonly NoteChatSuggestion[] = [
  {
    label: 'Qisqacha xulosa',
    prompt: 'Bu qaydni bir nechta band bilan qisqacha xulosa qil.',
  },
  {
    label: 'Vazifalarni sanab ber',
    prompt: "Shu qayddan kelib chiqib, men bajarishim kerak bo'lgan keyingi qadamlar qaysilar?",
  },
  {
    label: 'Xat qoralamasi',
    prompt: 'Shu qayd asosida xat qoralamasini yozib ber.',
  },
];

export function getNoteChatSuggestions(isMeeting: boolean): readonly NoteChatSuggestion[] {
  return isMeeting ? MEETING_SUGGESTIONS : NOTE_SUGGESTIONS;
}
