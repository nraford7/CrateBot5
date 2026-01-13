import { useState } from 'react'
import { X, Key, Disc3, Sun, Moon, Monitor, FolderOpen, Loader2, ChevronRight, GraduationCap, Sliders, RotateCcw } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { useThemeStore } from '../stores/themeStore'
import { useElectron } from '../hooks/useElectron'
import { api } from '../api/client'
import { LexiconEditor } from './settings/LexiconEditor'

type ThemeMode = 'light' | 'dark' | 'system'

interface SettingsPanelProps {
  isOpen: boolean
  onClose: () => void
  onOpenTrain: () => void
  onOpenRefine: () => void
}

const themeOptions: { value: ThemeMode; label: string; icon: typeof Sun }[] = [
  { value: 'light', label: 'Light', icon: Sun },
  { value: 'dark', label: 'Dark', icon: Moon },
  { value: 'system', label: 'System', icon: Monitor },
]

export function SettingsPanel({ isOpen, onClose, onOpenTrain, onOpenRefine }: SettingsPanelProps) {
  const {
    settings,
    model,
    loadModel,
    loadSettings,
    taggingPreferences,
    setTaggingPreferences,
    resetSetup,
    setToast,
    serverStatus,
  } = useAppStore()
  const { mode, setMode } = useThemeStore()
  const { dialog } = useElectron()

  const [apiKey, setApiKey] = useState('')
  const [isSavingKey, setIsSavingKey] = useState(false)
  const [isLoadingModel, setIsLoadingModel] = useState(false)

  const isServerDisconnected = serverStatus !== 'connected'

  const handleSaveApiKey = async () => {
    if (!apiKey.trim()) return
    setIsSavingKey(true)
    try {
      await api.setApiKey(apiKey)
      setApiKey('')
      await loadSettings()
      setToast('API key saved', 'success')
    } catch (error) {
      setToast('Failed to save API key', 'error')
    } finally {
      setIsSavingKey(false)
    }
  }

  const handleBrowseModel = async () => {
    const files = await dialog.openFiles({
      filters: [{ name: 'Model Files', extensions: ['pkl'] }],
    })
    if (files.length > 0) {
      setIsLoadingModel(true)
      try {
        await loadModel(files[0])
        setToast('Model loaded', 'success')
      } catch (error) {
        setToast('Failed to load model', 'error')
      } finally {
        setIsLoadingModel(false)
      }
    }
  }

  // Helper for updating nested preferences
  const updateFieldPref = (field: 'genre' | 'album' | 'mood' | 'comments' | 'likeness', enabled: boolean) => {
    setTaggingPreferences({
      [field]: { ...taggingPreferences[field], enabled },
    })
  }

  const updateFeaturePref = (field: 'vibes' | 'hooks', enabled: boolean) => {
    if (field === 'vibes') {
      setTaggingPreferences({ vibes: { ...taggingPreferences.vibes, enabled } })
    } else {
      setTaggingPreferences({ hooks: { ...taggingPreferences.hooks, enabled } })
    }
  }

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/30 z-40"
            onClick={onClose}
          />

          {/* Panel */}
          <motion.div
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={{ type: 'spring', damping: 30, stiffness: 300 }}
            className="fixed right-0 top-0 bottom-0 w-96 bg-surface-light dark:bg-surface-dark border-l border-border-light dark:border-border-dark z-50 flex flex-col"
          >
            {/* Header */}
            <div className="h-14 flex items-center justify-between px-4 border-b border-border-light dark:border-border-dark">
              <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">Settings</h2>
              <button
                onClick={onClose}
                className="p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Content */}
            <div className="flex-1 overflow-auto p-4 space-y-6">
              {/* Tagging Preferences */}
              <section>
                <h3 className="text-sm font-medium text-stone-500 dark:text-stone-400 uppercase tracking-wider mb-3">
                  Tagging Preferences
                </h3>
                <div className="space-y-2">
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.genre.enabled}
                      onChange={(e) => updateFieldPref('genre', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Genre</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.album.enabled}
                      onChange={(e) => updateFieldPref('album', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Timing</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.mood.enabled}
                      onChange={(e) => updateFieldPref('mood', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Mood</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.comments.enabled}
                      onChange={(e) => updateFieldPref('comments', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Comments (Descriptive)</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.likeness.enabled}
                      onChange={(e) => updateFieldPref('likeness', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Likeness Scores</span>
                  </label>
                  <label className={`flex items-center gap-3 p-2 rounded-lg ${settings.vibeAvailable ? 'hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer' : 'opacity-50'}`}>
                    <input
                      type="checkbox"
                      checked={taggingPreferences.vibes.enabled}
                      onChange={(e) => updateFeaturePref('vibes', e.target.checked)}
                      disabled={!settings.vibeAvailable}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Generate Vibes</span>
                    {!settings.vibeAvailable && (
                      <span className="text-xs text-stone-400">(needs API key)</span>
                    )}
                  </label>
                  {taggingPreferences.vibes.enabled && settings.vibeAvailable && (
                    <div className="ml-8 space-y-2 text-sm">
                      <div className="flex items-center gap-2">
                        <span className="text-stone-500 w-20">Short:</span>
                        <select
                          value={taggingPreferences.vibes.shortTargetField}
                          onChange={(e) => setTaggingPreferences({
                            vibes: { ...taggingPreferences.vibes, shortTargetField: e.target.value }
                          })}
                          className="flex-1 px-2 py-1 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                        >
                          <option value="TXXX:CRATEBOT_VIBE_SHORT">TXXX:CRATEBOT_VIBE_SHORT</option>
                          <option value="TIT3">TIT3 (Subtitle)</option>
                          <option value="TIT1">TIT1 (Content Group)</option>
                          <option value="COMM">COMM (Comments)</option>
                        </select>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-stone-500 w-20">Long:</span>
                        <select
                          value={taggingPreferences.vibes.longTargetField}
                          onChange={(e) => setTaggingPreferences({
                            vibes: { ...taggingPreferences.vibes, longTargetField: e.target.value }
                          })}
                          className="flex-1 px-2 py-1 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                        >
                          <option value="COMM">COMM (Comments)</option>
                          <option value="TXXX:CRATEBOT_VIBE_LONG">TXXX:CRATEBOT_VIBE_LONG</option>
                          <option value="TIT1">TIT1 (Content Group)</option>
                          <option value="TDSC">TDSC (Description)</option>
                        </select>
                      </div>
                    </div>
                  )}
                  <label className={`flex items-center gap-3 p-2 rounded-lg ${settings.hookAvailable ? 'hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer' : 'opacity-50'}`}>
                    <input
                      type="checkbox"
                      checked={taggingPreferences.hooks.enabled}
                      onChange={(e) => updateFeaturePref('hooks', e.target.checked)}
                      disabled={!settings.hookAvailable}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Detect Hooks</span>
                    {!settings.hookAvailable && (
                      <span className="text-xs text-stone-400">({settings.hookStatus})</span>
                    )}
                  </label>
                  <div className="border-t border-border-light dark:border-border-dark my-2" />
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.overwrite}
                      onChange={(e) => setTaggingPreferences({ overwrite: e.target.checked })}
                      className="checkbox"
                    />
                    <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Overwrite existing tags</span>
                  </label>
                </div>
              </section>

              {/* Lexicon & Vocabulary */}
              <section>
                <h3 className="text-sm font-medium text-stone-500 dark:text-stone-400 uppercase tracking-wider mb-3">
                  Lexicon & Vocabulary
                </h3>
                <LexiconEditor />
              </section>

              {/* API Key */}
              <section>
                <h3 className="text-sm font-medium text-stone-500 dark:text-stone-400 uppercase tracking-wider mb-3">
                  Anthropic API Key
                </h3>
                <div className="flex items-center gap-2 mb-2">
                  <Key className="w-4 h-4 text-stone-400" />
                  <span className={`text-sm ${settings.anthropicApiKeySet ? 'text-emerald-600 dark:text-emerald-400' : 'text-stone-500'}`}>
                    {settings.anthropicApiKeySet ? 'API key is set' : 'Not configured'}
                  </span>
                </div>
                <div className="flex gap-2">
                  <input
                    type="password"
                    value={apiKey}
                    onChange={(e) => setApiKey(e.target.value)}
                    placeholder={settings.anthropicApiKeySet ? '••••••••' : 'sk-ant-...'}
                    className="input flex-1 text-sm"
                  />
                  <button
                    onClick={handleSaveApiKey}
                    disabled={isServerDisconnected || isSavingKey || !apiKey.trim()}
                    className="btn btn-primary btn-sm"
                  >
                    {isSavingKey ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Save'}
                  </button>
                </div>
                <p className="text-xs text-stone-400 mt-2">
                  Required for AI vibe generation. Get a key from console.anthropic.com
                </p>
              </section>

              {/* Model */}
              <section>
                <h3 className="text-sm font-medium text-stone-500 dark:text-stone-400 uppercase tracking-wider mb-3">
                  Model
                </h3>
                {model.loaded && (
                  <div className="flex items-center gap-2 mb-3 p-2 bg-surface-sunken dark:bg-surface-dark-sunken rounded-lg">
                    <Disc3 className="w-4 h-4 text-amber-500" />
                    <span className="text-sm font-medium text-stone-700 dark:text-stone-300">{model.name}</span>
                    {model.selectedTags && (
                      <span className="text-xs text-stone-400">
                        ({model.selectedTags.genre.length} genres)
                      </span>
                    )}
                  </div>
                )}
                <button
                  onClick={handleBrowseModel}
                  disabled={isLoadingModel}
                  className="btn btn-secondary btn-sm w-full"
                >
                  {isLoadingModel ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <FolderOpen className="w-4 h-4" />
                  )}
                  Load Different Model
                </button>
              </section>

              {/* Appearance */}
              <section>
                <h3 className="text-sm font-medium text-stone-500 dark:text-stone-400 uppercase tracking-wider mb-3">
                  Appearance
                </h3>
                <div className="flex gap-2">
                  {themeOptions.map((option) => {
                    const Icon = option.icon
                    const isSelected = mode === option.value
                    return (
                      <button
                        key={option.value}
                        onClick={() => setMode(option.value)}
                        className={`flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-lg border text-sm transition-colors ${
                          isSelected
                            ? 'border-amber-500 bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                            : 'border-border-light dark:border-border-dark text-stone-600 dark:text-stone-400 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken'
                        }`}
                      >
                        <Icon className="w-4 h-4" />
                        {option.label}
                      </button>
                    )
                  })}
                </div>
              </section>

              {/* Advanced */}
              <section>
                <h3 className="text-sm font-medium text-stone-500 dark:text-stone-400 uppercase tracking-wider mb-3">
                  Advanced
                </h3>
                <div className="space-y-2">
                  <button
                    onClick={() => {
                      onClose()
                      onOpenTrain()
                    }}
                    className="w-full flex items-center gap-3 p-3 rounded-lg border border-border-light dark:border-border-dark hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors text-left"
                  >
                    <GraduationCap className="w-5 h-5 text-stone-400" />
                    <div className="flex-1">
                      <div className="text-sm font-medium text-stone-700 dark:text-stone-300">Train Custom Model</div>
                      <div className="text-xs text-stone-400">Build a model from your tagged music</div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-stone-400" />
                  </button>

                  <button
                    onClick={() => {
                      onClose()
                      onOpenRefine()
                    }}
                    className="w-full flex items-center gap-3 p-3 rounded-lg border border-border-light dark:border-border-dark hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors text-left"
                  >
                    <Sliders className="w-5 h-5 text-stone-400" />
                    <div className="flex-1">
                      <div className="text-sm font-medium text-stone-700 dark:text-stone-300">Review & Refine Tags</div>
                      <div className="text-xs text-stone-400">Manually review and correct auto-tagged files</div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-stone-400" />
                  </button>

                  <button
                    onClick={() => {
                      if (confirm('This will show the setup wizard again on next launch. Continue?')) {
                        resetSetup()
                        setToast('Setup will run on next launch', 'success')
                      }
                    }}
                    className="w-full flex items-center gap-3 p-3 rounded-lg border border-border-light dark:border-border-dark hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors text-left"
                  >
                    <RotateCcw className="w-5 h-5 text-stone-400" />
                    <div className="flex-1">
                      <div className="text-sm font-medium text-stone-700 dark:text-stone-300">Reset Setup</div>
                      <div className="text-xs text-stone-400">Run the setup wizard again</div>
                    </div>
                  </button>
                </div>
              </section>
            </div>

            {/* Footer */}
            <div className="p-4 border-t border-border-light dark:border-border-dark">
              <div className="text-xs text-stone-400 text-center">
                CrateBot v3.1.0
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
