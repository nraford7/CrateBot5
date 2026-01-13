import { useState } from 'react'
import { Key, FolderOpen, Check, X, RefreshCw, Loader2, Sun, Moon, Monitor } from 'lucide-react'
import { useAppStore } from '../stores/appStore'
import { useThemeStore } from '../stores/themeStore'
import { useElectron } from '../hooks/useElectron'
import { api } from '../api/client'

type ThemeMode = 'light' | 'dark' | 'system'

const themeOptions: { value: ThemeMode; label: string; icon: typeof Sun }[] = [
  { value: 'light', label: 'Light', icon: Sun },
  { value: 'dark', label: 'Dark', icon: Moon },
  { value: 'system', label: 'System', icon: Monitor },
]

function ThemeSelector() {
  const { mode, setMode } = useThemeStore()

  return (
    <div className="flex gap-2">
      {themeOptions.map((option) => {
        const Icon = option.icon
        const isSelected = mode === option.value
        return (
          <button
            key={option.value}
            onClick={() => setMode(option.value)}
            className={`flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-lg border transition-colors ${
              isSelected
                ? 'border-accent bg-accent/10 text-accent'
                : 'border-border dark:border-border-dark text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800'
            }`}
          >
            <Icon className="w-4 h-4" />
            <span className="text-sm font-medium">{option.label}</span>
          </button>
        )
      })}
    </div>
  )
}

export function SettingsTab() {
  const { settings, model, loadSettings, loadModel, serverStatus, setToast } = useAppStore()
  const { dialog } = useElectron()
  const [apiKey, setApiKey] = useState('')
  const [isSavingKey, setIsSavingKey] = useState(false)
  const [modelPath, setModelPath] = useState('')
  const [isLoadingModel, setIsLoadingModel] = useState(false)
  const buildStamp = __BUILD_STAMP__
  const buildLabel = new Date(buildStamp).toLocaleString()

  const handleSaveApiKey = async () => {
    if (!apiKey.trim()) return

    setIsSavingKey(true)
    try {
      await api.setApiKey(apiKey)
      setApiKey('')
      await loadSettings()
    } catch (error) {
      console.error('Failed to save API key:', error)
    } finally {
      setIsSavingKey(false)
    }
  }

  const handleLoadModel = async () => {
    if (!modelPath.trim()) return

    setIsLoadingModel(true)
    try {
      await loadModel(modelPath)
      setToast('Model loaded', 'success')
      setModelPath('')
    } catch (error) {
      console.error('Failed to load model:', error)
    } finally {
      setIsLoadingModel(false)
    }
  }

  const handleBrowseModel = async () => {
    const files = await dialog.openFiles({
      filters: [{ name: 'Model Files', extensions: ['pkl'] }],
    })
    if (files.length > 0) {
      setModelPath(files[0])
    }
  }

  const isServerDisconnected = serverStatus !== 'connected'

  return (
    <div className="p-6 max-w-4xl w-full">
      <div className="mb-8">
        <h1 className="text-2xl font-semibold text-gray-900 dark:text-white mb-2">
          Settings
        </h1>
        <p className="text-muted">
          Configure API keys, models, and preferences.
        </p>
      </div>

      {/* API Key */}
      <div className="card mb-6">
        <div className="flex items-center gap-2 mb-4">
          <Key className="w-5 h-5 text-accent" />
          <h2 className="text-lg font-medium text-gray-900 dark:text-white">
            Anthropic API Key
          </h2>
          {settings.anthropicApiKeySet ? (
            <span className="flex items-center gap-1 text-xs text-green-600 bg-green-50 dark:bg-green-900/20 px-2 py-0.5 rounded">
              <Check className="w-3 h-3" /> Set
            </span>
          ) : (
            <span className="flex items-center gap-1 text-xs text-amber-600 bg-amber-50 dark:bg-amber-900/20 px-2 py-0.5 rounded">
              <X className="w-3 h-3" /> Not set
            </span>
          )}
        </div>

        <p className="text-sm text-muted mb-4">
          Required for AI vibe generation. Get your key from{' '}
          <a href="https://console.anthropic.com" className="text-accent hover:underline">
            console.anthropic.com
          </a>
        </p>

        <div className="flex gap-3">
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder={settings.anthropicApiKeySet ? '••••••••••••••••' : 'sk-ant-...'}
            className="input flex-1"
            disabled={isSavingKey}
          />
          <button
            onClick={handleSaveApiKey}
            disabled={isServerDisconnected || isSavingKey || !apiKey.trim()}
            className="btn btn-primary"
          >
            {isSavingKey ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Save'}
          </button>
        </div>
      </div>

      {/* Model */}
      <div className="card mb-6">
        <div className="flex items-center gap-2 mb-4">
          <RefreshCw className="w-5 h-5 text-accent" />
          <h2 className="text-lg font-medium text-gray-900 dark:text-white">
            Model
          </h2>
          {model.loaded ? (
            <span className="flex items-center gap-1 text-xs text-green-600 bg-green-50 dark:bg-green-900/20 px-2 py-0.5 rounded">
              <Check className="w-3 h-3" /> Loaded
            </span>
          ) : (
            <span className="flex items-center gap-1 text-xs text-muted bg-gray-100 dark:bg-gray-800 px-2 py-0.5 rounded">
              Not loaded
            </span>
          )}
        </div>

        {model.loaded && (
          <div className="mb-4 p-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
            <p className="text-sm">
              <span className="text-muted">Path:</span>{' '}
              <span className="font-mono text-xs">{model.path}</span>
            </p>
            {model.selectedTags && (
              <div className="mt-2 text-sm">
                <span className="text-muted">Tags:</span>{' '}
                {model.selectedTags.genre.length} genres,{' '}
                {model.selectedTags.album.length} albums,{' '}
                {model.selectedTags.comments.length} comments
              </div>
            )}
          </div>
        )}

        <div className="flex gap-3">
          <input
            type="text"
            value={modelPath}
            onChange={(e) => setModelPath(e.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                event.preventDefault()
                handleLoadModel()
              }
            }}
            placeholder="Path to model (.pkl file)..."
            className="input flex-1"
            disabled={isLoadingModel}
          />
          <button
            onClick={handleBrowseModel}
            disabled={isLoadingModel}
            className="btn btn-secondary flex items-center gap-2"
          >
            <FolderOpen className="w-4 h-4" />
            Browse
          </button>
          <button
            onClick={handleLoadModel}
            disabled={isServerDisconnected || isLoadingModel || !modelPath.trim()}
            className="btn btn-primary"
          >
            {isLoadingModel ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Load'}
          </button>
        </div>
      </div>

      {/* Appearance */}
      <div className="card mb-6">
        <div className="flex items-center gap-2 mb-4">
          {useThemeStore.getState().isDark ? (
            <Moon className="w-5 h-5 text-accent" />
          ) : (
            <Sun className="w-5 h-5 text-accent" />
          )}
          <h2 className="text-lg font-medium text-gray-900 dark:text-white">
            Appearance
          </h2>
        </div>

        <ThemeSelector />
      </div>

      {/* Feature Status */}
      <div className="card">
        <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-4">
          Feature Status
        </h2>
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <span className="text-sm text-gray-900 dark:text-gray-200">Vibe Generation</span>
            <span className={`text-xs px-2 py-0.5 rounded ${
              settings.vibeAvailable
                ? 'text-green-600 bg-green-50 dark:bg-green-900/20 dark:text-green-400'
                : 'text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-800'
            }`}>
              {settings.vibeStatus}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-sm text-gray-900 dark:text-gray-200">Hook Transcription</span>
            <span className={`text-xs px-2 py-0.5 rounded ${
              settings.hookAvailable
                ? 'text-green-600 bg-green-50 dark:bg-green-900/20 dark:text-green-400'
                : 'text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-800'
            }`}>
              {settings.hookStatus}
            </span>
          </div>
        </div>
      </div>

      <div className="mt-6 text-xs text-muted">
        Build: {buildLabel}
      </div>
    </div>
  )
}
