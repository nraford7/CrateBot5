# CrateBot3 UX Redesign: Setup-First Flow

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform CrateBot from a 4-tab workflow app into a streamlined setup-once, tag-always experience optimized for users with pre-trained models.

**Architecture:** Replace the current Train→Tag→Refine→Settings tab navigation with a two-phase UX: (1) First-run setup wizard that guides users through model loading and preferences, (2) Main tagging view that users land on for all subsequent sessions. Advanced features (Training, Refine) move into an expanded Settings panel.

**Tech Stack:** React, TypeScript, Zustand, Framer Motion, Tailwind CSS, Electron

---

## Context & Decisions

### Problem Statement

The current 4-tab interface assumes users will:
1. Train their own model
2. Tag files
3. Refine results
4. Configure settings

**Reality:** Most users will use a pre-trained model and primarily tag files. Training is rare, refining is occasional. The current UI over-serves power users while creating friction for typical users.

### Design Decisions Made

1. **Setup Wizard on First Run**
   - Detect first-run via localStorage/config
   - Guide user through: Welcome → Load Model → Configure Preferences → Done
   - Preferences include: which tags to write, vibe/hook toggles, overwrite behavior
   - Skip button available for users who want manual control

2. **Main View = Tagging**
   - After setup, app opens directly to tagging interface
   - Model info displayed prominently (name, tag counts)
   - Active preferences shown as summary (e.g., "Writing: Genre, Album • Vibes: On")
   - Large drop zone for files
   - Quick access to Settings via header button

3. **Settings Panel (Expanded)**
   - Preferences section (tag options, API key, theme)
   - Model section (load different model)
   - Advanced section:
     - Train Custom Model (opens TrainTab content)
     - Review/Refine Tags (opens RefineTab content)
   - Use slide-out panel or modal for Settings (not a tab)

4. **State Persistence**
   - `setupComplete: boolean` in localStorage
   - Tag preferences persisted in localStorage
   - Model path persisted (auto-load on startup)

### Information Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  App                                                        │
│  ├── SetupWizard (shown if !setupComplete)                  │
│  │   ├── WelcomeStep                                        │
│  │   ├── ModelStep (load pre-trained model)                 │
│  │   ├── PreferencesStep (configure tag options)            │
│  │   └── CompleteStep (summary + "Start Tagging")           │
│  │                                                          │
│  └── MainView (shown if setupComplete)                      │
│      ├── Header (logo, model info, settings button)         │
│      ├── TaggingView (drop zone, queue, controls)           │
│      └── SettingsPanel (slide-out)                          │
│          ├── Preferences                                    │
│          ├── Model                                          │
│          ├── Appearance                                     │
│          └── Advanced (Train, Refine)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Tasks

### Task 1: Add Setup State to Store

**Files:**
- Modify: `desktop/src/stores/appStore.ts`

**Step 1: Add setup state interface and initial values**

Add to the AppState interface after line 48:

```typescript
// Setup state
setupComplete: boolean
taggingPreferences: {
  writeGenre: boolean
  writeAlbum: boolean
  writeComments: boolean
  writeLikeness: boolean
  generateVibes: boolean
  detectHooks: boolean
  overwrite: boolean
}
```

Add to the initial state after line 72:

```typescript
setupComplete: localStorage.getItem('cratebot-setup-complete') === 'true',
taggingPreferences: JSON.parse(
  localStorage.getItem('cratebot-tagging-preferences') ||
  '{"writeGenre":true,"writeAlbum":true,"writeComments":true,"writeLikeness":true,"generateVibes":false,"detectHooks":false,"overwrite":true}'
),
```

**Step 2: Add actions for setup state**

Add after line 59 in the interface:

```typescript
completeSetup: () => void
resetSetup: () => void
setTaggingPreferences: (prefs: Partial<AppState['taggingPreferences']>) => void
```

Add implementations after line 159:

```typescript
completeSetup: () => {
  localStorage.setItem('cratebot-setup-complete', 'true')
  set({ setupComplete: true })
},

resetSetup: () => {
  localStorage.removeItem('cratebot-setup-complete')
  set({ setupComplete: false })
},

setTaggingPreferences: (prefs) => {
  const newPrefs = { ...get().taggingPreferences, ...prefs }
  localStorage.setItem('cratebot-tagging-preferences', JSON.stringify(newPrefs))
  set({ taggingPreferences: newPrefs })
},
```

**Step 3: Commit**

```bash
git add desktop/src/stores/appStore.ts
git commit -m "feat: add setup state and tagging preferences to store

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Create SetupWizard Component

**Files:**
- Create: `desktop/src/components/SetupWizard.tsx`

**Step 1: Create the SetupWizard component**

```typescript
import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Disc3, ChevronRight, ChevronLeft, FolderOpen, Check, Loader2 } from 'lucide-react'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'

type Step = 'welcome' | 'model' | 'preferences' | 'complete'

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
  const [modelPath, setModelPath] = useState('')
  const [isLoadingModel, setIsLoadingModel] = useState(false)
  const [modelError, setModelError] = useState<string | null>(null)

  const {
    model,
    settings,
    loadModel,
    taggingPreferences,
    setTaggingPreferences,
    completeSetup
  } = useAppStore()
  const { dialog } = useElectron()

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

  const handleBrowseModel = async () => {
    const files = await dialog.openFiles({
      filters: [{ name: 'Model Files', extensions: ['pkl'] }],
    })
    if (files.length > 0) {
      setModelPath(files[0])
      setIsLoadingModel(true)
      setModelError(null)
      try {
        await loadModel(files[0])
      } catch (error) {
        setModelError(error instanceof Error ? error.message : 'Failed to load model')
      } finally {
        setIsLoadingModel(false)
      }
    }
  }

  const handleFinish = () => {
    completeSetup()
  }

  const updatePref = (key: keyof typeof taggingPreferences, value: boolean) => {
    setTaggingPreferences({ [key]: value })
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
                    Auto-tag your music library with ML-powered genre, mood, and vibe detection.
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
                  Select a pre-trained model to use for tagging your music.
                </p>

                <div className="flex-1">
                  <div className="flex gap-3 mb-4">
                    <input
                      type="text"
                      value={modelPath}
                      placeholder="Select a model file..."
                      className="input flex-1"
                      readOnly
                    />
                    <button
                      onClick={handleBrowseModel}
                      disabled={isLoadingModel}
                      className="btn btn-secondary"
                    >
                      {isLoadingModel ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <FolderOpen className="w-4 h-4" />
                      )}
                      Browse
                    </button>
                  </div>

                  {modelError && (
                    <p className="text-sm text-red-600 dark:text-red-400 mb-4">{modelError}</p>
                  )}

                  {model.loaded && (
                    <div className="p-4 bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800 rounded-lg">
                      <div className="flex items-center gap-2 mb-2">
                        <Check className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
                        <span className="font-medium text-emerald-800 dark:text-emerald-200">
                          Model loaded successfully
                        </span>
                      </div>
                      {model.selectedTags && (
                        <p className="text-sm text-emerald-700 dark:text-emerald-300">
                          {model.selectedTags.genre.length} genres, {model.selectedTags.album.length} albums, {model.selectedTags.comments.length} comments
                        </p>
                      )}
                    </div>
                  )}
                </div>

                <div className="flex justify-between pt-6 border-t border-border-light dark:border-border-dark">
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
                  Choose which tags to write to your files. You can change these anytime.
                </p>

                <div className="flex-1 space-y-6">
                  {/* Core Tags */}
                  <div>
                    <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">Core Tags</h3>
                    <div className="space-y-3">
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.writeGenre}
                          onChange={(e) => updatePref('writeGenre', e.target.checked)}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Genre</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">Primary genre classification</p>
                        </div>
                      </label>
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.writeAlbum}
                          onChange={(e) => updatePref('writeAlbum', e.target.checked)}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Album (Mood)</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">Energy and mood classification</p>
                        </div>
                      </label>
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.writeComments}
                          onChange={(e) => updatePref('writeComments', e.target.checked)}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Comments</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">Additional descriptive tags</p>
                        </div>
                      </label>
                    </div>
                  </div>

                  {/* AI Features */}
                  <div>
                    <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">AI Features</h3>
                    <div className="space-y-3">
                      <label className={`flex items-center gap-3 ${!settings.vibeAvailable ? 'opacity-50' : 'cursor-pointer'}`}>
                        <input
                          type="checkbox"
                          checked={taggingPreferences.generateVibes}
                          onChange={(e) => updatePref('generateVibes', e.target.checked)}
                          disabled={!settings.vibeAvailable}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Generate Vibes</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">
                            {settings.vibeAvailable
                              ? 'AI-generated descriptive text for each track'
                              : `Requires API key (${settings.vibeStatus})`}
                          </p>
                        </div>
                      </label>
                      <label className={`flex items-center gap-3 ${!settings.hookAvailable ? 'opacity-50' : 'cursor-pointer'}`}>
                        <input
                          type="checkbox"
                          checked={taggingPreferences.detectHooks}
                          onChange={(e) => updatePref('detectHooks', e.target.checked)}
                          disabled={!settings.hookAvailable}
                          className="checkbox"
                        />
                        <div>
                          <span className="text-sm text-stone-800 dark:text-stone-200">Detect Hooks</span>
                          <p className="text-xs text-stone-500 dark:text-stone-400">
                            {settings.hookAvailable
                              ? 'Transcribe vocal hooks and catchphrases'
                              : `${settings.hookStatus}`}
                          </p>
                        </div>
                      </label>
                    </div>
                  </div>

                  {/* Behavior */}
                  <div>
                    <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">Behavior</h3>
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={taggingPreferences.overwrite}
                        onChange={(e) => updatePref('overwrite', e.target.checked)}
                        className="checkbox"
                      />
                      <div>
                        <span className="text-sm text-stone-800 dark:text-stone-200">Overwrite existing tags</span>
                        <p className="text-xs text-stone-500 dark:text-stone-400">Replace tags that already have values</p>
                      </div>
                    </label>
                  </div>
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
                    You're all set!
                  </h2>
                  <p className="text-stone-500 dark:text-stone-400 max-w-sm mb-6">
                    Drop files into CrateBot anytime to tag them. Your preferences are saved and can be changed in Settings.
                  </p>

                  {/* Summary */}
                  <div className="bg-surface-sunken dark:bg-surface-dark-sunken rounded-lg p-4 text-left w-full max-w-sm">
                    <div className="text-sm space-y-2">
                      <div className="flex justify-between">
                        <span className="text-stone-500 dark:text-stone-400">Model:</span>
                        <span className="font-medium text-stone-800 dark:text-stone-200">{model.name || 'Loaded'}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-stone-500 dark:text-stone-400">Writing:</span>
                        <span className="font-medium text-stone-800 dark:text-stone-200">
                          {[
                            taggingPreferences.writeGenre && 'Genre',
                            taggingPreferences.writeAlbum && 'Album',
                            taggingPreferences.writeComments && 'Comments',
                          ].filter(Boolean).join(', ') || 'None'}
                        </span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-stone-500 dark:text-stone-400">AI Features:</span>
                        <span className="font-medium text-stone-800 dark:text-stone-200">
                          {[
                            taggingPreferences.generateVibes && 'Vibes',
                            taggingPreferences.detectHooks && 'Hooks',
                          ].filter(Boolean).join(', ') || 'None'}
                        </span>
                      </div>
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
```

**Step 2: Commit**

```bash
git add desktop/src/components/SetupWizard.tsx
git commit -m "feat: add SetupWizard component for first-run experience

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Create MainHeader Component

**Files:**
- Create: `desktop/src/components/MainHeader.tsx`

**Step 1: Create header component with model info and settings button**

```typescript
import { Settings, Disc3 } from 'lucide-react'
import { motion } from 'framer-motion'
import { useAppStore } from '../stores/appStore'

interface MainHeaderProps {
  onOpenSettings: () => void
}

export function MainHeader({ onOpenSettings }: MainHeaderProps) {
  const { model, taggingPreferences, currentTask } = useAppStore()
  const isProcessing = !!currentTask

  // Build preferences summary
  const writingTags = [
    taggingPreferences.writeGenre && 'Genre',
    taggingPreferences.writeAlbum && 'Album',
    taggingPreferences.writeComments && 'Comments',
  ].filter(Boolean)

  const aiFeatures = [
    taggingPreferences.generateVibes && 'Vibes',
    taggingPreferences.detectHooks && 'Hooks',
  ].filter(Boolean)

  return (
    <header className="h-14 border-b border-border-light dark:border-border-dark bg-surface-light dark:bg-surface-dark flex items-center px-6 drag-region">
      {/* Logo */}
      <div className="flex items-center gap-2.5 no-drag">
        <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-amber-600 flex items-center justify-center">
          <motion.div
            animate={isProcessing ? { rotate: 360 } : { rotate: 0 }}
            transition={{
              duration: 3,
              repeat: isProcessing ? Infinity : 0,
              ease: 'linear',
            }}
          >
            <Disc3 className="w-4 h-4 text-white drop-shadow-sm" />
          </motion.div>
        </div>
        <span className="font-display font-semibold text-stone-900 dark:text-stone-100">
          Crate<span className="text-amber-500">Bot</span>
        </span>
      </div>

      {/* Model Info */}
      <div className="ml-8 flex items-center gap-4 no-drag">
        <div className="text-sm">
          <span className="text-stone-400 dark:text-stone-500">Model:</span>
          <span className="ml-2 font-medium text-stone-700 dark:text-stone-300">
            {model.name || 'Unknown'}
          </span>
          {model.selectedTags && (
            <span className="ml-2 text-xs text-stone-400 dark:text-stone-500">
              ({model.selectedTags.genre.length} genres)
            </span>
          )}
        </div>

        <div className="h-4 w-px bg-border-light dark:bg-border-dark" />

        <div className="text-sm text-stone-400 dark:text-stone-500">
          Writing: <span className="text-stone-600 dark:text-stone-400">{writingTags.join(', ') || 'None'}</span>
          {aiFeatures.length > 0 && (
            <>
              {' '}&bull;{' '}
              <span className="text-stone-600 dark:text-stone-400">{aiFeatures.join(', ')}</span>
            </>
          )}
        </div>
      </div>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Settings Button */}
      <button
        onClick={onOpenSettings}
        className="no-drag p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
      >
        <Settings className="w-5 h-5" />
      </button>
    </header>
  )
}
```

**Step 2: Commit**

```bash
git add desktop/src/components/MainHeader.tsx
git commit -m "feat: add MainHeader component with model info and settings access

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Create SettingsPanel Component

**Files:**
- Create: `desktop/src/components/SettingsPanel.tsx`

**Step 1: Create slide-out settings panel with all options**

```typescript
import { useState } from 'react'
import { X, Key, Disc3, Sun, Moon, Monitor, FolderOpen, Loader2, Check, ChevronRight, GraduationCap, Sliders, RotateCcw } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { useThemeStore } from '../stores/themeStore'
import { useElectron } from '../hooks/useElectron'
import { api } from '../api/client'

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
  const [modelPath, setModelPath] = useState('')
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
      setModelPath(files[0])
      setIsLoadingModel(true)
      try {
        await loadModel(files[0])
        setToast('Model loaded', 'success')
        setModelPath('')
      } catch (error) {
        setToast('Failed to load model', 'error')
      } finally {
        setIsLoadingModel(false)
      }
    }
  }

  const updatePref = (key: keyof typeof taggingPreferences, value: boolean) => {
    setTaggingPreferences({ [key]: value })
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
                      checked={taggingPreferences.writeGenre}
                      onChange={(e) => updatePref('writeGenre', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Genre</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.writeAlbum}
                      onChange={(e) => updatePref('writeAlbum', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Album (Mood)</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.writeComments}
                      onChange={(e) => updatePref('writeComments', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Comments</span>
                  </label>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.writeLikeness}
                      onChange={(e) => updatePref('writeLikeness', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Write Likeness Scores</span>
                  </label>
                  <label className={`flex items-center gap-3 p-2 rounded-lg ${settings.vibeAvailable ? 'hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer' : 'opacity-50'}`}>
                    <input
                      type="checkbox"
                      checked={taggingPreferences.generateVibes}
                      onChange={(e) => updatePref('generateVibes', e.target.checked)}
                      disabled={!settings.vibeAvailable}
                      className="checkbox"
                    />
                    <span className="text-sm text-stone-700 dark:text-stone-300">Generate Vibes</span>
                    {!settings.vibeAvailable && (
                      <span className="text-xs text-stone-400">(needs API key)</span>
                    )}
                  </label>
                  <label className={`flex items-center gap-3 p-2 rounded-lg ${settings.hookAvailable ? 'hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer' : 'opacity-50'}`}>
                    <input
                      type="checkbox"
                      checked={taggingPreferences.detectHooks}
                      onChange={(e) => updatePref('detectHooks', e.target.checked)}
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
                      onChange={(e) => updatePref('overwrite', e.target.checked)}
                      className="checkbox"
                    />
                    <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Overwrite existing tags</span>
                  </label>
                </div>
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
                CrateBot v3.0.0
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
```

**Step 2: Commit**

```bash
git add desktop/src/components/SettingsPanel.tsx
git commit -m "feat: add SettingsPanel slide-out with preferences, model, and advanced options

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Create TaggingView Component

**Files:**
- Create: `desktop/src/components/TaggingView.tsx`

**Step 1: Create streamlined tagging view component**

This is a simplified version of TagTab that uses the store preferences directly.

```typescript
import { FilePlus, Play, Square, Pause, AlertCircle, FolderPlus } from 'lucide-react'
import { motion } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'
import { useTagging } from '../hooks/useTagging'
import { FileQueue } from './FileQueue'
import { DropZone } from './DropZone'

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

export function TaggingView() {
  const { serverStatus, model, taggingPreferences } = useAppStore()
  const { dialog } = useElectron()

  const {
    files,
    isProcessing,
    isPaused,
    currentIndex,
    error,
    startTime,
    addFiles,
    removeFile,
    clearFiles,
    startTagging,
    stopTagging,
    pauseTagging,
    resumeTagging,
    retryFile,
    loadFromDirectory,
  } = useTagging()

  const handleSelectFiles = async () => {
    const selectedFiles = await dialog.openFiles({
      filters: [{ name: 'MP3 Files', extensions: ['mp3'] }],
    })
    if (selectedFiles.length === 0) {
      const directory = await dialog.openDirectory()
      if (directory) {
        await loadFromDirectory(directory)
      }
      return
    }

    const filePaths = selectedFiles.filter((path) => path.toLowerCase().endsWith('.mp3'))
    const dirPaths = selectedFiles.filter((path) => !path.toLowerCase().endsWith('.mp3'))

    if (filePaths.length > 0) {
      addFiles(filePaths)
    }
    for (const dirPath of dirPaths) {
      await loadFromDirectory(dirPath)
    }
  }

  const handleSelectDirectory = async () => {
    const directory = await dialog.openDirectory()
    if (directory) {
      await loadFromDirectory(directory)
    }
  }

  const handleStartTagging = () => {
    // Use preferences from store
    startTagging({
      writeGenre: taggingPreferences.writeGenre,
      writeAlbum: taggingPreferences.writeAlbum,
      writeComments: taggingPreferences.writeComments,
      writeLikeness: taggingPreferences.writeLikeness,
      generateVibes: taggingPreferences.generateVibes,
      detectHooks: taggingPreferences.detectHooks,
      overwrite: taggingPreferences.overwrite,
    })
  }

  const handleRetryFile = (path: string) => {
    retryFile(path, {
      writeGenre: taggingPreferences.writeGenre,
      writeAlbum: taggingPreferences.writeAlbum,
      writeComments: taggingPreferences.writeComments,
      writeLikeness: taggingPreferences.writeLikeness,
      generateVibes: taggingPreferences.generateVibes,
      detectHooks: taggingPreferences.detectHooks,
      overwrite: taggingPreferences.overwrite,
    })
  }

  const isServerDisconnected = serverStatus !== 'connected'
  const canStart = !isServerDisconnected && model.loaded && files.length > 0 && !isProcessing

  const pendingCount = files.filter((f) => f.status === 'pending').length
  const taggedCount = files.filter((f) => f.status === 'tagged').length
  const failedCount = files.filter((f) => f.status === 'failed').length

  return (
    <DropZone onDrop={addFiles} disabled={isProcessing}>
      <motion.div
        variants={containerVariants}
        initial="hidden"
        animate="visible"
        className="p-8 h-full flex flex-col max-w-4xl mx-auto w-full"
      >
        {/* Drop Zone / Add Files Area */}
        {files.length === 0 ? (
          <motion.div
            variants={itemVariants}
            className="flex-1 flex flex-col items-center justify-center"
          >
            <div className="text-center mb-8">
              <h2 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
                Drop files to tag
              </h2>
              <p className="text-stone-500 dark:text-stone-400">
                Drag MP3 files or folders here, or use the buttons below
              </p>
            </div>

            <div className="flex gap-3">
              <button onClick={handleSelectFiles} className="btn btn-primary">
                <FilePlus className="w-4 h-4" />
                Add Files
              </button>
              <button onClick={handleSelectDirectory} className="btn btn-secondary">
                <FolderPlus className="w-4 h-4" />
                Add Folder
              </button>
            </div>
          </motion.div>
        ) : (
          <>
            {/* File Actions */}
            <motion.div variants={itemVariants} className="flex gap-3 mb-4">
              <button
                onClick={handleSelectFiles}
                disabled={isProcessing}
                className="btn btn-secondary"
              >
                <FilePlus className="w-4 h-4" />
                Add More
              </button>
              <button
                onClick={handleSelectDirectory}
                disabled={isProcessing}
                className="btn btn-secondary"
              >
                <FolderPlus className="w-4 h-4" />
                Add Folder
              </button>
            </motion.div>

            {/* File Queue */}
            <motion.div variants={itemVariants} className="flex-1 min-h-0">
              <FileQueue
                files={files}
                onRemove={isProcessing ? undefined : removeFile}
                onClear={isProcessing ? undefined : clearFiles}
                onRetry={isProcessing ? undefined : handleRetryFile}
                currentIndex={currentIndex}
                isProcessing={isProcessing}
                isPaused={isPaused}
                startTime={startTime}
              />
            </motion.div>

            {/* Error Message */}
            {error && (
              <motion.div
                variants={itemVariants}
                className="mt-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg flex items-start gap-2"
              >
                <AlertCircle className="w-4 h-4 text-red-500 flex-shrink-0 mt-0.5" />
                <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
              </motion.div>
            )}

            {/* Completion Summary */}
            {!isProcessing && taggedCount > 0 && (
              <motion.div
                variants={itemVariants}
                className="mt-4 card bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800"
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-emerald-100 dark:bg-emerald-800 rounded-full flex items-center justify-center">
                    <span className="text-emerald-600 dark:text-emerald-300 font-bold">
                      {taggedCount}
                    </span>
                  </div>
                  <div>
                    <p className="font-medium text-emerald-800 dark:text-emerald-200">
                      Files tagged successfully
                    </p>
                    {failedCount > 0 && (
                      <p className="text-sm text-emerald-700 dark:text-emerald-300">
                        {failedCount} failed - click to retry
                      </p>
                    )}
                  </div>
                </div>
              </motion.div>
            )}

            {/* Start/Control Buttons */}
            <motion.div
              variants={itemVariants}
              className="mt-6 pt-4 border-t border-border-light dark:border-border-dark"
            >
              {isProcessing ? (
                <div className="flex gap-3">
                  <button
                    onClick={isPaused ? resumeTagging : pauseTagging}
                    className="btn btn-secondary"
                  >
                    {isPaused ? (
                      <>
                        <Play className="w-4 h-4" />
                        Resume
                      </>
                    ) : (
                      <>
                        <Pause className="w-4 h-4" />
                        Pause
                      </>
                    )}
                  </button>
                  <button onClick={stopTagging} className="btn btn-secondary">
                    <Square className="w-4 h-4" />
                    Stop
                  </button>
                </div>
              ) : (
                <button
                  onClick={handleStartTagging}
                  disabled={!canStart}
                  className="btn btn-primary"
                >
                  <Play className="w-4 h-4" />
                  Start Tagging ({pendingCount} files)
                </button>
              )}
            </motion.div>
          </>
        )}
      </motion.div>
    </DropZone>
  )
}
```

**Step 2: Commit**

```bash
git add desktop/src/components/TaggingView.tsx
git commit -m "feat: add TaggingView component using store preferences

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Update App.tsx with New Architecture

**Files:**
- Modify: `desktop/src/App.tsx`

**Step 1: Replace current App.tsx content**

```typescript
/**
 * CrateBot App - Redesigned with Setup-First Flow
 * Main application component with streamlined tagging experience
 */
import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from './stores/appStore'
import { SetupWizard } from './components/SetupWizard'
import { MainHeader } from './components/MainHeader'
import { TaggingView } from './components/TaggingView'
import { SettingsPanel } from './components/SettingsPanel'
import { TrainTab } from './components/TrainTab'
import { RefineTab } from './components/RefineTab'
import { StatusBar } from './components/StatusBar'
import { ToastHost } from './components/ToastHost'

type AdvancedView = 'none' | 'train' | 'refine'

function App() {
  const { setupComplete, checkServerStatus } = useAppStore()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [advancedView, setAdvancedView] = useState<AdvancedView>('none')

  useEffect(() => {
    // Check server status on mount
    checkServerStatus()

    // Poll server status every 5 seconds
    const interval = setInterval(checkServerStatus, 5000)
    return () => clearInterval(interval)
  }, [checkServerStatus])

  useEffect(() => {
    const loadingEl = document.getElementById('app-loading')
    if (!loadingEl) return
    loadingEl.classList.add('fade-out')
    const timer = window.setTimeout(() => {
      loadingEl.remove()
    }, 600)
    return () => window.clearTimeout(timer)
  }, [])

  // Show setup wizard if not complete
  if (!setupComplete) {
    return <SetupWizard />
  }

  // Main app view
  return (
    <div className="flex flex-col h-screen bg-surface-sunken dark:bg-surface-dark-sunken">
      {/* Header */}
      <MainHeader onOpenSettings={() => setSettingsOpen(true)} />

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden">
        <div className="flex-1 overflow-auto bg-surface-light dark:bg-surface-dark">
          <AnimatePresence mode="wait">
            {advancedView === 'none' && (
              <motion.div
                key="tagging"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="h-full"
              >
                <TaggingView />
              </motion.div>
            )}
            {advancedView === 'train' && (
              <motion.div
                key="train"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="h-full"
              >
                <div className="p-4">
                  <button
                    onClick={() => setAdvancedView('none')}
                    className="btn btn-secondary mb-4"
                  >
                    ← Back to Tagging
                  </button>
                </div>
                <TrainTab />
              </motion.div>
            )}
            {advancedView === 'refine' && (
              <motion.div
                key="refine"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="h-full"
              >
                <div className="p-4">
                  <button
                    onClick={() => setAdvancedView('none')}
                    className="btn btn-secondary mb-4"
                  >
                    ← Back to Tagging
                  </button>
                </div>
                <RefineTab />
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Toasts */}
        <ToastHost />

        {/* Status Bar */}
        <StatusBar />
      </main>

      {/* Settings Panel */}
      <SettingsPanel
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onOpenTrain={() => setAdvancedView('train')}
        onOpenRefine={() => setAdvancedView('refine')}
      />
    </div>
  )
}

export default App
```

**Step 2: Commit**

```bash
git add desktop/src/App.tsx
git commit -m "feat: update App.tsx with setup-first flow architecture

- Shows SetupWizard for first-run users
- Main view is now tagging-focused
- Settings as slide-out panel
- Train/Refine accessible from settings as advanced options

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Clean Up Unused Components

**Files:**
- Delete or archive: `desktop/src/components/Sidebar.tsx`
- Delete or archive: `desktop/src/components/SettingsTab.tsx`

**Step 1: Remove old Sidebar (no longer needed)**

The Sidebar is replaced by the MainHeader and SettingsPanel.

```bash
# Option A: Delete
rm desktop/src/components/Sidebar.tsx
rm desktop/src/components/SettingsTab.tsx

# Option B: Archive (recommended for safety)
mkdir -p desktop/src/components/_archived
mv desktop/src/components/Sidebar.tsx desktop/src/components/_archived/
mv desktop/src/components/SettingsTab.tsx desktop/src/components/_archived/
```

**Step 2: Update any imports that reference removed components**

Search for imports of Sidebar or SettingsTab and remove them if present (App.tsx was already updated).

**Step 3: Commit**

```bash
git add -A desktop/src/components/
git commit -m "chore: archive old Sidebar and SettingsTab components

These are replaced by MainHeader and SettingsPanel in the new architecture.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 8: Update TabId Type Export

**Files:**
- Modify: `desktop/src/App.tsx` (already done in Task 6, but verify)

**Step 1: Verify TabId is removed or updated**

The old `TabId` type (`'train' | 'tag' | 'refine' | 'settings'`) was used by Sidebar. Since we've replaced the tab navigation, verify no other components depend on this export.

Search for `TabId` usage:
```bash
grep -r "TabId" desktop/src/
```

If found in other files, update or remove those references.

**Step 2: Commit if changes needed**

```bash
git add desktop/src/
git commit -m "chore: clean up TabId type references

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 9: Test the Complete Flow

**Step 1: Clear setup state to test first-run experience**

```bash
# In browser dev tools console (when app is running):
localStorage.removeItem('cratebot-setup-complete')
localStorage.removeItem('cratebot-tagging-preferences')
# Then refresh the app
```

**Step 2: Manual test checklist**

- [ ] App shows SetupWizard on first launch
- [ ] Can navigate through all wizard steps
- [ ] Model loads successfully in wizard
- [ ] Preferences persist after wizard completion
- [ ] After wizard, app shows TaggingView directly
- [ ] MainHeader displays correct model name and preferences
- [ ] Settings panel opens/closes correctly
- [ ] Preferences changes in Settings panel are reflected in header
- [ ] Can access Train from Settings → Advanced
- [ ] Can access Refine from Settings → Advanced
- [ ] Back button returns to TaggingView from Train/Refine
- [ ] Reset Setup shows wizard on next launch
- [ ] File drag-and-drop works in TaggingView
- [ ] Tagging uses preferences from store (not local state)

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during testing

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 10: Final Review and Documentation

**Step 1: Update any relevant documentation**

If there's a README or user guide, update it to reflect the new flow:

- First-run setup wizard
- Main tagging view
- Settings panel for preferences and advanced features

**Step 2: Final commit**

```bash
git add -A
git commit -m "docs: update documentation for new UX flow

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary of Changes

| Before | After |
|--------|-------|
| 4-tab navigation (Train, Tag, Refine, Settings) | Setup wizard + Main tagging view |
| Train tab as first screen | TaggingView as main screen |
| Settings as separate tab | Settings as slide-out panel |
| Tagging options configured per-session | Preferences persisted in store |
| No first-run guidance | SetupWizard guides new users |
| Train/Refine as primary features | Train/Refine as advanced options in Settings |

## Files Changed

**Created:**
- `desktop/src/components/SetupWizard.tsx`
- `desktop/src/components/MainHeader.tsx`
- `desktop/src/components/SettingsPanel.tsx`
- `desktop/src/components/TaggingView.tsx`

**Modified:**
- `desktop/src/stores/appStore.ts`
- `desktop/src/App.tsx`

**Archived/Removed:**
- `desktop/src/components/Sidebar.tsx`
- `desktop/src/components/SettingsTab.tsx`

**Kept as-is:**
- `desktop/src/components/TrainTab.tsx` (used in advanced settings)
- `desktop/src/components/RefineTab.tsx` (used in advanced settings)
- `desktop/src/components/TagTab.tsx` (can be removed after TaggingView is verified)
