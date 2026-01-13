/** @type {import('tailwindcss').Config} */
/**
 * CrateBot3 Design System - "Vinyl Warmth"
 *
 * Concept: Warm analog aesthetic meets modern precision.
 * Think: Late-night DJ booth, glowing VU meters, vinyl warmth.
 */

export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      // ═══════════════════════════════════════════════════════════
      // BRAND COLORS - Vinyl Warmth Palette
      // ═══════════════════════════════════════════════════════════
      colors: {
        // Primary - Warm Amber (the soul of CrateBot)
        'amber': {
          50: '#fffbeb',
          100: '#fef3c7',
          200: '#fde68a',
          300: '#fcd34d',
          400: '#fbbf24',
          500: '#f59e0b',
          600: '#d97706',
          700: '#b45309',
          800: '#92400e',
          900: '#78350f',
        },

        // Secondary - Electric Purple (creative energy)
        'violet': {
          50: '#f5f3ff',
          100: '#ede9fe',
          200: '#ddd6fe',
          300: '#c4b5fd',
          400: '#a78bfa',
          500: '#8b5cf6',
          600: '#7c3aed',
          700: '#6d28d9',
          800: '#5b21b6',
          900: '#4c1d95',
        },

        // Semantic colors
        'success': '#10b981',
        'warning': '#f59e0b',
        'danger': '#ef4444',
        'info': '#3b82f6',

        // Surface colors - Warm neutrals
        'surface': {
          'light': '#faf9f7',
          'elevated': '#ffffff',
          'sunken': '#f5f3f0',
          'dark': '#1a1918',
          'dark-elevated': '#242322',
          'dark-sunken': '#121110',
        },

        // Sidebar
        'sidebar': {
          'light': '#f0eeeb',
          'dark': '#141312',
        },

        // Text colors
        'text': {
          'primary': '#1c1917',
          'secondary': '#57534e',
          'muted': '#a8a29e',
          'inverse': '#fafaf9',
          'dark-primary': '#fafaf9',
          'dark-secondary': '#d6d3d1',
          'dark-muted': '#78716c',
        },

        // Border colors
        'border': {
          'light': '#e7e5e4',
          'dark': '#3f3f3f',
        },

        // Waveform specific
        'waveform': {
          'base': '#d6d3d1',
          'progress': '#f59e0b',
          'cursor': '#d97706',
          'dark-base': '#525252',
          'dark-progress': '#fbbf24',
        },

        // Legacy compatibility
        'accent': '#f59e0b',
        'accent-hover': '#d97706',
        'muted': '#a8a29e',
      },

      // ═══════════════════════════════════════════════════════════
      // TYPOGRAPHY
      // ═══════════════════════════════════════════════════════════
      fontFamily: {
        'display': ['DM Sans', 'system-ui', 'sans-serif'],
        'sans': ['Inter', 'system-ui', 'sans-serif'],
        'mono': ['JetBrains Mono', 'SF Mono', 'Consolas', 'monospace'],
      },

      fontSize: {
        'display-lg': ['2.5rem', { lineHeight: '1.1', letterSpacing: '-0.02em', fontWeight: '700' }],
        'display-md': ['2rem', { lineHeight: '1.15', letterSpacing: '-0.02em', fontWeight: '700' }],
        'display-sm': ['1.5rem', { lineHeight: '1.2', letterSpacing: '-0.01em', fontWeight: '600' }],
        'heading-lg': ['1.25rem', { lineHeight: '1.3', fontWeight: '600' }],
        'heading-md': ['1.125rem', { lineHeight: '1.4', fontWeight: '600' }],
        'heading-sm': ['1rem', { lineHeight: '1.4', fontWeight: '600' }],
        'body-lg': ['1rem', { lineHeight: '1.5' }],
        'body-md': ['0.875rem', { lineHeight: '1.5' }],
        'body-sm': ['0.8125rem', { lineHeight: '1.5' }],
        'caption': ['0.75rem', { lineHeight: '1.4' }],
        'overline': ['0.6875rem', { lineHeight: '1.3', letterSpacing: '0.05em', fontWeight: '600' }],
      },

      // ═══════════════════════════════════════════════════════════
      // SPACING & LAYOUT
      // ═══════════════════════════════════════════════════════════
      spacing: {
        '18': '4.5rem',
        '22': '5.5rem',
      },

      borderRadius: {
        'sm': '0.375rem',
        'DEFAULT': '0.5rem',
        'md': '0.625rem',
        'lg': '0.75rem',
        'xl': '1rem',
        '2xl': '1.25rem',
        '3xl': '1.5rem',
      },

      // ═══════════════════════════════════════════════════════════
      // SHADOWS
      // ═══════════════════════════════════════════════════════════
      boxShadow: {
        'sm': '0 1px 2px rgba(28, 25, 23, 0.05)',
        'DEFAULT': '0 2px 4px rgba(28, 25, 23, 0.06), 0 1px 2px rgba(28, 25, 23, 0.04)',
        'md': '0 4px 8px rgba(28, 25, 23, 0.08), 0 2px 4px rgba(28, 25, 23, 0.04)',
        'lg': '0 8px 16px rgba(28, 25, 23, 0.1), 0 4px 8px rgba(28, 25, 23, 0.05)',
        'xl': '0 16px 32px rgba(28, 25, 23, 0.12), 0 8px 16px rgba(28, 25, 23, 0.06)',
        'glow-amber': '0 0 20px rgba(245, 158, 11, 0.3)',
        'glow-amber-lg': '0 0 40px rgba(245, 158, 11, 0.4)',
        'glow-violet': '0 0 20px rgba(139, 92, 246, 0.3)',
        'card': '0 2px 8px rgba(28, 25, 23, 0.06), 0 0 1px rgba(28, 25, 23, 0.1)',
        'card-hover': '0 8px 24px rgba(28, 25, 23, 0.1), 0 0 1px rgba(28, 25, 23, 0.1)',
        'elevated': '0 24px 48px rgba(28, 25, 23, 0.16), 0 12px 24px rgba(28, 25, 23, 0.08)',
        'inner-soft': 'inset 0 2px 4px rgba(28, 25, 23, 0.04)',
        'subtle': '0 1px 3px rgba(0, 0, 0, 0.08)',
      },

      // ═══════════════════════════════════════════════════════════
      // ANIMATIONS
      // ═══════════════════════════════════════════════════════════
      animation: {
        'fade-in': 'fadeIn 0.3s ease-out',
        'slide-up': 'slideUp 0.4s ease-out',
        'slide-down': 'slideDown 0.3s ease-out',
        'scale-in': 'scaleIn 0.2s ease-out',
        'stagger': 'slideUp 0.4s ease-out backwards',
        'spin-slow': 'spin 3s linear infinite',
        'pulse-soft': 'pulseSoft 2s ease-in-out infinite',
        'glow': 'glow 2s ease-in-out infinite',
        'shimmer': 'shimmer 2s linear infinite',
        'vinyl-spin': 'spin 2s linear infinite',
        'vinyl-spin-slow': 'spin 8s linear infinite',
      },

      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        slideDown: {
          '0%': { opacity: '0', transform: 'translateY(-10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        scaleIn: {
          '0%': { opacity: '0', transform: 'scale(0.95)' },
          '100%': { opacity: '1', transform: 'scale(1)' },
        },
        pulseSoft: {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0.7' },
        },
        glow: {
          '0%, 100%': { boxShadow: '0 0 20px rgba(245, 158, 11, 0.3)' },
          '50%': { boxShadow: '0 0 30px rgba(245, 158, 11, 0.5)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
      },

      // ═══════════════════════════════════════════════════════════
      // TRANSITIONS
      // ═══════════════════════════════════════════════════════════
      transitionDuration: {
        '250': '250ms',
        '350': '350ms',
        '400': '400ms',
      },

      transitionTimingFunction: {
        'bounce-in': 'cubic-bezier(0.68, -0.55, 0.265, 1.55)',
        'smooth': 'cubic-bezier(0.4, 0, 0.2, 1)',
        'snap': 'cubic-bezier(0, 0, 0.2, 1)',
      },

      backdropBlur: {
        'xs': '2px',
      },

      backgroundImage: {
        'noise': "url(\"data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E\")",
        'gradient-radial': 'radial-gradient(var(--tw-gradient-stops))',
        'gradient-warm': 'linear-gradient(135deg, var(--tw-gradient-stops))',
      },
    },
  },
  plugins: [],
}
