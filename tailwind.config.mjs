/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          primary: 'var(--color-brand-primary)',
          bg: 'var(--color-brand-bg)',
          surface: 'var(--color-brand-surface)',
          el1: 'var(--color-brand-el1)',
          el2: 'var(--color-brand-el2)',
          el3: 'var(--color-brand-el3)',
          text1: 'var(--color-brand-text1)',
          text2: 'var(--color-brand-text2)',
          text3: 'var(--color-brand-text3)',
          text4: 'var(--color-brand-text4)',
        },
      },
      fontFamily: {
        sans: ['"Inter Variable"', 'Inter', 'system-ui', 'sans-serif'],
      },
    },
  },
}
