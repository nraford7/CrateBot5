/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // macOS-inspired color palette
        'sidebar': '#f5f5f7',
        'sidebar-dark': '#1d1d1f',
        'accent': '#0071e3',
        'accent-hover': '#0077ed',
        'surface': '#ffffff',
        'surface-dark': '#2d2d2d',
        'muted': '#86868b',
        'border': '#d2d2d7',
        'border-dark': '#424245',
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Text', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
      },
      fontSize: {
        'xxs': '0.625rem',
      },
      borderRadius: {
        'xl': '0.875rem',
        '2xl': '1rem',
      },
      boxShadow: {
        'subtle': '0 1px 3px rgba(0, 0, 0, 0.08)',
        'card': '0 2px 8px rgba(0, 0, 0, 0.08)',
        'elevated': '0 4px 16px rgba(0, 0, 0, 0.12)',
      },
    },
  },
  plugins: [],
}
