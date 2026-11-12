import Svg, { Rect } from 'react-native-svg';

/**
 * The Gapla brand mark: a text cursor (I-beam) followed by four sound bars, as in the app icon.
 * Drawn as filled rectangles in one colour with a transparent background, so it sits cleanly on
 * any surface. The component keeps its old name so existing imports keep working.
 * `cursorColor` paints only the I-beam, as the app icon does (mandarin cursor, white bars).
 * Coordinates are the icon's own 1024-unit grid, cropped to the mark.
 */
export function OpenWhisprMark({
  size = 32,
  color = '#FFFFFF',
  cursorColor,
}: {
  size?: number;
  color?: string;
  cursorColor?: string;
}) {
  const cursor = cursorColor ?? color;
  return (
    <Svg width={size} height={size} viewBox="195 301 636 421">
      <Rect x={195} y={301} width={165} height={55} fill={cursor} />
      <Rect x={250} y={301} width={55} height={421} fill={cursor} />
      <Rect x={195} y={667} width={165} height={55} fill={cursor} />
      <Rect x={431} y={449} width={55} height={126} fill={color} />
      <Rect x={546} y={390} width={55} height={244} fill={color} />
      <Rect x={661} y={390} width={55} height={244} fill={color} />
      <Rect x={776} y={449} width={55} height={126} fill={color} />
    </Svg>
  );
}
