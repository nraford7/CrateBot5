# UX Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Address user feedback from the latest build review covering splash screen, setup wizard, tagging page, and completion flow improvements.

**Architecture:** Modifications to existing React components (SetupWizard, TaggingView, MainHeader, StatusBar, FileQueue) plus one new component (CompletionDialog). State updates in appStore for ID3 field mappings. Design follows "Vinyl Warmth" theme from design system.

**Tech Stack:** React 18, TypeScript, Zustand, Framer Motion, Tailwind CSS, Lucide icons

---

## Task Overview

| # | Area | Task |
|---|------|------|
| 1 | Splash | Update loading screen to match style guide |
| 2 | Wizard | Add pre-trained model selection + external browse |
| 3 | Wizard | Add "train your own model later" helper text |
| 4 | Wizard | Show model name in success message |
| 5 | Wizard | Redesign preferences with ID3 field mapping |
| 6 | Wizard | Update completion screen with model name and status |
| 7 | Tagging | Add top spacer for macOS traffic lights |
| 8 | Tagging | Enhance file status display (Active/Completed/Pending) |
| 9 | StatusBar | Add time estimates to status bar |
| 10 | Completion | Add post-tagging dialog with review option |

---

## Task 1: Update Splash Screen

**Files:**
- Modify: `desktop/index.html:12-45`

**Step 1: Update the loading screen styles**

Replace the current `#app-loading` styles with the updated design:

```html
<style>
  #app-loading {
    position: fixed;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: linear-gradient(to bottom, #1a1918, #121110);
    color: #fafaf9;
    font-family: "DM Sans", system-ui, sans-serif;
    letter-spacing: 0.01em;
    transition: opacity 300ms ease;
  }
  #app-loading.fade-out {
    opacity: 0;
  }
  #app-loading .logo-container {
    width: 80px;
    height: 80px;
    border-radius: 20px;
    background: linear-gradient(135deg, #fbbf24, #d97706);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 24px;
    box-shadow: 0 0 40px rgba(245, 158, 11, 0.3);
  }
  #app-loading .logo-container svg {
    width: 40px;
    height: 40px;
    color: white;
    animation: spin 3s linear infinite;
  }
  #app-loading .brand {
    font-size: 28px;
    font-weight: 700;
    margin-bottom: 8px;
  }
  #app-loading .brand span {
    color: #f59e0b;
  }
  #app-loading .loading-text {
    font-size: 14px;
    font-weight: 500;
    color: #a8a29e;
    display: flex;
    align-items: center;
    gap: 12px;
  }
  #app-loading .spinner {
    width: 16px;
    height: 16px;
    border-radius: 999px;
    border: 2px solid rgba(245, 158, 11, 0.3);
    border-top-color: #f59e0b;
    animation: spin 0.9s linear infinite;
  }
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
```

**Step 2: Update the loading screen HTML**

Replace the body content with the new design:

```html
<div id="app-loading">
  <div class="logo-container">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="10"/>
      <circle cx="12" cy="12" r="3"/>
    </svg>
  </div>
  <div class="brand">Crate<span>Bot</span></div>
  <div class="loading-text">
    <div class="spinner"></div>
    Starting up...
  </div>
</div>
```

**Step 3: Verify changes**

Run: `cd desktop && npm run electron:dev`
Expected: See updated splash screen with logo, brand name, and "Starting up..." text

**Step 4: Commit**

```bash
git add desktop/index.html
git commit -m "$(cat <<'EOF'
style: update splash screen to match design system

Apply Vinyl Warmth theme with logo, brand text, and
improved loading indicator animation.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add Pre-trained Model Selection

**Files:**
- Modify: `desktop/src/components/SetupWizard.tsx:133-220`
- Modify: `desktop/src/stores/appStore.ts` (add bundled model path)

**Step 1: Add bundled model constants to appStore**

Add to the top of `appStore.ts`:

```typescript
// Bundled model info
export const BUNDLED_MODEL = {
  name: 'CrateBot Default',
  description: 'Pre-trained model for genre, mood, and style classification',
  // Path will be resolved at runtime based on platform
  getPath: () => {
    if (typeof window !== 'undefined' && window.electron) {
      return window.electron.getResourcePath('models/cratebot-default.pkl')
    }
    return null
  }
}
```

**Step 2: Update model step UI in SetupWizard**

Replace the model step content (lines ~133-220) with:

```tsx
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
        disabled={isLoadingModel || !serverStatus.includes('connect')}
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
          {selectedModelType === 'bundled' && (
            <Check className="w-5 h-5 text-amber-500" />
          )}
        </div>
      </button>

      {/* Custom Model Option */}
      <div
        className={clsx(
          'p-4 rounded-xl border-2 transition-all',
          selectedModelType === 'custom'
            ? 'border-amber-500 bg-amber-50 dark:bg-amber-900/20'
            : 'border-border-light dark:border-border-dark'
        )}
      >
        <div className="flex items-start gap-3">
          <div className="w-10 h-10 rounded-lg bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
            <FolderOpen className="w-5 h-5 text-stone-500 dark:text-stone-400" />
          </div>
          <div className="flex-1">
            <div className="font-medium text-stone-900 dark:text-stone-100 mb-2">
              Load Custom Model
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                value={modelPath}
                placeholder="Select a model file..."
                className="input flex-1 text-sm"
                readOnly
              />
              <button
                onClick={handleBrowseModel}
                disabled={isLoadingModel}
                className="btn btn-secondary"
              >
                {isLoadingModel && selectedModelType === 'custom' ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <FolderOpen className="w-4 h-4" />
                )}
                Browse
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Helper text */}
      <p className="text-xs text-stone-400 dark:text-stone-500 text-center mt-4">
        You can train your own model later once you get comfortable with CrateBot
      </p>

      {modelError && (
        <p className="text-sm text-red-600 dark:text-red-400">{modelError}</p>
      )}

      {model.loaded && (
        <div className="p-4 bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800 rounded-lg">
          <div className="flex items-center gap-2 mb-2">
            <Check className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
            <span className="font-medium text-emerald-800 dark:text-emerald-200">
              {model.name || 'Model'} loaded successfully
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
```

**Step 3: Add state and handlers**

Add to SetupWizard component (after existing state):

```tsx
const [selectedModelType, setSelectedModelType] = useState<'bundled' | 'custom' | null>(null)

const handleLoadBundledModel = async () => {
  setSelectedModelType('bundled')
  setIsLoadingModel(true)
  setModelError(null)
  try {
    // Get bundled model path from electron
    const bundledPath = await window.electron?.getResourcePath('models/cratebot-default.pkl')
    if (bundledPath) {
      await loadModel(bundledPath)
    } else {
      throw new Error('Bundled model not found')
    }
  } catch (error) {
    setModelError(error instanceof Error ? error.message : 'Failed to load bundled model')
  } finally {
    setIsLoadingModel(false)
  }
}

// Update existing handleBrowseModel
const handleBrowseModel = async () => {
  const files = await dialog.openFiles({
    filters: [{ name: 'Model Files', extensions: ['pkl'] }],
  })
  if (files.length > 0) {
    setSelectedModelType('custom')
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
```

**Step 4: Add Package icon import**

Add to imports at top of file:

```tsx
import { Disc3, ChevronRight, ChevronLeft, FolderOpen, Check, Loader2, AlertCircle, Package } from 'lucide-react'
import { clsx } from 'clsx'
```

**Step 5: Commit**

```bash
git add desktop/src/components/SetupWizard.tsx desktop/src/stores/appStore.ts
git commit -m "$(cat <<'EOF'
feat: add pre-trained model selection to setup wizard

- Add bundled model option with clear visual selection
- Keep external model browse option
- Add helper text about training custom models later
- Show model name in success message

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Redesign Preferences with ID3 Field Mapping

**Files:**
- Modify: `desktop/src/stores/appStore.ts` (add field mappings)
- Modify: `desktop/src/components/SetupWizard.tsx:223-366`

**Step 1: Update taggingPreferences type in appStore**

Replace the taggingPreferences interface:

```typescript
interface TagFieldMapping {
  enabled: boolean
  targetField: string // ID3 field name: 'genre', 'album', 'artist', 'comments', 'grouping', etc.
}

taggingPreferences: {
  genre: TagFieldMapping
  album: TagFieldMapping     // Mood data
  comments: TagFieldMapping  // Descriptive tags
  likeness: TagFieldMapping  // Artist similarity
  vibes: { enabled: boolean }
  hooks: { enabled: boolean }
  overwrite: boolean
}
```

**Step 2: Update DEFAULT_TAGGING_PREFERENCES**

```typescript
const DEFAULT_TAGGING_PREFERENCES: AppState['taggingPreferences'] = {
  genre: { enabled: true, targetField: 'genre' },
  album: { enabled: true, targetField: 'album' },
  comments: { enabled: true, targetField: 'comments' },
  likeness: { enabled: true, targetField: 'grouping' },
  vibes: { enabled: false },
  hooks: { enabled: false },
  overwrite: true,
}
```

**Step 3: Create ID3 field options constant**

Add to SetupWizard.tsx:

```typescript
const ID3_FIELDS = [
  { value: 'genre', label: 'Genre' },
  { value: 'album', label: 'Album' },
  { value: 'artist', label: 'Artist' },
  { value: 'comments', label: 'Comments' },
  { value: 'grouping', label: 'Grouping' },
  { value: 'composer', label: 'Composer' },
  { value: 'publisher', label: 'Publisher' },
]

const TAG_FIELD_INFO = {
  genre: {
    title: 'Genre Classification',
    description: 'Primary musical genre detected by the model (e.g., House, Hip-Hop, Rock)',
  },
  album: {
    title: 'Mood / Energy',
    description: 'Energy level and mood classification (e.g., Dark, Uplifting, Chill)',
  },
  comments: {
    title: 'Descriptive Tags',
    description: 'Additional descriptive tags about the track\'s characteristics',
  },
  likeness: {
    title: 'Artist Likeness',
    description: 'Similar artists and songs based on audio analysis',
  },
}
```

**Step 4: Replace preferences step UI**

```tsx
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
      {(['genre', 'album', 'comments', 'likeness'] as const).map((key) => {
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
              onChange={(e) => setTaggingPreferences({ vibes: { enabled: e.target.checked } })}
              disabled={!settings.vibeAvailable}
              className="checkbox"
            />
            <div>
              <span className="text-sm text-stone-800 dark:text-stone-200">Generate Vibes</span>
              <p className="text-xs text-stone-500 dark:text-stone-400">
                {settings.vibeAvailable ? 'AI-generated descriptive text' : `Requires API key`}
              </p>
            </div>
          </label>
          <label className={clsx('flex items-center gap-3 p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken', !settings.hookAvailable && 'opacity-50')}>
            <input
              type="checkbox"
              checked={taggingPreferences.hooks.enabled}
              onChange={(e) => setTaggingPreferences({ hooks: { enabled: e.target.checked } })}
              disabled={!settings.hookAvailable}
              className="checkbox"
            />
            <div>
              <span className="text-sm text-stone-800 dark:text-stone-200">Detect Hooks</span>
              <p className="text-xs text-stone-500 dark:text-stone-400">
                {settings.hookAvailable ? 'Transcribe vocal hooks' : `${settings.hookStatus}`}
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
```

**Step 5: Add updateFieldPref helper**

```typescript
const updateFieldPref = (
  field: 'genre' | 'album' | 'comments' | 'likeness',
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
```

**Step 6: Commit**

```bash
git add desktop/src/stores/appStore.ts desktop/src/components/SetupWizard.tsx
git commit -m "$(cat <<'EOF'
feat: add ID3 field mapping to tagging preferences

Allow users to map model output fields to any ID3 tag field.
Each tag type shows title, description, and target field selector.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Update Completion Screen

**Files:**
- Modify: `desktop/src/components/SetupWizard.tsx:369-432`

**Step 1: Replace completion step UI**

```tsx
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
            <span className="font-medium text-stone-800 dark:text-stone-200">
              {model.name || 'CrateBot Default'}
            </span>
          </div>

          {/* Tags Assigned */}
          <div className="flex justify-between items-start">
            <span className="text-stone-500 dark:text-stone-400">Tags Assigned:</span>
            <div className="text-right">
              <span className="badge badge-success">Successful</span>
              <p className="text-xs text-stone-600 dark:text-stone-400 mt-1">
                {[
                  taggingPreferences.genre.enabled && `Genre → ${taggingPreferences.genre.targetField}`,
                  taggingPreferences.album.enabled && `Mood → ${taggingPreferences.album.targetField}`,
                  taggingPreferences.comments.enabled && `Tags → ${taggingPreferences.comments.targetField}`,
                  taggingPreferences.likeness.enabled && `Likeness → ${taggingPreferences.likeness.targetField}`,
                ].filter(Boolean).join(', ') || 'None'}
              </p>
            </div>
          </div>

          {/* AI Features */}
          <div className="flex justify-between items-center">
            <span className="text-stone-500 dark:text-stone-400">AI Features Selected:</span>
            <span className="font-medium text-stone-800 dark:text-stone-200">
              {[
                taggingPreferences.vibes.enabled && 'Vibes',
                taggingPreferences.hooks.enabled && 'Hooks',
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
```

**Step 2: Commit**

```bash
git add desktop/src/components/SetupWizard.tsx
git commit -m "$(cat <<'EOF'
feat: update completion screen with model name and status

- Show loaded model name
- Change "Writing" to "Tags Assigned" with success badge
- Show field mappings in summary
- Display selected AI features

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add Top Spacer for macOS Traffic Lights

**Files:**
- Modify: `desktop/src/components/MainHeader.tsx:25-26`

**Step 1: Add traffic light spacer**

Update the header element to include platform-specific padding:

```tsx
return (
  <header className="h-14 border-b border-border-light dark:border-border-dark bg-surface-light dark:bg-surface-dark flex items-center drag-region">
    {/* Spacer for macOS traffic light buttons */}
    <div className="w-20 flex-shrink-0" />

    {/* Logo */}
    <div className="flex items-center gap-2.5 no-drag">
      {/* ... rest unchanged ... */}
```

Remove `px-6` from header and adjust spacing:

```tsx
<header className="h-14 border-b border-border-light dark:border-border-dark bg-surface-light dark:bg-surface-dark flex items-center pr-6 drag-region">
```

**Step 2: Commit**

```bash
git add desktop/src/components/MainHeader.tsx
git commit -m "$(cat <<'EOF'
fix: add spacer for macOS traffic light buttons

Prevent header content from overlapping with window
control buttons on macOS.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Enhance File Status Display

**Files:**
- Modify: `desktop/src/components/FileQueue.tsx:49-56`

**Step 1: Update statusConfig colors**

Update the statusConfig to use the correct colors per the requirements:

```typescript
const statusConfig: Record<FileStatus, { icon: typeof CheckCircle2; color: string; bgColor: string; label: string; labelColor: string }> = {
  pending: {
    icon: Clock,
    color: 'text-stone-400',
    bgColor: 'bg-stone-100 dark:bg-stone-800',
    label: 'Pending',
    labelColor: 'text-stone-400'
  },
  processing: {
    icon: Loader2,
    color: 'text-amber-500',
    bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    label: 'Processing',
    labelColor: 'text-amber-500'
  },
  tagged: {
    icon: CheckCircle2,
    color: 'text-emerald-500',
    bgColor: 'bg-emerald-100 dark:bg-emerald-900/30',
    label: 'Complete',
    labelColor: 'text-emerald-500'
  },
  failed: {
    icon: XCircle,
    color: 'text-red-500',
    bgColor: 'bg-red-100 dark:bg-red-900/30',
    label: 'Failed',
    labelColor: 'text-red-500'
  },
  skipped: {
    icon: AlertTriangle,
    color: 'text-amber-500',
    bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    label: 'Skipped',
    labelColor: 'text-amber-500'
  },
  review: {
    icon: AlertTriangle,
    color: 'text-violet-500',
    bgColor: 'bg-violet-100 dark:bg-violet-900/30',
    label: 'Review',
    labelColor: 'text-violet-500'
  },
}
```

**Step 2: Update status label rendering**

In the file row, update the status label to use labelColor:

```tsx
{/* Status Label */}
<span className={clsx('text-xs font-medium', config.labelColor)}>
  {config.label}
</span>
```

**Step 3: Commit**

```bash
git add desktop/src/components/FileQueue.tsx
git commit -m "$(cat <<'EOF'
style: enhance file status display colors

- Processing: yellow text
- Complete: green checkmark icon and green text
- Pending: grey clock icon and grey text

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add Time Estimates to Status Bar

**Files:**
- Modify: `desktop/src/components/StatusBar.tsx`
- Modify: `desktop/src/stores/appStore.ts` (add tagging stats)

**Step 1: Add tagging stats to appStore**

Add to AppState interface:

```typescript
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
```

Add action:

```typescript
setTaggingStats: (stats: AppState['taggingStats']) => void
clearTaggingStats: () => void
```

**Step 2: Update StatusBar to show time estimates**

Add to StatusBar component:

```tsx
export function StatusBar() {
  const { serverStatus, model, currentTask, taggingStats } = useAppStore()

  const formatTime = (seconds: number): string => {
    if (seconds < 60) return `${Math.round(seconds)}s`
    const mins = Math.floor(seconds / 60)
    const secs = Math.round(seconds % 60)
    return `${mins}m ${secs}s`
  }

  return (
    <footer className="statusbar justify-between">
      <div className="flex items-center gap-4">
        <ConnectionIndicator status={serverStatus} />
        <div className="divider-vertical" />
        <div className="statusbar-indicator">
          {model.loaded ? (
            <>
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" />
              <span className="text-xs text-stone-600 dark:text-stone-400">
                Model: <span className="font-medium">{model.name || 'Loaded'}</span>
              </span>
            </>
          ) : (
            <span className="text-xs text-stone-400 dark:text-stone-500">No model</span>
          )}
        </div>
      </div>

      <div className="flex items-center gap-4">
        {/* Tagging Stats */}
        {taggingStats && taggingStats.processing > 0 && (
          <div className="flex items-center gap-3 text-xs text-stone-500 dark:text-stone-400">
            <span>
              {taggingStats.completed}/{taggingStats.total} files
            </span>
            {taggingStats.avgTimePerFile > 0 && (
              <>
                <span className="divider-vertical" />
                <span>{taggingStats.avgTimePerFile.toFixed(1)}s/file</span>
              </>
            )}
            {taggingStats.eta > 0 && (
              <>
                <span className="divider-vertical" />
                <span>ETA: {formatTime(taggingStats.eta)}</span>
              </>
            )}
          </div>
        )}

        <AnimatePresence mode="wait">
          {currentTask && (
            <TaskProgress
              type={currentTask.type}
              progress={currentTask.progress}
              message={currentTask.message}
            />
          )}
        </AnimatePresence>
      </div>
    </footer>
  )
}
```

**Step 3: Update useTagging to set stats**

Add to useTagging hook where state changes:

```typescript
// After updating files, also update stats
const updateTaggingStats = useCallback(() => {
  const { setTaggingStats } = useAppStore.getState()
  const completed = state.files.filter(f => ['tagged', 'failed', 'skipped'].includes(f.status)).length
  const pending = state.files.filter(f => f.status === 'pending').length
  const processing = state.files.filter(f => f.status === 'processing').length

  const elapsed = state.startTime ? (Date.now() - state.startTime) / 1000 : 0
  const avgTime = completed > 0 ? elapsed / completed : 0
  const eta = avgTime * pending

  setTaggingStats({
    total: state.files.length,
    completed,
    pending,
    processing,
    failed: state.files.filter(f => f.status === 'failed').length,
    startTime: state.startTime,
    avgTimePerFile: avgTime,
    eta,
  })
}, [state.files, state.startTime])
```

**Step 4: Commit**

```bash
git add desktop/src/components/StatusBar.tsx desktop/src/stores/appStore.ts desktop/src/hooks/useTagging.ts
git commit -m "$(cat <<'EOF'
feat: add time estimates to status bar

Show files processed, time per file, and ETA during tagging.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Add Post-Tagging Completion Dialog

**Files:**
- Create: `desktop/src/components/CompletionDialog.tsx`
- Modify: `desktop/src/components/TaggingView.tsx`

**Step 1: Create CompletionDialog component**

```tsx
// desktop/src/components/CompletionDialog.tsx
import { motion, AnimatePresence } from 'framer-motion'
import { CheckCircle2, Edit3, X } from 'lucide-react'

interface CompletionDialogProps {
  isOpen: boolean
  onClose: () => void
  onReview: () => void
  taggedCount: number
  failedCount: number
}

export function CompletionDialog({
  isOpen,
  onClose,
  onReview,
  taggedCount,
  failedCount,
}: CompletionDialogProps) {
  if (!isOpen) return null

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="modal-backdrop"
            onClick={onClose}
          />

          {/* Dialog */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
          >
            <div className="modal w-full max-w-md p-6">
              {/* Close button */}
              <button
                onClick={onClose}
                className="absolute top-4 right-4 p-1.5 rounded-lg text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
              >
                <X className="w-5 h-5" />
              </button>

              {/* Content */}
              <div className="text-center">
                <div className="w-16 h-16 mx-auto rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center mb-4">
                  <CheckCircle2 className="w-8 h-8 text-emerald-600 dark:text-emerald-400" />
                </div>

                <h2 className="font-display text-xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
                  Tagging Complete!
                </h2>

                <p className="text-stone-500 dark:text-stone-400 mb-6">
                  {taggedCount} {taggedCount === 1 ? 'file' : 'files'} tagged successfully
                  {failedCount > 0 && `, ${failedCount} failed`}.
                </p>

                <p className="text-sm text-stone-600 dark:text-stone-400 mb-6">
                  Would you like to review what was written and make any changes?
                </p>

                {/* Actions */}
                <div className="flex gap-3">
                  <button
                    onClick={onClose}
                    className="btn btn-secondary flex-1"
                  >
                    Done
                  </button>
                  <button
                    onClick={onReview}
                    className="btn btn-primary flex-1"
                  >
                    <Edit3 className="w-4 h-4" />
                    Review Tags
                  </button>
                </div>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
```

**Step 2: Add CompletionDialog to TaggingView**

Import and add state:

```tsx
import { CompletionDialog } from './CompletionDialog'

// In TaggingView component:
const [showCompletionDialog, setShowCompletionDialog] = useState(false)

// Add effect to detect completion
useEffect(() => {
  if (!isProcessing && taggedCount > 0 && pendingCount === 0) {
    setShowCompletionDialog(true)
  }
}, [isProcessing, taggedCount, pendingCount])

// Add handlers
const handleReview = () => {
  setShowCompletionDialog(false)
  // Navigate to refine view - this will need App.tsx integration
  window.dispatchEvent(new CustomEvent('navigate-to-refine'))
}
```

**Step 3: Add dialog to render**

At the end of TaggingView return:

```tsx
{/* Completion Dialog */}
<CompletionDialog
  isOpen={showCompletionDialog}
  onClose={() => setShowCompletionDialog(false)}
  onReview={handleReview}
  taggedCount={taggedCount}
  failedCount={failedCount}
/>
```

**Step 4: Wire up navigation in App.tsx**

Add event listener:

```tsx
useEffect(() => {
  const handleNavigateToRefine = () => {
    setAdvancedView('refine')
    setSettingsOpen(false)
  }
  window.addEventListener('navigate-to-refine', handleNavigateToRefine)
  return () => window.removeEventListener('navigate-to-refine', handleNavigateToRefine)
}, [])
```

**Step 5: Commit**

```bash
git add desktop/src/components/CompletionDialog.tsx desktop/src/components/TaggingView.tsx desktop/src/App.tsx
git commit -m "$(cat <<'EOF'
feat: add post-tagging completion dialog

Show dialog when tagging completes asking if user wants to
review tags. "Done" dismisses, "Review Tags" navigates to
the refinement view.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Final Integration Test

**Step 1: Run the app**

```bash
cd desktop && npm run electron:dev
```

**Step 2: Test checklist**

- [ ] Splash screen shows updated design with logo and brand
- [ ] Setup wizard shows pre-trained model option
- [ ] Can select bundled model or browse for custom
- [ ] "Train your own model later" text appears
- [ ] Model success message shows model name
- [ ] Preferences show title/description for each tag field
- [ ] Can map tag fields to different ID3 fields
- [ ] Completion screen shows model name and "Tags Assigned: Successful"
- [ ] Tagging page has spacer for macOS traffic lights
- [ ] File statuses show correct colors (grey pending, yellow processing, green complete)
- [ ] Status bar shows time estimates during processing
- [ ] Completion dialog appears when tagging finishes
- [ ] "Review Tags" button navigates to refine view

**Step 3: Final commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: finalize UX improvements from build review

Complete implementation of all feedback items:
- Splash screen redesign
- Model selection with bundled option
- ID3 field mapping in preferences
- Enhanced completion screen
- macOS traffic light spacer
- Improved file status colors
- Status bar time estimates
- Post-tagging completion dialog

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

This plan addresses all user feedback items:

1. **Splash screen** - Updated to match Vinyl Warmth design with logo, brand, and improved animation
2. **Model selection** - Pre-trained model option plus external browse, helper text about training later
3. **Model success** - Shows specific model name that was loaded
4. **Preferences** - Flexible ID3 field mapping with title/description for each tag type
5. **Completion screen** - Shows model name, "Tags Assigned" with success status, AI features
6. **Traffic light spacer** - 80px spacer on left side of header
7. **File status colors** - Grey pending, yellow processing, green complete with appropriate icons
8. **Status bar** - Shows time per file and ETA during processing
9. **Completion dialog** - Asks user to review or dismiss after tagging finishes
