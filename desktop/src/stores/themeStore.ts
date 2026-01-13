/**
 * Theme Store
 * Manages dark mode state with system preference detection and localStorage persistence.
 */
import { create } from 'zustand'

type ThemeMode = 'light' | 'dark' | 'system'

interface ThemeState {
  mode: ThemeMode
  isDark: boolean
  setMode: (mode: ThemeMode) => void
  initialize: () => void
}

const STORAGE_KEY = 'cratebot-theme'

function getSystemPreference(): boolean {
  if (typeof window === 'undefined') return false
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

function applyTheme(isDark: boolean) {
  if (typeof document === 'undefined') return

  if (isDark) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }
}

function computeIsDark(mode: ThemeMode): boolean {
  if (mode === 'system') {
    return getSystemPreference()
  }
  return mode === 'dark'
}

export const useThemeStore = create<ThemeState>((set, get) => ({
  mode: 'system',
  isDark: false,

  setMode: (mode: ThemeMode) => {
    const isDark = computeIsDark(mode)

    // Persist to localStorage
    try {
      localStorage.setItem(STORAGE_KEY, mode)
    } catch (e) {
      console.warn('Failed to save theme preference:', e)
    }

    applyTheme(isDark)
    set({ mode, isDark })
  },

  initialize: () => {
    // Load from localStorage
    let mode: ThemeMode = 'system'
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored === 'light' || stored === 'dark' || stored === 'system') {
        mode = stored
      }
    } catch (e) {
      console.warn('Failed to load theme preference:', e)
    }

    const isDark = computeIsDark(mode)
    applyTheme(isDark)
    set({ mode, isDark })

    // Listen for system preference changes
    if (typeof window !== 'undefined') {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
      const handleChange = () => {
        const currentMode = get().mode
        if (currentMode === 'system') {
          const newIsDark = getSystemPreference()
          applyTheme(newIsDark)
          set({ isDark: newIsDark })
        }
      }

      mediaQuery.addEventListener('change', handleChange)
    }
  },
}))
