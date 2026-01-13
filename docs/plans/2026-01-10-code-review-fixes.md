# Code Review Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix critical and important issues identified in the code review for the UI/UX polish features.

**Architecture:** Extract shared ID3 constants, update store defaults to use ID3 frame codes, extend TaggingOptions interface with targetField mappings, pass these mappings to the backend API, and clean up duplicate UI controls.

**Tech Stack:** React 18, TypeScript, Zustand, Framer Motion

---

## Task 1: Extract Shared ID3 Frame Constants

**Files:**
- Create: `desktop/src/constants/id3Frames.ts`
- Modify: `desktop/src/components/settings/LexiconEditor.tsx:19-109`
- Modify: `desktop/src/components/TaggingConfirmationDialog.tsx:19-35`

**Step 1: Create the shared constants file**

Create `desktop/src/constants/id3Frames.ts`:

```typescript
/**
 * Shared ID3 frame constants for consistent usage across the app.
 * Single source of truth for ID3v2.3/2.4 frames supported by iTunes/Apple Music.
 */

export interface ID3Frame {
  code: string
  name: string
  description: string
  group: string
}

export const ID3_FRAMES: ID3Frame[] = [
  // Primary Tags (most commonly used)
  { code: 'TCON', name: 'Genre', description: 'Content type / Genre', group: 'Primary' },
  { code: 'TALB', name: 'Album', description: 'Album/Movie/Show title', group: 'Primary' },
  { code: 'TIT1', name: 'Content Group', description: 'Content group description (Grouping in iTunes)', group: 'Primary' },
  { code: 'TIT2', name: 'Title', description: 'Title/Song name', group: 'Primary' },
  { code: 'TIT3', name: 'Subtitle', description: 'Subtitle/Description refinement', group: 'Primary' },
  { code: 'COMM', name: 'Comments', description: 'Comments field (multi-value)', group: 'Primary' },
  { code: 'TDSC', name: 'Description', description: 'iTunes Description field', group: 'Primary' },

  // Artist Tags
  { code: 'TPE1', name: 'Artist', description: 'Lead performer/Soloist', group: 'Artist' },
  { code: 'TPE2', name: 'Album Artist', description: 'Band/Orchestra/Accompaniment', group: 'Artist' },
  { code: 'TPE3', name: 'Conductor', description: 'Conductor/Performer refinement', group: 'Artist' },
  { code: 'TPE4', name: 'Remixer', description: 'Interpreted, remixed, or modified by', group: 'Artist' },
  { code: 'TCOM', name: 'Composer', description: 'Composer name', group: 'Artist' },
  { code: 'TEXT', name: 'Lyricist', description: 'Lyricist/Text writer', group: 'Artist' },

  // Sorting Tags (iTunes specific)
  { code: 'TSOT', name: 'Sort Title', description: 'Title sort order', group: 'Sorting' },
  { code: 'TSOA', name: 'Sort Album', description: 'Album sort order', group: 'Sorting' },
  { code: 'TSOP', name: 'Sort Artist', description: 'Performer sort order', group: 'Sorting' },
  { code: 'TSO2', name: 'Sort Album Artist', description: 'Album artist sort order', group: 'Sorting' },
  { code: 'TSOC', name: 'Sort Composer', description: 'Composer sort order', group: 'Sorting' },

  // Classification Tags
  { code: 'TCAT', name: 'Category', description: 'Category (podcast category in iTunes)', group: 'Classification' },
  { code: 'GRP1', name: 'Grouping', description: 'Grouping (iTunes grouping field)', group: 'Classification' },
  { code: 'MVNM', name: 'Movement Name', description: 'Movement name (classical)', group: 'Classification' },
  { code: 'MVIN', name: 'Movement Number', description: 'Movement number/count', group: 'Classification' },
  { code: 'TKEY', name: 'Key', description: 'Initial key (musical)', group: 'Classification' },
  { code: 'TBPM', name: 'Beats Per Minute', description: 'BPM tempo value', group: 'Classification' },
  { code: 'TLAN', name: 'Language', description: 'Language(s) of text/lyrics', group: 'Classification' },
  { code: 'TMOO', name: 'Mood', description: 'Mood (ID3v2.4)', group: 'Classification' },
  { code: 'TFLT', name: 'Kind', description: 'File type / Audio type', group: 'Classification' },
  { code: 'TMED', name: 'Media Type', description: 'Media type (CD, Vinyl, etc.)', group: 'Classification' },

  // Rating & Play Stats (iTunes)
  { code: 'POPM', name: 'Rating', description: 'Popularimeter / Star rating', group: 'Stats' },
  { code: 'PCNT', name: 'Plays', description: 'Play counter', group: 'Stats' },
  { code: 'TXXX:RATING', name: 'Rating (Text)', description: 'Text-based rating value', group: 'Stats' },
  { code: 'TXXX:PLAY_COUNT', name: 'Play Count', description: 'Number of plays', group: 'Stats' },
  { code: 'TXXX:SKIP_COUNT', name: 'Skips', description: 'Number of skips', group: 'Stats' },
  { code: 'TXXX:LAST_PLAYED', name: 'Last Played', description: 'Last played timestamp', group: 'Stats' },
  { code: 'TXXX:LAST_SKIPPED', name: 'Last Skipped', description: 'Last skipped timestamp', group: 'Stats' },

  // Publishing Tags
  { code: 'TPUB', name: 'Publisher', description: 'Publisher/Label', group: 'Publishing' },
  { code: 'TCOP', name: 'Copyright', description: 'Copyright message', group: 'Publishing' },
  { code: 'TENC', name: 'Encoded By', description: 'Encoded by', group: 'Publishing' },
  { code: 'TOWN', name: 'Owner', description: 'File owner/licensee', group: 'Publishing' },
  { code: 'WCOP', name: 'Copyright URL', description: 'Copyright/Legal URL', group: 'Publishing' },
  { code: 'WPUB', name: 'Publisher URL', description: 'Publisher official URL', group: 'Publishing' },

  // Date/Time Tags
  { code: 'TDRC', name: 'Recording Date', description: 'Recording time (ID3v2.4)', group: 'Date' },
  { code: 'TDRL', name: 'Release Date', description: 'Release time (ID3v2.4)', group: 'Date' },
  { code: 'TYER', name: 'Year', description: 'Year of recording (ID3v2.3)', group: 'Date' },
  { code: 'TDAT', name: 'Date', description: 'Date (DDMM format, ID3v2.3)', group: 'Date' },
  { code: 'TDEN', name: 'Date Added', description: 'Encoding time / Date added', group: 'Date' },
  { code: 'TDTG', name: 'Date Modified', description: 'Tagging time / Date modified', group: 'Date' },
  { code: 'TXXX:PURCHASE_DATE', name: 'Purchase Date', description: 'iTunes purchase date', group: 'Date' },

  // Track/Disc Tags
  { code: 'TRCK', name: 'Track Number', description: 'Track number/Position in set', group: 'Track' },
  { code: 'TPOS', name: 'Disc Number', description: 'Part of a set (disc number)', group: 'Track' },
  { code: 'TLEN', name: 'Length', description: 'Length in milliseconds', group: 'Track' },
  { code: 'TSIZ', name: 'Size', description: 'Size in bytes', group: 'Track' },
  { code: 'TXXX:SAMPLE_RATE', name: 'Sample Rate', description: 'Audio sample rate', group: 'Track' },

  // Album Metadata
  { code: 'TXXX:ALBUM_RATING', name: 'Album Rating', description: 'Album-level rating', group: 'Album' },
  { code: 'TXXX:FAVORITE', name: 'Favorite', description: 'Favorite/loved status', group: 'Album' },
  { code: 'TXXX:EQUALIZER', name: 'Equalizer', description: 'Equalizer preset name', group: 'Album' },

  // Cloud/Sync Tags (iTunes specific)
  { code: 'TXXX:CLOUD_STATUS', name: 'Cloud Status', description: 'iCloud sync status', group: 'Cloud' },
  { code: 'TXXX:CLOUD_DOWNLOAD', name: 'Cloud Download', description: 'iCloud download status', group: 'Cloud' },

  // Custom CrateBot Tags
  { code: 'TXXX:CRATEBOT_TIMING', name: 'CrateBot Timing', description: 'Custom timing tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_MOOD', name: 'CrateBot Mood', description: 'Custom mood tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_GENRE', name: 'CrateBot Genre', description: 'Custom genre tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_DESCRIPTIVE', name: 'CrateBot Descriptive', description: 'Custom descriptive tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_VIBE_SHORT', name: 'CrateBot Vibe (Short)', description: 'Short AI vibe description', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_VIBE_LONG', name: 'CrateBot Vibe (Long)', description: 'Long AI vibe description', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_HOOK', name: 'CrateBot Hook', description: 'Detected vocal hook transcription', group: 'Custom' },
  { code: 'TXXX:ENERGY', name: 'Energy', description: 'Energy level (DJ software)', group: 'Custom' },
]

export const FRAME_GROUPS = ['Primary', 'Classification', 'Artist', 'Sorting', 'Stats', 'Album', 'Publishing', 'Date', 'Track', 'Cloud', 'Custom']

/**
 * Common frames suitable for CrateBot tag assignment (subset of full list).
 * Used in confirmation dialog and settings dropdowns.
 */
export const TAGGING_TARGET_FRAMES = ID3_FRAMES.filter(f =>
  ['TCON', 'TALB', 'TIT1', 'TIT3', 'COMM', 'TDSC', 'GRP1', 'TMOO'].includes(f.code) ||
  f.code.startsWith('TXXX:CRATEBOT')
)

/**
 * Get frame options for select dropdowns.
 */
export function getFrameOptions() {
  return TAGGING_TARGET_FRAMES.map(f => ({
    value: f.code,
    label: `${f.code} (${f.name})`,
  }))
}
```

**Step 2: Verify the file was created**

Run: `cat desktop/src/constants/id3Frames.ts | head -20`
Expected: File contents visible

**Step 3: Update LexiconEditor to import from shared constants**

In `desktop/src/components/settings/LexiconEditor.tsx`, replace lines 15-109 (the ID3_FRAMES array and FRAME_GROUPS) with:

```typescript
import { ID3_FRAMES, FRAME_GROUPS } from '../../constants/id3Frames'
```

Remove the local `ID3_FRAMES` and `FRAME_GROUPS` definitions.

**Step 4: Update TaggingConfirmationDialog to use shared constants**

In `desktop/src/components/TaggingConfirmationDialog.tsx`, replace lines 18-35 (ID3_FRAME_OPTIONS) with:

```typescript
import { getFrameOptions } from '../constants/id3Frames'

const ID3_FRAME_OPTIONS = getFrameOptions()
```

**Step 5: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 6: Commit**

```bash
git add desktop/src/constants/id3Frames.ts desktop/src/components/settings/LexiconEditor.tsx desktop/src/components/TaggingConfirmationDialog.tsx
git commit -m "refactor: extract ID3 frame constants to shared file"
```

---

## Task 2: Update Store Defaults to Use ID3 Frame Codes

**Files:**
- Modify: `desktop/src/stores/appStore.ts:111-119`

**Step 1: Update DEFAULT_TAGGING_PREFERENCES**

In `desktop/src/stores/appStore.ts`, update lines 111-119 to use ID3 frame codes:

```typescript
const DEFAULT_TAGGING_PREFERENCES: AppState['taggingPreferences'] = {
  genre: { enabled: true, targetField: 'TCON' },
  album: { enabled: true, targetField: 'TALB' },
  comments: { enabled: true, targetField: 'COMM' },
  likeness: { enabled: true, targetField: 'TIT1' },
  vibes: { enabled: false, shortTargetField: 'TXXX:CRATEBOT_VIBE_SHORT', longTargetField: 'COMM' },
  hooks: { enabled: false, targetField: 'TXXX:CRATEBOT_HOOK' },
  overwrite: true,
}
```

**Step 2: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 3: Commit**

```bash
git add desktop/src/stores/appStore.ts
git commit -m "fix: use ID3 frame codes in default tagging preferences"
```

---

## Task 3: Extend TaggingOptions Interface with Target Fields

**Files:**
- Modify: `desktop/src/components/TaggingOptionsPanel.tsx:4-17`

**Step 1: Add targetField properties to TaggingOptions interface**

In `desktop/src/components/TaggingOptionsPanel.tsx`, update lines 4-17:

```typescript
export interface TaggingOptions {
  // ML Tags
  writeGenre: boolean
  genreTargetField: string
  writeAlbum: boolean
  albumTargetField: string
  writeComments: boolean
  commentsTargetField: string
  writeLikeness: boolean
  likenessTargetField: string

  // AI Features
  generateVibes: boolean
  vibesShortTargetField: string
  vibesLongTargetField: string
  detectHooks: boolean
  hooksTargetField: string

  // Other
  overwrite: boolean
}
```

**Step 2: Verify typecheck (will show errors - expected)**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck 2>&1 | head -30`
Expected: Errors about missing properties (we'll fix these in next tasks)

**Step 3: Commit interface change**

```bash
git add desktop/src/components/TaggingOptionsPanel.tsx
git commit -m "feat: extend TaggingOptions interface with targetField properties"
```

---

## Task 4: Update TaggingView to Pass Target Fields to API

**Files:**
- Modify: `desktop/src/components/TaggingView.tsx:77-99`

**Step 1: Update handleStartTagging to include target fields**

In `desktop/src/components/TaggingView.tsx`, update the `handleStartTagging` function (around line 77):

```typescript
  const handleStartTagging = () => {
    startTagging({
      writeGenre: taggingPreferences.genre.enabled,
      genreTargetField: taggingPreferences.genre.targetField,
      writeAlbum: taggingPreferences.album.enabled,
      albumTargetField: taggingPreferences.album.targetField,
      writeComments: taggingPreferences.comments.enabled,
      commentsTargetField: taggingPreferences.comments.targetField,
      writeLikeness: taggingPreferences.likeness.enabled,
      likenessTargetField: taggingPreferences.likeness.targetField,
      generateVibes: taggingPreferences.vibes.enabled,
      vibesShortTargetField: taggingPreferences.vibes.shortTargetField,
      vibesLongTargetField: taggingPreferences.vibes.longTargetField,
      detectHooks: taggingPreferences.hooks.enabled,
      hooksTargetField: taggingPreferences.hooks.targetField,
      overwrite: taggingPreferences.overwrite,
    })
  }
```

**Step 2: Update handleRetryFile similarly**

Update the `handleRetryFile` function (around line 90):

```typescript
  const handleRetryFile = (path: string) => {
    retryFile(path, {
      writeGenre: taggingPreferences.genre.enabled,
      genreTargetField: taggingPreferences.genre.targetField,
      writeAlbum: taggingPreferences.album.enabled,
      albumTargetField: taggingPreferences.album.targetField,
      writeComments: taggingPreferences.comments.enabled,
      commentsTargetField: taggingPreferences.comments.targetField,
      writeLikeness: taggingPreferences.likeness.enabled,
      likenessTargetField: taggingPreferences.likeness.targetField,
      generateVibes: taggingPreferences.vibes.enabled,
      vibesShortTargetField: taggingPreferences.vibes.shortTargetField,
      vibesLongTargetField: taggingPreferences.vibes.longTargetField,
      detectHooks: taggingPreferences.hooks.enabled,
      hooksTargetField: taggingPreferences.hooks.targetField,
      overwrite: taggingPreferences.overwrite,
    })
  }
```

**Step 3: Verify typecheck**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck 2>&1 | head -30`
Expected: May still have errors from TagTab.tsx (to fix next)

**Step 4: Commit**

```bash
git add desktop/src/components/TaggingView.tsx
git commit -m "feat: pass targetField values to tagging API"
```

---

## Task 5: Fix TagTab.tsx to Include Target Fields

**Files:**
- Modify: `desktop/src/components/TagTab.tsx:11-19,69-77`

**Step 1: Update local TaggingOptions interface**

In `desktop/src/components/TagTab.tsx`, update lines 11-19:

```typescript
interface TaggingOptions {
  writeGenre: boolean
  genreTargetField: string
  writeAlbum: boolean
  albumTargetField: string
  writeComments: boolean
  commentsTargetField: string
  writeLikeness: boolean
  likenessTargetField: string
  generateVibes: boolean
  vibesShortTargetField: string
  vibesLongTargetField: string
  detectHooks: boolean
  hooksTargetField: string
  overwrite: boolean
}
```

**Step 2: Update default options state**

Update lines 69-77 to include default target fields:

```typescript
  const [options, setOptions] = useState<TaggingOptions>({
    writeGenre: true,
    genreTargetField: 'TCON',
    writeAlbum: true,
    albumTargetField: 'TALB',
    writeComments: true,
    commentsTargetField: 'COMM',
    writeLikeness: true,
    likenessTargetField: 'TIT1',
    generateVibes: settings.vibeAvailable,
    vibesShortTargetField: 'TXXX:CRATEBOT_VIBE_SHORT',
    vibesLongTargetField: 'COMM',
    detectHooks: settings.hookAvailable,
    hooksTargetField: 'TXXX:CRATEBOT_HOOK',
    overwrite: true,
  })
```

**Step 3: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 4: Commit**

```bash
git add desktop/src/components/TagTab.tsx
git commit -m "fix: update TagTab with targetField properties"
```

---

## Task 6: Remove Duplicate Pause/Resume Controls from TrainTab

**Files:**
- Modify: `desktop/src/components/TrainTab.tsx:263-289`

**Step 1: Remove the duplicate Training Controls section**

In `desktop/src/components/TrainTab.tsx`, find and remove the entire "Training Controls" motion.div block (approximately lines 263-289):

```typescript
          {/* Training Controls */}
          <motion.div variants={itemVariants} className="flex gap-3">
            <button
              onClick={status === 'paused' ? resumeTraining : pauseTraining}
              className="btn btn-secondary"
            >
              {status === 'paused' ? (
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
            <button
              onClick={cancelTraining}
              className="btn btn-secondary text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
            >
              <Square className="w-4 h-4" />
              Stop
            </button>
          </motion.div>
```

Remove this entire block. The pause/resume controls are already in TrainingProgress component.

**Step 2: Remove unused imports**

If `Pause`, `Play`, `Square` are no longer used elsewhere in the file, remove them from the imports.

**Step 3: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 4: Commit**

```bash
git add desktop/src/components/TrainTab.tsx
git commit -m "fix: remove duplicate pause/resume controls from TrainTab"
```

---

## Task 7: Fix TrainingCompletionDialog Failed Count Calculation

**Files:**
- Modify: `desktop/src/components/TrainingCompletionDialog.tsx:10-20,38`

**Step 1: Add failedCount prop to interface**

In `desktop/src/components/TrainingCompletionDialog.tsx`, update the props interface to include explicit failedCount:

```typescript
interface TrainingCompletionDialogProps {
  isOpen: boolean
  onClose: () => void
  status: 'completed' | 'failed' | 'cancelled'
  filesProcessed: number
  filesSkipped: number  // Add this
  filesFailed: number   // Add this
  totalFiles: number
  samplesCollected: number
  metrics?: { accuracy: number; f1: number }
  error?: string
  onLoadModel: () => void
  onTrainAnother: () => void
}
```

**Step 2: Update the component to use explicit counts**

Replace line 38:
```typescript
const failedCount = totalFiles - filesProcessed
```

With:
```typescript
const skippedCount = filesSkipped
const failedCount = filesFailed
```

Update the display to show both skipped and failed separately if cancelled.

**Step 3: Update TrainTab to pass new props**

In `desktop/src/components/TrainTab.tsx`, update the TrainingCompletionDialog usage to pass the new props:

```typescript
<TrainingCompletionDialog
  isOpen={showCompletionDialog}
  onClose={() => setShowCompletionDialog(false)}
  status={status as 'completed' | 'failed' | 'cancelled'}
  filesProcessed={filesProcessed}
  filesSkipped={status === 'cancelled' ? totalFiles - filesProcessed : 0}
  filesFailed={status === 'failed' ? 1 : 0}
  totalFiles={totalFiles}
  samplesCollected={samplesCollected}
  metrics={metrics}
  error={error ?? undefined}
  onLoadModel={handleLoadModel}
  onTrainAnother={handleTrainAnother}
/>
```

**Step 4: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 5: Commit**

```bash
git add desktop/src/components/TrainingCompletionDialog.tsx desktop/src/components/TrainTab.tsx
git commit -m "fix: separate skipped and failed counts in TrainingCompletionDialog"
```

---

## Task 8: Add Error Handling for Lexicon Fetch in Confirmation Dialog

**Files:**
- Modify: `desktop/src/components/TaggingConfirmationDialog.tsx:43-51`

**Step 1: Add error state and toast**

In `desktop/src/components/TaggingConfirmationDialog.tsx`, update the useEffect for lexicon loading:

```typescript
  const [lexiconError, setLexiconError] = useState<string | null>(null)

  useEffect(() => {
    if (isOpen) {
      setLexiconError(null)
      api.getLexicon()
        .then(setLexicon)
        .catch((err) => {
          console.error('Failed to load lexicon:', err)
          setLexiconError('Could not load vocabulary settings')
        })
    }
  }, [isOpen])
```

**Step 2: Display error message in UI**

Add error display in the lexicon section (around line 200):

```typescript
{lexiconError && (
  <div className="text-xs text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 rounded px-2 py-1">
    {lexiconError}
  </div>
)}
```

**Step 3: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 4: Commit**

```bash
git add desktop/src/components/TaggingConfirmationDialog.tsx
git commit -m "fix: add error handling for lexicon fetch failure"
```

---

## Task 9: Extract formatTime Utility

**Files:**
- Create: `desktop/src/utils/formatTime.ts`
- Modify: `desktop/src/components/FileQueue.tsx:94-99`
- Modify: `desktop/src/components/TrainingProgress.tsx:70-75`

**Step 1: Create the utility file**

Create `desktop/src/utils/formatTime.ts`:

```typescript
/**
 * Format seconds as human-readable time string.
 * @param seconds - Number of seconds
 * @returns Formatted string like "5m 30s" or "1h 15m"
 */
export function formatTime(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`
  if (seconds < 3600) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.round(seconds % 60)
    return `${mins}m ${secs}s`
  }
  const hours = Math.floor(seconds / 3600)
  const mins = Math.round((seconds % 3600) / 60)
  return `${hours}h ${mins}m`
}
```

**Step 2: Update FileQueue to use shared utility**

In `desktop/src/components/FileQueue.tsx`, add import and remove local function:

```typescript
import { formatTime } from '../utils/formatTime'
```

Remove local `formatTime` function definition.

**Step 3: Update TrainingProgress to use shared utility**

In `desktop/src/components/TrainingProgress.tsx`, add import and remove local function:

```typescript
import { formatTime } from '../utils/formatTime'
```

Remove local `formatTime` function definition.

**Step 4: Verify typecheck passes**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 5: Commit**

```bash
git add desktop/src/utils/formatTime.ts desktop/src/components/FileQueue.tsx desktop/src/components/TrainingProgress.tsx
git commit -m "refactor: extract formatTime utility to shared file"
```

---

## Task 10: Final Build and Verification

**Step 1: Run full typecheck**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No errors

**Step 2: Build the app**

Run: `cd /Users/noahraford/CrateBot3/desktop && rm -rf dist dist-electron && npm run build`
Expected: Build completes successfully

**Step 3: Verify build output**

Run: `ls -la /Users/noahraford/CrateBot3/desktop/release/mac-arm64/CrateBot.app`
Expected: App bundle exists

**Step 4: Final commit with version bump**

```bash
git add -A
git commit -m "build: rebuild app with code review fixes

- Extracted ID3 frame constants to shared file
- Fixed targetField value consistency (now uses ID3 codes)
- Extended TaggingOptions to pass targetField to backend
- Removed duplicate pause/resume controls
- Fixed TrainingCompletionDialog failed count
- Added lexicon fetch error handling
- Extracted formatTime utility"
```
