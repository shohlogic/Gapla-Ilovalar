const { platformColor } = require('nativewind/theme');

// Gapla ranglari (G54) — src/config/colors.ts bilan bir xil; kontrast hisobi o'sha faylda.
const BRAND = '#BC4B1C';
const BRAND_LINK = '#B84A1C';
const BRAND_RING = '#DE5F2A';
const INK = '#1F2328';

const ios = (iosName, androidFallback, web = androidFallback) =>
  platformColor(iosName, androidFallback, web);

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./App.{js,jsx,ts,tsx}', './app/**/*.{js,jsx,ts,tsx}', './src/**/*.{js,jsx,ts,tsx}'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: {
        brand: BRAND,

        label: ios('label', '#000000', '#000000'),
        secondaryLabel: ios('secondaryLabel', '#3C3C434D', '#3C3C434D'),
        tertiaryLabel: ios('tertiaryLabel', '#3C3C434D', '#3C3C434D'),
        quaternaryLabel: ios('quaternaryLabel', '#3C3C432E', '#3C3C432E'),

        systemBackground: '#F8F6F5',
        secondarySystemBackground: ios('secondarySystemBackground', '#F2F2F7', '#F2F2F7'),
        secondarySystemGroupedBackground: '#FFFFFF',
        tertiarySystemFill: ios('tertiarySystemFill', '#76768014', '#76768014'),
        quaternarySystemFill: ios('quaternarySystemFill', '#7676800F', '#7676800F'),

        separator: ios('separator', '#3C3C4349', '#3C3C4349'),
        link: BRAND_LINK,

        systemRed: ios('systemRed', '#FF3B30', '#FF3B30'),
        systemGreen: ios('systemGreen', '#34C759', '#34C759'),
        // Tizim ko'ki o'rniga Gapla mandarini.
        systemBlue: BRAND,
        systemOrange: ios('systemOrange', '#FF9500', '#FF9500'),

        // Iliq kulrang chegara (eski ko'kish kulrang o'rniga), matn grafit — kompyuterdagidek.
        border: '#E7E3E0',
        input: '#E7E3E0',
        ring: BRAND_RING,
        background: '#FFFFFF',
        foreground: INK,
        primary: {
          DEFAULT: BRAND,
          foreground: '#FFFFFF',
        },
        secondary: {
          DEFAULT: '#F5F3F2',
          foreground: INK,
        },
        destructive: {
          DEFAULT: 'hsl(0 84.2% 60.2%)',
          foreground: 'hsl(210 40% 98%)',
        },
        muted: {
          DEFAULT: '#F5F3F2',
          // Oq fonda 5,81:1, #F5F3F2 ustida 5,25:1.
          foreground: '#6B6460',
        },
        accent: {
          DEFAULT: '#F5F3F2',
          foreground: INK,
        },
        popover: {
          DEFAULT: '#FFFFFF',
          foreground: INK,
        },
        card: {
          DEFAULT: '#FFFFFF',
          foreground: INK,
        },
      },
      borderRadius: {
        lg: '0.5rem',
        md: '0.375rem',
        sm: '0.25rem',
      },
      fontFamily: {
        sans: ['SpaceGrotesk_400Regular'],
      },
    },
  },
  plugins: [],
};
