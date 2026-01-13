import { create } from 'zustand'
import { api } from '../api/client'

interface ModelInfo {
  loaded: boolean
  path?: string
  name?: string
  selectedTags?: {
    genre: string[]
    album: string[]
    comments: string[]
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

  // Toast
  toast?: {
    message: string
    kind: 'success' | 'error'
  }

  // Actions
  checkServerStatus: () => Promise<void>
  loadModelInfo: () => Promise<void>
  loadModel: (modelPath: string) => Promise<void>
  loadSettings: () => Promise<void>
  setCurrentTask: (task: AppState['currentTask']) => void
  clearCurrentTask: () => void
  setToast: (message: string, kind?: 'success' | 'error') => void
  clearToast: () => void
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

  checkServerStatus: async () => {
    try {
      const response = await api.health()
      if (response.status === 'ok') {
        set({ serverStatus: 'connected', serverError: undefined })
        // Also load model info and settings
        get().loadModelInfo()
        get().loadSettings()
      } else {
        set({ serverStatus: 'error', serverError: 'Unexpected response' })
      }
    } catch (error) {
      const isElectron = typeof window !== 'undefined' && window.electron !== undefined
      if (isElectron) {
        try {
          const running = await window.electron!.python.isRunning()
          if (!running) {
            await window.electron!.python.restart()
            const retry = await api.health()
            if (retry.status === 'ok') {
              set({ serverStatus: 'connected', serverError: undefined })
              get().loadModelInfo()
              get().loadSettings()
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
  setToast: (message, kind = 'success') => set({ toast: { message, kind } }),
  clearToast: () => set({ toast: undefined }),
}))
