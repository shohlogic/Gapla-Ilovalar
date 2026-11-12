import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';
import { Text } from '@/components/ui/Text';
import { FormSheet } from '@/components/ui/FormSheet';
import { SystemIcon } from '@/components/ui/SystemIcon';
import { iosColor } from '@/config/colors';
import { AppFont } from '@/lib/fonts';
import { safeHaptics } from '@/lib/utils';

const LABEL_COLOR = iosColor('label');
const PLACEHOLDER_COLOR = iosColor('tertiaryLabel');
// Subtle brand wash for context-phrase chips (multi-word entries).
// Gapla mandarinining 12%i (G54).
const CONTEXT_TINT = 'rgba(188,75,28,0.12)';

type Props = {
  visible: boolean;
  onClose: () => void;
  onSubmit: (input: string) => void;
};

export function AddWordsSheet({ visible, onClose, onSubmit }: Props) {
  const [input, setInput] = useState('');
  const inputRef = useRef<TextInput>(null);

  useEffect(() => {
    if (visible) {
      const t = setTimeout(() => inputRef.current?.focus(), 120);
      return () => clearTimeout(t);
    }
    setInput('');
  }, [visible]);

  // Keep raw indices so a chip can splice its own comma segment out of the input.
  const segments = useMemo(
    () =>
      input
        .split(',')
        .map((value, index) => ({ value: value.trim(), index }))
        .filter((segment) => segment.value.length > 0),
    [input],
  );

  const wordCount = segments.length;
  const canSubmit = wordCount > 0;
  const addLabel = wordCount <= 1 ? "So'z qo'shish" : `${wordCount} ta so'z qo'shish`;

  const handleSubmit = () => {
    if (!canSubmit) return;
    safeHaptics('light');
    onSubmit(input);
    onClose();
  };

  const removeSegment = (target: number) => {
    const next = input
      .split(',')
      .filter((_, index) => index !== target)
      .join(',')
      .replace(/^[\s,]+/, '');
    setInput(next);
    inputRef.current?.focus();
  };

  return (
    <FormSheet
      visible={visible}
      onClose={onClose}
      title="Lug'atga qo'shish"
      subtitle="Bir nechta so'zni vergul bilan ajrating."
      submitLabel={addLabel}
      canSubmit={canSubmit}
      onSubmit={handleSubmit}
    >
      <View
        style={{ borderCurve: 'continuous' }}
        className="rounded-xl bg-tertiarySystemFill px-3.5 py-3"
      >
        <TextInput
          ref={inputRef}
          value={input}
          onChangeText={setInput}
          placeholder="So'z, ism yoki atama qo'shing…"
          placeholderTextColor={PLACEHOLDER_COLOR}
          returnKeyType="done"
          onSubmitEditing={handleSubmit}
          autoCorrect={false}
          autoCapitalize="none"
          style={styles.input}
        />
      </View>

      {wordCount > 0 ? (
        <View className="mt-3 flex-row flex-wrap gap-2">
          {segments.map((segment) => {
            const isContext = segment.value.includes(' ');
            return (
              <Pressable
                key={segment.index}
                onPress={() => removeSegment(segment.index)}
                accessibilityRole="button"
                accessibilityLabel={`Olib tashlash: ${segment.value}`}
                style={({ pressed }) => ({
                  borderCurve: 'continuous',
                  backgroundColor: isContext ? CONTEXT_TINT : undefined,
                  opacity: pressed ? 0.6 : 1,
                })}
                className={`h-8 flex-row items-center gap-1.5 rounded-[10px] pl-3 pr-2 ${
                  isContext ? '' : 'bg-tertiarySystemFill'
                }`}
              >
                <Text
                  className={`text-[13.5px] font-medium ${isContext ? 'text-link' : 'text-label'}`}
                >
                  {segment.value}
                </Text>
                <SystemIcon
                  name="xmark.circle.fill"
                  mdName="X"
                  size={15}
                  color={isContext ? 'link' : 'tertiaryLabel'}
                />
              </Pressable>
            );
          })}
        </View>
      ) : null}

      <View className="mt-4 flex-row items-start gap-1.5">
        <SystemIcon name="info.circle" mdName="Info" size={13} color="tertiaryLabel" />
        <View className="flex-1">
          <Text className="text-[12px] text-tertiaryLabel">
            Talaffuzi qiyin so'z uchun kontekst ibora yozib ko'ring, masalan:
          </Text>
          <Text className="mt-0.5 text-[12px] italic text-secondaryLabel">
            «Bu so'z Synty»
          </Text>
        </View>
      </View>
    </FormSheet>
  );
}

const styles = StyleSheet.create({
  input: {
    color: LABEL_COLOR,
    fontFamily: AppFont.regular,
    fontSize: 15,
    fontWeight: '400',
  },
});
