import { useState } from 'react'
import { Key, FolderOpen, Check, X, RefreshCw, Loader2, Sun, Moon, Monitor, Disc3 } from 'lucide-react'
import { motion } from 'framer-motion'
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

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.08, delayChildren: 0.1 },
  },
}

const itemVariants = {
  hidden: { opacity: 0, y: 15 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.4, ease: [0.4, 0, 0.2, 1] } },
}

function CardHeader({ icon: Icon, title, badge }: { icon: any; title: string; badge?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2.5 mb-4">
      <div className="w-8 h-8 rounded-lg bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
        <Icon className="w-4 h-4 text-amber-600 dark:text-amber-400" />
      </div>
      <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">
        {title}
      </h2>
      {badge}
    </div>
  )
}

function ThemeSelector() {
  const { mode, setMode } = useThemeStore()

  return (
    <div className="flex gap-2">
      {themeOptions.map((option) => {
        const Icon = option.icon
        const isSelected = mode === option.value
        return (
          <motion.button
            key={option.value}
            onClick={() => setMode(option.value)}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className={`flex-1 flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg border transition-all duration-200 ${
              isSelected
                ? 'border-amber-500 bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                : 'border-border-light dark:border-border-dark text-stone-600 dark:text-stone-400 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken'
            }`}
          >
            <Icon className="w-4 h-4" />
            <span className="text-sm font-medium">{option.label}</span>
          </motion.button>
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

  const handleSaveApiKey = async () => {
    if (!apiKey.trim()) return

    setIsSavingKey(true)
    try {
      await api.setApiKey(apiKey)
      setApiKey('')
      await loadSettings()
      setToast('API key saved', 'success')
    } catch (error) {
      console.error('Failed to save API key:', error)
      setToast('Failed to save API key', 'error')
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
      setToast('Failed to load model', 'error')
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
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="p-8 max-w-4xl w-full"
    >
      <motion.div variants={itemVariants} className="mb-8">
        <h1 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
          Settings
        </h1>
        <p className="text-sm text-stone-500 dark:text-stone-400">
          Configure API keys, models, and preferences.
        </p>
      </motion.div>

      {/* API Key */}
      <motion.div variants={itemVariants} className="card mb-6">
        <CardHeader
          icon={Key}
          title="Anthropic API Key"
          badge={
            settings.anthropicApiKeySet ? (
              <span className="badge badge-success">
                <Check className="w-3 h-3" /> Set
              </span>
            ) : (
              <span className="badge badge-warning">
                <X className="w-3 h-3" /> Not set
              </span>
            )
          }
        />

        <p className="text-sm text-stone-500 dark:text-stone-400 mb-4">
          Required for AI vibe generation. Get your key from{' '}
          <a href="https://console.anthropic.com" className="text-amber-600 dark:text-amber-400 hover:underline">
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
      </motion.div>

      {/* Model */}
      <motion.div variants={itemVariants} className="card mb-6">
        <CardHeader
          icon={Disc3}
          title="Model"
          badge={
            model.loaded ? (
              <span className="badge badge-success">
                <Check className="w-3 h-3" /> Loaded
              </span>
            ) : (
              <span className="badge badge-neutral">Not loaded</span>
            )
          }
        />

        {model.loaded && (
          <div className="mb-4 p-3 bg-surface-sunken dark:bg-surface-dark-sunken rounded-lg">
            <p className="text-sm">
              <span className="text-stone-500 dark:text-stone-400">Path:</span>{' '}
              <span className="font-mono text-xs">{model.path}</span>
            </p>
            {model.selectedTags && (
              <div className="mt-2 text-sm">
                <span className="text-stone-500 dark:text-stone-400">Tags:</span>{' '}
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
            className="btn btn-secondary"
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
      </motion.div>

      {/* Appearance */}
      <motion.div variants={itemVariants} className="card mb-6">
        <CardHeader
          icon={useThemeStore.getState().isDark ? Moon : Sun}
          title="Appearance"
        />
        <ThemeSelector />
      </motion.div>

      {/* Feature Status */}
      <motion.div variants={itemVariants} className="card">
        <CardHeader icon={RefreshCw} title="Feature Status" />
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <span className="text-sm text-stone-700 dark:text-stone-300">Vibe Generation</span>
            <span className={`badge ${
              settings.vibeAvailable ? 'badge-success' : 'badge-neutral'
            }`}>
              {settings.vibeStatus}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-sm text-stone-700 dark:text-stone-300">Hook Transcription</span>
            <span className={`badge ${
              settings.hookAvailable ? 'badge-success' : 'badge-neutral'
            }`}>
              {settings.hookStatus}
            </span>
          </div>
        </div>
      </motion.div>
    </motion.div>
  )
}
