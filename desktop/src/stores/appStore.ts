import { create } from 'zustand'
import { api } from '../api/client'

// Update splash screen loading status
const updateLoadingStatus = (status: string) => {
  if (typeof window !== 'undefined' && (window as unknown as { updateLoadingStatus?: (s: string) => void }).updateLoadingStatus) {
    (window as unknown as { updateLoadingStatus: (s: string) => void }).updateLoadingStatus(status)
  }
}

// localStorage keys
const SETUP_COMPLETE_KEY = 'cratebot-setup-complete'
const TAGGING_PREFERENCES_KEY = 'cratebot-tagging-preferences'

interface ModelInfo {
  loaded: boolean
  path?: string
  name?: string
  selectedTags?: {
    genre: string[]
    timing: string[]
    mood: string[]
    descriptive: string[]
  }
}

interface Settings {
  anthropicApiKeySet: boolean
  vibeAvailable: boolean
  vibeStatus: string
  hookAvailable: boolean
  hookStatus: string
  modelsDirectory?: string
  cacheDirectory?: string
}

interface AppState {
  // Server status
  serverStatus: 'connecting' | 'connected' | 'disconnected' | 'error'
  serverError?: string

  // Model info
  model: ModelInfo

  // Settings
  settings: Settings

  // Current task (if any)
  currentTask?: {
    id: string
    type: 'training' | 'tagging' | 'vibe'
    progress: number
    status: string
    message?: string
  }

  // Tagging stats for status bar
  taggingStats?: {
    total: number
    completed: number
    pending: number
    processing: number
    failed: number
    startTime: number | null
    avgTimePerFile: number
    eta: number
  }

  // Recently tagged files for auto-loading in refine view
  recentlyTaggedFiles: string[]

  // Toast
  toast?: {
    message: string
    kind: 'success' | 'error'
  }

  // Setup state
  setupComplete: boolean
  pendingView: 'train' | null  // View to navigate to after setup completes
  taggingPreferences: {
    genre: { enabled: boolean; targetField: string }
    album: { enabled: boolean; targetField: string }
    mood: { enabled: boolean; targetField: string }
    comments: { enabled: boolean; targetField: string }
    likeness: { enabled: boolean; targetField: string }
    vibes: { enabled: boolean; shortTargetField: string; longTargetField: string }
    hooks: { enabled: boolean; targetField: string }
    overwrite: boolean
  }

  // Actions
  checkServerStatus: () => Promise<void>
  loadModelInfo: () => Promise<void>
  loadModel: (modelPath: string) => Promise<void>
  autoLoadDefaultModel: () => Promise<void>
  loadSettings: () => Promise<void>
  setCurrentTask: (task: AppState['currentTask']) => void
  clearCurrentTask: () => void
  setTaggingStats: (stats: AppState['taggingStats']) => void
  clearTaggingStats: () => void
  setToast: (message: string, kind?: 'success' | 'error') => void
  clearToast: () => void
  completeSetup: (pendingView?: 'train' | null) => void
  resetSetup: () => void
  clearPendingView: () => void
  setTaggingPreferences: (prefs: Partial<AppState['taggingPreferences']>) => void
  setRecentlyTaggedFiles: (files: string[]) => void
  clearRecentlyTaggedFiles: () => void
}

// Default tagging preferences
const DEFAULT_TAGGING_PREFERENCES: AppState['taggingPreferences'] = {
  genre: { enabled: true, targetField: 'TCON' },
  album: { enabled: true, targetField: 'TALB' },
  mood: { enabled: true, targetField: 'TIT1' },
  comments: { enabled: true, targetField: 'COMM' },
  likeness: { enabled: true, targetField: 'TIT1' },
  vibes: { enabled: false, shortTargetField: 'TXXX:CRATEBOT_VIBE_SHORT', longTargetField: 'COMM' },
  hooks: { enabled: false, targetField: 'TXXX:CRATEBOT_HOOK' },
  overwrite: true,
}

export const useAppStore = create<AppState>((set, get) => ({
  serverStatus: 'connecting',
  model: { loaded: false },
  settings: {
    anthropicApiKeySet: false,
    vibeAvailable: false,
    vibeStatus: 'Not configured',
    hookAvailable: false,
    hookStatus: 'Not available',
    modelsDirectory: undefined,
    cacheDirectory: undefined,
  },
  recentlyTaggedFiles: [],
  setupComplete: localStorage.getItem(SETUP_COMPLETE_KEY) === 'true',
  pendingView: null,
  taggingPreferences: (() => {
    try {
      const stored = localStorage.getItem(TAGGING_PREFERENCES_KEY)
      if (!stored) return DEFAULT_TAGGING_PREFERENCES

      const parsed = JSON.parse(stored)

      // Migrate from old flat format (writeGenre, writeAlbum, etc.)
      // to new nested format (genre: { enabled, targetField }, etc.)
      if ('writeGenre' in parsed || !('genre' in parsed) || typeof parsed.genre !== 'object') {
        localStorage.removeItem(TAGGING_PREFERENCES_KEY)
        return DEFAULT_TAGGING_PREFERENCES
      }

      return { ...DEFAULT_TAGGING_PREFERENCES, ...parsed }
    } catch {
      return DEFAULT_TAGGING_PREFERENCES
    }
  })(),

  checkServerStatus: async () => {
    const logRenderer = (message: string, data?: unknown) => {
      console.info(message, data ?? '')
      if (typeof window === 'undefined' || !window.electron?.log?.write) return
      let payload = message
      if (data !== undefined) {
        try {
          payload = `${message} ${JSON.stringify(data)}`
        } catch {
          payload = `${message} [unserializable data]`
        }
      }
      window.electron.log.write(payload)
    }

    updateLoadingStatus('Connecting to server...')
    logRenderer('[server] Health check start', {
      bases: api.getApiBases(),
      activeBase: api.getActiveBase(),
    })
    try {
      const response = await api.health()
      logRenderer('[server] Health check response', {
        response,
        activeBase: api.getActiveBase(),
      })
      if (response.status === 'ok') {
        set({ serverStatus: 'connected', serverError: undefined })
        // Also load model info and settings
        await get().loadModelInfo()
        get().loadSettings()
        // Auto-load default model if no model is loaded
        if (!get().model.loaded) {
          await get().autoLoadDefaultModel()
        }
        updateLoadingStatus('Ready!')
      } else {
        set({ serverStatus: 'error', serverError: 'Unexpected response' })
      }
    } catch (error) {
      logRenderer('[server] Health check failed', {
        error: error instanceof Error ? error.message : String(error),
        activeBase: api.getActiveBase(),
        bases: api.getApiBases(),
      })
      const isElectron = typeof window !== 'undefined' && window.electron !== undefined
      if (isElectron) {
        try {
          updateLoadingStatus('Starting server...')
          const running = await window.electron!.python.isRunning()
          if (!running) {
            await window.electron!.python.restart()
            const retry = await api.health()
            if (retry.status === 'ok') {
              set({ serverStatus: 'connected', serverError: undefined })
              await get().loadModelInfo()
              get().loadSettings()
              // Auto-load default model if no model is loaded
              if (!get().model.loaded) {
                await get().autoLoadDefaultModel()
              }
              updateLoadingStatus('Ready!')
              return
            }
          }
        } catch (restartError) {
          console.error('Failed to restart Python server:', restartError)
        }
      }
      set({
        serverStatus: 'disconnected',
        serverError: error instanceof Error ? error.message : 'Connection failed'
      })
    }
  },

  loadModelInfo: async () => {
    try {
      const info = await api.getModelInfo()
      set({
        model: {
          loaded: info.loaded,
          path: info.path,
          name: info.name,
          selectedTags: info.selected_tags,
        }
      })
    } catch (error) {
      console.error('Failed to load model info:', error)
    }
  },

  loadModel: async (modelPath: string) => {
    try {
      await api.loadModel(modelPath)
      await get().loadModelInfo()
    } catch (error) {
      console.error('Failed to load model:', error)
      throw error
    }
  },

  autoLoadDefaultModel: async () => {
    updateLoadingStatus('Loading default model...')
    try {
      const bundledPath = 'bundled://cratebot-default'
      await api.loadModel(bundledPath)
      await get().loadModelInfo()
    } catch (error) {
      // Silent fail - user can manually load in wizard
      console.log('Auto-load default model failed (may not be bundled):', error)
    }
  },

  loadSettings: async () => {
    try {
      const settings = await api.getSettings()
      set({
        settings: {
          anthropicApiKeySet: settings.anthropic_api_key_set,
          vibeAvailable: settings.vibe_available,
          vibeStatus: settings.vibe_status,
          hookAvailable: settings.hook_available,
          hookStatus: settings.hook_status,
          modelsDirectory: settings.models_directory,
          cacheDirectory: settings.cache_directory,
        }
      })
    } catch (error) {
      console.error('Failed to load settings:', error)
    }
  },

  setCurrentTask: (task) => set({ currentTask: task }),
  clearCurrentTask: () => set({ currentTask: undefined }),
  setTaggingStats: (stats) => set({ taggingStats: stats }),
  clearTaggingStats: () => set({ taggingStats: undefined }),
  setToast: (message, kind = 'success') => set({ toast: { message, kind } }),
  clearToast: () => set({ toast: undefined }),

  completeSetup: (pendingView = null) => {
    localStorage.setItem(SETUP_COMPLETE_KEY, 'true')
    set({ setupComplete: true, pendingView })
  },

  resetSetup: () => {
    localStorage.removeItem(SETUP_COMPLETE_KEY)
    set({ setupComplete: false, pendingView: null })
  },

  clearPendingView: () => set({ pendingView: null }),

  setTaggingPreferences: (prefs) => {
    const newPrefs = { ...get().taggingPreferences, ...prefs }
    localStorage.setItem(TAGGING_PREFERENCES_KEY, JSON.stringify(newPrefs))
    set({ taggingPreferences: newPrefs })
  },
  setRecentlyTaggedFiles: (files) => set({ recentlyTaggedFiles: files }),
  clearRecentlyTaggedFiles: () => set({ recentlyTaggedFiles: [] }),
}))
