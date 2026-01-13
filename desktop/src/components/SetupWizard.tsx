import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Disc3, ChevronRight, ChevronLeft, FolderOpen, Check, Loader2, AlertCircle, Package, Wrench } from 'lucide-react'
import { clsx } from 'clsx'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'

type Step = 'welcome' | 'model' | 'preferences' | 'complete'

const ID3_FIELDS = [
  { value: 'genre', label: 'Genre' },
  { value: 'album', label: 'Timing' },
  { value: 'mood', label: 'Mood' },
  { value: 'artist', label: 'Artist' },
  { value: 'comments', label: 'Comments (Descriptive)' },
  { value: 'grouping', label: 'Grouping' },
  { value: 'composer', label: 'Composer' },
  { value: 'publisher', label: 'Publisher' },
]

const TAG_FIELD_INFO: Record<string, { title: string; description: string }> = {
  genre: {
    title: 'Genre Classification',
    description: 'Primary musical genre detected by the model (e.g., House, Hip-Hop, Rock)',
  },
  album: {
    title: 'Timing / Energy',
    description: 'Energy position for a set (e.g., Peak, Build, Sustain)',
  },
  mood: {
    title: 'Mood',
    description: 'Emotional tone classification (e.g., Dark, Uplifting, Chill)',
  },
  comments: {
    title: 'Descriptive Tags',
    description: "Additional descriptive tags about the track's characteristics",
  },
  likeness: {
    title: 'Artist Likeness',
    description: 'Similar artists and songs based on audio analysis',
  },
}

const stepVariants = {
  enter: (direction: number) => ({
    x: direction > 0 ? 300 : -300,
    opacity: 0,
  }),
  center: {
    x: 0,
    opacity: 1,
  },
  exit: (direction: number) => ({
    x: direction < 0 ? 300 : -300,
    opacity: 0,
  }),
}

export function SetupWizard() {
  const [step, setStep] = useState<Step>('welcome')
  const [direction, setDirection] = useState(0)
  const [isLoadingModel, setIsLoadingModel] = useState(false)
  const [modelError, setModelError] = useState<string | null>(null)
  const [selectedModelType, setSelectedModelType] = useState<'bundled' | 'custom' | null>(null)
  // Track if user manually loaded a custom model (to show success message)
  const [showCustomModelSuccess, setShowCustomModelSuccess] = useState(false)

  const {
    model,
    settings,
    serverStatus,
    loadModel,
    taggingPreferences,
    setTaggingPreferences,
    completeSetup
  } = useAppStore()
  const { dialog } = useElectron()

  // If model is already loaded (auto-loaded default), mark as bundled
  useEffect(() => {
    if (model.loaded && !selectedModelType) {
      setSelectedModelType('bundled')
    }
  }, [model.loaded, selectedModelType])

  const steps: Step[] = ['welcome', 'model', 'preferences', 'complete']
  const currentIndex = steps.indexOf(step)

  const goNext = () => {
    setDirection(1)
    setStep(steps[currentIndex + 1])
  }

  const goBack = () => {
    setDirection(-1)
    setStep(steps[currentIndex - 1])
  }

  const handleLoadCustomModel = async () => {
    const files = await dialog.openFiles({
      filters: [{ name: 'Model Files', extensions: ['pkl'] }],
    })
    if (files.length > 0) {
      setSelectedModelType('custom')
      setIsLoadingModel(true)
      setModelError(null)
      setShowCustomModelSuccess(false)
      try {
        await loadModel(files[0])
        setShowCustomModelSuccess(true)
      } catch (error) {
        setModelError(error instanceof Error ? error.message : 'Failed to load model')
      } finally {
        setIsLoadingModel(false)
      }
    }
  }

  const handleLoadBundledModel = async () => {
    setSelectedModelType('bundled')
    setIsLoadingModel(true)
    setModelError(null)
    setShowCustomModelSuccess(false)
    try {
      const bundledPath = 'bundled://cratebot-default'
      await loadModel(bundledPath)
    } catch (error) {
      setModelError(error instanceof Error ? error.message : 'Failed to load bundled model')
    } finally {
      setIsLoadingModel(false)
    }
  }

  const handleFinish = () => {
    completeSetup()
  }

  const updateFieldPref = (
    field: 'genre' | 'album' | 'mood' | 'comments' | 'likeness',
    key: 'enabled' | 'targetField',
    value: boolean | string
  ) => {
    setTaggingPreferences({
      [field]: {
        ...taggingPreferences[field],
        [key]: value,
      },
    })
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface-sunken dark:bg-surface-dark-sunken p-8">
      <div className="w-full max-w-xl">
        {/* Progress dots */}
        <div className="flex justify-center gap-2 mb-8">
          {steps.map((s, i) => (
            <div
              key={s}
              className={`w-2 h-2 rounded-full transition-colors ${
                i <= currentIndex
                  ? 'bg-amber-500'
                  : 'bg-stone-300 dark:bg-stone-600'
              }`}
            />
          ))}
        </div>

        {/* Step content */}
        <div className="card p-8 min-h-[400px] flex flex-col">
          <AnimatePresence mode="wait" custom={direction}>
            {step === 'welcome' && (
              <motion.div
                key="welcome"
                custom={direction}
                variants={stepVariants}
                initial="enter"
                animate="center"
                exit="exit"
                transition={{ duration: 0.3 }}
                className="flex-1 flex flex-col"
              >
                <div className="flex-1 flex flex-col items-center justify-center text-center">
                  <div className="w-20 h-20 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center mb-6">
                    <Disc3 className="w-10 h-10 text-amber-600 dark:text-amber-400" />
                  </div>
                  <h1 className="font-display text-3xl font-bold text-stone-900 dark:text-stone-100 mb-3">
                    Welcome to CrateBot
                  </h1>
                  <p className="text-stone-500 dark:text-stone-400 max-w-sm">
                    Auto-tag your music library with ML-powered classification:
                    Genre, Timing, Mood, and Descriptive tags.
                    Let's get you set up in just a few steps.
                  </p>
                </div>
                <div className="flex justify-end pt-6 border-t border-border-light dark:border-border-dark">
                  <button onClick={goNext} className="btn btn-primary">
                    Get Started
                    <ChevronRight className="w-4 h-4" />
                  </button>
                </div>
              </motion.div>
            )}

            {step === 'model' && (
              <motion.div
                key="model"
                custom={direction}
                variants={stepVariants}
                initial="enter"
                animate="center"
                exit="exit"
                transition={{ duration: 0.3 }}
                className="flex-1 flex flex-col"
              >
                <h2 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
                  Load a Model
                </h2>
                <p className="text-sm text-stone-500 dark:text-stone-400 mb-6">
                  Select a pre-trained model or load your own custom model.
                </p>

                <div className="flex-1 space-y-4">
                  {serverStatus !== 'connected' && (
                    <div className="p-3 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg">
                      <div className="flex items-center gap-2">
                        <AlertCircle className="w-4 h-4 text-amber-600 dark:text-amber-400" />
                        <span className="text-sm text-amber-800 dark:text-amber-200">
                          {serverStatus === 'connecting' ? 'Connecting to server...' : 'Server not connected. Model loading may fail.'}
                        </span>
                      </div>
                    </div>
                  )}

                  {/* Pre-trained Model Option */}
                  <button
                    onClick={handleLoadBundledModel}
                    disabled={isLoadingModel}
                    className={clsx(
                      'w-full p-4 rounded-xl border-2 text-left transition-all',
                      selectedModelType === 'bundled'
                        ? 'border-amber-500 bg-amber-50 dark:bg-amber-900/20'
                        : 'border-border-light dark:border-border-dark hover:border-amber-300 dark:hover:border-amber-700'
                    )}
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 rounded-lg bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center flex-shrink-0">
                        <Package className="w-5 h-5 text-amber-600 dark:text-amber-400" />
                      </div>
                      <div className="flex-1">
                        <div className="font-medium text-stone-900 dark:text-stone-100">
                          CrateBot Default Model
                        </div>
                        <p className="text-sm text-stone-500 dark:text-stone-400 mt-0.5">
                          Pre-trained for genre, mood, and style classification
                        </p>
                      </div>
                      {selectedModelType === 'bundled' && model.loaded && (
                        <Check className="w-5 h-5 text-amber-500" />
                      )}
                      {isLoadingModel && selectedModelType === 'bundled' && (
                        <Loader2 className="w-5 h-5 text-amber-500 animate-spin" />
                      )}
                    </div>
                  </button>

                  {/* Custom Model Option */}
                  <button
                    onClick={handleLoadCustomModel}
                    disabled={isLoadingModel}
                    className={clsx(
                      'w-full p-4 rounded-xl border-2 text-left transition-all',
                      selectedModelType === 'custom'
                        ? 'border-amber-500 bg-amber-50 dark:bg-amber-900/20'
                        : 'border-border-light dark:border-border-dark hover:border-stone-300 dark:hover:border-stone-600'
                    )}
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 rounded-lg bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
                        <FolderOpen className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                      </div>
                      <div className="flex-1">
                        <div className="font-medium text-stone-900 dark:text-stone-100">
                          Load Custom Model
                        </div>
                        <p className="text-sm text-stone-500 dark:text-stone-400 mt-0.5">
                          Select a .pkl model file from your computer
                        </p>
                      </div>
                      {selectedModelType === 'custom' && model.loaded && (
                        <Check className="w-5 h-5 text-amber-500" />
                      )}
                      {isLoadingModel && selectedModelType === 'custom' && (
                        <Loader2 className="w-5 h-5 text-amber-500 animate-spin" />
                      )}
                    </div>
                  </button>

                  {/* Divider */}
                  <div className="flex items-center gap-3 my-2">
                    <div className="flex-1 h-px bg-border-light dark:bg-border-dark" />
                    <span className="text-xs text-stone-400 dark:text-stone-500">or</span>
                    <div className="flex-1 h-px bg-border-light dark:bg-border-dark" />
                  </div>

                  {/* Train Custom Model Option */}
                  <button
                    onClick={() => completeSetup('train')}
                    disabled={isLoadingModel}
                    className="w-full p-4 rounded-xl border-2 border-dashed border-border-light dark:border-border-dark hover:border-stone-300 dark:hover:border-stone-600 text-left transition-all"
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 rounded-lg bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
                        <Wrench className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                      </div>
                      <div className="flex-1">
                        <div className="font-medium text-stone-900 dark:text-stone-100">
                          Train Custom Model
                        </div>
                        <p className="text-sm text-stone-500 dark:text-stone-400 mt-0.5">
                          Skip model loading and train your own model first
                        </p>
                      </div>
                    </div>
                  </button>

                  {modelError && (
                    <p className="text-sm text-red-600 dark:text-red-400">{modelError}</p>
                  )}

                  {/* Only show success message for custom model loads */}
                  {showCustomModelSuccess && model.loaded && (
                    <div className="p-4 bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800 rounded-lg">
                      <div className="flex items-center gap-2 mb-2">
                        <Check className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
                        <span className="font-medium text-emerald-800 dark:text-emerald-200">
                          {model.name || 'Model'} loaded successfully
                        </span>
                      </div>
                      {model.selectedTags && (
                        <p className="text-sm text-emerald-700 dark:text-emerald-300">
                          {model.selectedTags.genre.length} genres, {model.selectedTags.timing.length} timing, {model.selectedTags.mood.length} moods, {model.selectedTags.descriptive.length} comments
                        </p>
                      )}
                    </div>
                  )}
                </div>

                <div className="flex justify-between pt-6">
                  <button onClick={goBack} className="btn btn-secondary">
                    <ChevronLeft className="w-4 h-4" />
                    Back
                  </button>
                  <button
                    onClick={goNext}
                    disabled={!model.loaded}
                    className="btn btn-primary"
                  >
                    Continue
                    <ChevronRight className="w-4 h-4" />
                  </button>
                </div>
              </motion.div>
            )}

            {step === 'preferences' && (
              <motion.div
                key="preferences"
                custom={direction}
                variants={stepVariants}
                initial="enter"
                animate="center"
                exit="exit"
                transition={{ duration: 0.3 }}
                className="flex-1 flex flex-col"
              >
                <h2 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
                  Tagging Preferences
                </h2>
                <p className="text-sm text-stone-500 dark:text-stone-400 mb-6">
                  Choose which tags to write and where to store them in your MP3 files.
                </p>

                <div className="flex-1 space-y-4 overflow-auto">
                  {/* Tag Field Mappings */}
                  {(['genre', 'album', 'mood', 'comments', 'likeness'] as const).map((key) => {
                    const info = TAG_FIELD_INFO[key]
                    const pref = taggingPreferences[key]
                    return (
                      <div key={key} className="p-4 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
                        <div className="flex items-start gap-3">
                          <input
                            type="checkbox"
                            checked={pref.enabled}
                            onChange={(e) => updateFieldPref(key, 'enabled', e.target.checked)}
                            className="checkbox mt-1"
                          />
                          <div className="flex-1 min-w-0">
                            <div className="font-medium text-stone-900 dark:text-stone-100">
                              {info.title}
                            </div>
                            <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5 mb-3">
                              {info.description}
                            </p>
                            {pref.enabled && (
                              <div className="flex items-center gap-2">
                                <span className="text-xs text-stone-500">Write to:</span>
                                <select
                                  value={pref.targetField}
                                  onChange={(e) => updateFieldPref(key, 'targetField', e.target.value)}
                                  className="select text-sm py-1.5"
                                >
                                  {ID3_FIELDS.map((field) => (
                                    <option key={field.value} value={field.value}>
                                      {field.label}
                                    </option>
                                  ))}
                                </select>
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    )
                  })}

                  {/* AI Features */}
                  <div className="pt-4 border-t border-border-light dark:border-border-dark">
                    <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">AI Features</h3>
                    <div className="space-y-3">
                      <label className={clsx('flex items-center gap-3 p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken', !settings.vibeAvailable && 'opacity-50')}>
                        <input
                          type="checkbox"
                          checked={taggingPreferences.vibes.enabled}
                          onChange={(e) => setTaggingPreferences({ vibes: { ...taggingPreferences.vibes, enabled: e.target.checked } })}
                          disabled={!settings.vibeAvailable}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Generate Vibes</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">
                            {settings.vibeAvailable ? 'AI-generated descriptive text' : 'Requires API key'}
                          </p>
                        </div>
                      </label>
                      <label className={clsx('flex items-center gap-3 p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken', !settings.hookAvailable && 'opacity-50')}>
                        <input
                          type="checkbox"
                          checked={taggingPreferences.hooks.enabled}
                          onChange={(e) => setTaggingPreferences({ hooks: { ...taggingPreferences.hooks, enabled: e.target.checked } })}
                          disabled={!settings.hookAvailable}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Detect Hooks</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">
                            {settings.hookAvailable ? 'Transcribe vocal hooks' : settings.hookStatus}
                          </p>
                        </div>
                      </label>
                    </div>
                  </div>

                  {/* Behavior */}
                  <label className="flex items-center gap-3 p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.overwrite}
                      onChange={(e) => setTaggingPreferences({ overwrite: e.target.checked })}
                      className="checkbox"
                    />
                    <div>
                      <span className="text-sm text-stone-800 dark:text-stone-200">Overwrite existing tags</span>
                      <p className="text-xs text-stone-500 dark:text-stone-400">Replace tags that already have values</p>
                    </div>
                  </label>
                </div>

                <div className="flex justify-between pt-6 border-t border-border-light dark:border-border-dark">
                  <button onClick={goBack} className="btn btn-secondary">
                    <ChevronLeft className="w-4 h-4" />
                    Back
                  </button>
                  <button onClick={goNext} className="btn btn-primary">
                    Continue
                    <ChevronRight className="w-4 h-4" />
                  </button>
                </div>
              </motion.div>
            )}

            {step === 'complete' && (
              <motion.div
                key="complete"
                custom={direction}
                variants={stepVariants}
                initial="enter"
                animate="center"
                exit="exit"
                transition={{ duration: 0.3 }}
                className="flex-1 flex flex-col"
              >
                <div className="flex-1 flex flex-col items-center justify-center text-center">
                  <div className="w-20 h-20 rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center mb-6">
                    <Check className="w-10 h-10 text-emerald-600 dark:text-emerald-400" />
                  </div>
                  <h2 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-3">
                    All Set!
                  </h2>
                  <p className="text-stone-500 dark:text-stone-400 max-w-sm mb-6">
                    Drop files into CrateBot anytime to tag them. Your preferences are saved and can be changed in Settings.
                  </p>

                  {/* Summary */}
                  <div className="bg-surface-sunken dark:bg-surface-dark-sunken rounded-xl p-5 text-left w-full max-w-sm">
                    <div className="text-sm space-y-3">
                      {/* Model */}
                      <div className="flex justify-between items-center">
                        <span className="text-stone-500 dark:text-stone-400">Model:</span>
                        <span className="font-medium text-emerald-600 dark:text-emerald-400">
                          {model.name || 'CrateBot Default'}
                        </span>
                      </div>

                      {/* Tags - just list enabled ones, no mapping */}
                      <div className="flex justify-between items-center">
                        <span className="text-stone-500 dark:text-stone-400">Tags:</span>
                        <span className="font-medium text-emerald-600 dark:text-emerald-400">
                          {[
                            taggingPreferences.genre.enabled && 'Genre',
                            taggingPreferences.album.enabled && 'Timing',
                            taggingPreferences.mood.enabled && 'Mood',
                            taggingPreferences.comments.enabled && 'Comments (Descriptive)',
                            taggingPreferences.likeness.enabled && 'Likeness',
                          ].filter(Boolean).join(', ') || 'None'}
                        </span>
                      </div>

                      {/* AI Features - only show if any enabled, use & instead of comma */}
                      {(taggingPreferences.vibes.enabled || taggingPreferences.hooks.enabled) && (
                        <div className="flex justify-between items-center">
                          <span className="text-stone-500 dark:text-stone-400">AI Features:</span>
                          <span className="font-medium text-emerald-600 dark:text-emerald-400">
                            {[
                              taggingPreferences.vibes.enabled && 'Vibes',
                              taggingPreferences.hooks.enabled && 'Hooks',
                            ].filter(Boolean).join(' & ')}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                <div className="flex justify-between pt-6 border-t border-border-light dark:border-border-dark">
                  <button onClick={goBack} className="btn btn-secondary">
                    <ChevronLeft className="w-4 h-4" />
                    Back
                  </button>
                  <button onClick={handleFinish} className="btn btn-primary">
                    Start Tagging
                    <ChevronRight className="w-4 h-4" />
                  </button>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  )
}
