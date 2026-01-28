# UI/UX Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 13 UI/UX improvements including splash screen update, training tab console redesign, tagging status fixes, and new confirmation popup before tagging.

**Architecture:** Component-level modifications across the desktop React app. Most changes are visual/UI with minimal state changes. Key architectural addition is a new TaggingConfirmationDialog component that shows before tagging starts.

**Tech Stack:** React 18.2, TypeScript, TailwindCSS, Zustand, Framer Motion

---

## Task 1: Update Splash Screen Text

**Files:**
- Modify: `desktop/index.html:89`

**Problem:** Splash screen shows "Genre • Timing • Mood • Descriptive" but should show "GENRE - TIMING - MOOD - DESCRIPTION" then "YOUR TAGGING BUDDY" on next line.

**Step 1: Update tagline HTML**

Replace line 89:
```html
<p class="tagline">Genre • Timing • Mood • Descriptive</p>
```

With:
```html
<p class="tagline">GENRE - TIMING - MOOD - DESCRIPTION</p>
<p class="tagline" style="margin-top: 4px;">YOUR TAGGING BUDDY</p>
```

**Step 2: Verify in browser**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run dev`
Expected: Splash shows updated text on two lines

**Step 3: Commit**

```bash
git add desktop/index.html
git commit -m "ui: update splash screen tagline text"
```

---

## Task 2: Update Lexicon ID3 Frames to Match iTunes

**Files:**
- Modify: `desktop/src/components/settings/LexiconEditor.tsx:19-79`

**Problem:** Current ID3_FRAMES list is missing some iTunes fields shown in screenshot. Need to add: Album Rating, Beats Per Minute (if missing), Category, Cloud Download, Cloud Status, Date Modified, Disc Number, Equalizer, Favorite, Kind, Last Played, Last Skipped, Movement Name, Movement Number, Plays, Purchase Date, Rating, Release Date, Sample Rate, Size, Skips, Sort Album, Sort Album Artist, Sort Artist, Sort Composer, Sort Title.

**Step 1: Update ID3_FRAMES array**

Replace the ID3_FRAMES constant with an expanded version including all iTunes fields:

```typescript
const ID3_FRAMES: Array<{ code: string; name: string; description: string; group: string }> = [
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
  { code: 'TXXX:ENERGY', name: 'Energy', description: 'Energy level (DJ software)', group: 'Custom' },
]

// Group frames by category for the UI
const FRAME_GROUPS = ['Primary', 'Classification', 'Artist', 'Sorting', 'Stats', 'Album', 'Publishing', 'Date', 'Track', 'Cloud', 'Custom']
```

**Step 2: Run type check**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No type errors

**Step 3: Commit**

```bash
git add desktop/src/components/settings/LexiconEditor.tsx
git commit -m "feat: expand lexicon ID3 frames to include full iTunes field list"
```

---

## Task 3: Add Vibes Tag Field Assignment

**Files:**
- Modify: `desktop/src/stores/appStore.ts:80-88`
- Modify: `desktop/src/components/SettingsPanel.tsx:165-190`
- Modify: `desktop/src/components/settings/LexiconEditor.tsx`

**Problem:** Users should be able to assign where short and long vibes descriptions are written.

**Step 1: Update taggingPreferences in appStore**

Add vibes target fields to the interface and defaults:

In appStore.ts, update the taggingPreferences type (around line 80):
```typescript
taggingPreferences: {
  genre: { enabled: boolean; targetField: string }
  album: { enabled: boolean; targetField: string }
  comments: { enabled: boolean; targetField: string }
  likeness: { enabled: boolean; targetField: string }
  vibes: { enabled: boolean; shortTargetField: string; longTargetField: string }
  hooks: { enabled: boolean; targetField: string }
  overwrite: boolean
}
```

Update DEFAULT_TAGGING_PREFERENCES (around line 111):
```typescript
const DEFAULT_TAGGING_PREFERENCES: AppState['taggingPreferences'] = {
  genre: { enabled: true, targetField: 'genre' },
  album: { enabled: true, targetField: 'album' },
  comments: { enabled: true, targetField: 'comments' },
  likeness: { enabled: true, targetField: 'grouping' },
  vibes: { enabled: false, shortTargetField: 'TXXX:CRATEBOT_VIBE_SHORT', longTargetField: 'COMM' },
  hooks: { enabled: false, targetField: 'TXXX:CRATEBOT_HOOK' },
  overwrite: true,
}
```

**Step 2: Update SettingsPanel vibes section**

In SettingsPanel.tsx, add field selectors after the vibes checkbox (around line 177):

```tsx
<label className={`flex items-center gap-3 p-2 rounded-lg ${settings.vibeAvailable ? 'hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer' : 'opacity-50'}`}>
  <input
    type="checkbox"
    checked={taggingPreferences.vibes.enabled}
    onChange={(e) => setTaggingPreferences({
      vibes: { ...taggingPreferences.vibes, enabled: e.target.checked }
    })}
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
```

**Step 3: Run type check and verify**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No type errors

**Step 4: Commit**

```bash
git add desktop/src/stores/appStore.ts desktop/src/components/SettingsPanel.tsx
git commit -m "feat: add vibes tag field assignment options"
```

---

## Task 4: Fix Tagging Status Visuals (Three States)

**Files:**
- Modify: `desktop/src/components/FileQueue.tsx:48-91`
- Review: `desktop/src/hooks/useTagging.ts`

**Problem:** Status visuals should show three distinct states:
1. **Pending**: Grey clock icon, grey "Pending" text
2. **Processing/Active**: Yellow/amber spinner, yellow "Processing" text
3. **Completed**: Green checkmark, green "Complete" text

**Step 1: Verify statusConfig is correct**

The current statusConfig in FileQueue.tsx (lines 48-91) already looks correct:
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
  // ... rest
}
```

**Step 2: Check useTagging hook updates file status**

Review `desktop/src/hooks/useTagging.ts` to ensure files transition through states correctly. The hook should:
- Set status to 'pending' when files are added
- Set status to 'processing' when tagging starts on a file
- Set status to 'tagged' when complete

**Step 3: Add debugging if needed**

If statuses aren't updating, add console.log statements to trace the flow:
```typescript
// In useTagging.ts processFile function
console.log(`[Tagging] Starting file: ${file.name}, status: processing`)
// After completion
console.log(`[Tagging] Completed file: ${file.name}, status: tagged`)
```

**Step 4: Commit any fixes**

```bash
git add desktop/src/hooks/useTagging.ts desktop/src/components/FileQueue.tsx
git commit -m "fix: ensure tagging status visuals update correctly"
```

---

## Task 5: Update FileQueue Header with Stats Summary

**Files:**
- Modify: `desktop/src/components/FileQueue.tsx:159-213`

**Problem:** The header should reflect totals for pending/active/complete with time per track and ETA.

**Step 1: Update header stats section**

The current header (lines 159-213) already shows some stats. Enhance it to be clearer:

Replace the header content section:
```tsx
{/* Header */}
<div className="flex items-center justify-between px-4 py-3 bg-surface-sunken dark:bg-surface-dark-sunken border-b border-border-light dark:border-border-dark">
  <div className="flex items-center gap-4">
    <span className="font-medium text-stone-900 dark:text-stone-100">
      {stats.total} files
    </span>
    <div className="flex items-center gap-3 text-xs">
      {stats.pending > 0 && (
        <span className="flex items-center gap-1 text-stone-400">
          <Clock className="w-3 h-3" />
          {stats.pending} pending
        </span>
      )}
      {stats.processing > 0 && (
        <span className="flex items-center gap-1 text-amber-500">
          <Loader2 className={clsx('w-3 h-3', !isPaused && 'animate-spin')} />
          {stats.processing} processing
        </span>
      )}
      {stats.tagged > 0 && (
        <span className="flex items-center gap-1 text-emerald-500">
          <CheckCircle2 className="w-3 h-3" />
          {stats.tagged} complete
        </span>
      )}
      {stats.failed > 0 && (
        <span className="flex items-center gap-1 text-red-500">
          <XCircle className="w-3 h-3" />
          {stats.failed} failed
        </span>
      )}
    </div>
  </div>
  <div className="flex items-center gap-4">
    {/* Time estimates - always show during processing */}
    {isProcessing && (
      <div className="flex items-center gap-3 text-xs text-stone-500 dark:text-stone-400">
        {completedCount > 0 && (
          <span>{avgTimePerTrack.toFixed(1)}s/track</span>
        )}
        {remainingCount > 0 && avgTimePerTrack > 0 && (
          <span>ETA: {formatTime(etaSeconds)}</span>
        )}
      </div>
    )}
    {onClear && !isProcessing && (
      <motion.button
        onClick={onClear}
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        className="text-xs text-stone-400 hover:text-red-500 flex items-center gap-1 transition-colors"
      >
        <Trash2 className="w-3 h-3" />
        Clear all
      </motion.button>
    )}
  </div>
</div>
```

**Step 2: Add missing imports if needed**

Ensure these icons are imported at the top:
```typescript
import { CheckCircle2, XCircle, Clock, Loader2, ... } from 'lucide-react'
```

**Step 3: Run type check**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No type errors

**Step 4: Commit**

```bash
git add desktop/src/components/FileQueue.tsx
git commit -m "ui: improve file queue header stats display"
```

---

## Task 6: Create Tagging Confirmation Dialog

**Files:**
- Create: `desktop/src/components/TaggingConfirmationDialog.tsx`
- Modify: `desktop/src/components/TaggingView.tsx`

**Problem:** Pull "Tagging Settings" & "Lexicon & Vocabulary" out of Settings and into a popup that appears after clicking "Start Tagging". This ensures users confirm what tags are being written and what dictionary they're using.

**Step 1: Create TaggingConfirmationDialog component**

Create new file `desktop/src/components/TaggingConfirmationDialog.tsx`:

```tsx
/**
 * TaggingConfirmationDialog
 * Shows tagging settings and lexicon for confirmation before starting tagging.
 */
import { useState, useEffect } from 'react'
import { X, Play, Settings2, BookOpen } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { api, LexiconConfig } from '../api/client'

interface TaggingConfirmationDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  fileCount: number
}

export function TaggingConfirmationDialog({
  isOpen,
  onClose,
  onConfirm,
  fileCount,
}: TaggingConfirmationDialogProps) {
  const { taggingPreferences, setTaggingPreferences, settings } = useAppStore()
  const [lexicon, setLexicon] = useState<LexiconConfig | null>(null)
  const [showLexiconDetails, setShowLexiconDetails] = useState(false)

  useEffect(() => {
    if (isOpen) {
      api.getLexicon().then(setLexicon).catch(console.error)
    }
  }, [isOpen])

  const updateFieldPref = (field: 'genre' | 'album' | 'comments' | 'likeness', enabled: boolean) => {
    setTaggingPreferences({
      [field]: { ...taggingPreferences[field], enabled },
    })
  }

  const updateFeaturePref = (field: 'vibes' | 'hooks', enabled: boolean) => {
    setTaggingPreferences({
      [field]: { ...taggingPreferences[field], enabled },
    })
  }

  const enabledTags = [
    taggingPreferences.genre.enabled && 'Genre',
    taggingPreferences.album.enabled && 'Album (Mood)',
    taggingPreferences.comments.enabled && 'Comments',
    taggingPreferences.likeness.enabled && 'Likeness',
    taggingPreferences.vibes.enabled && 'Vibes',
    taggingPreferences.hooks.enabled && 'Hooks',
  ].filter(Boolean)

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/50 z-40"
            onClick={onClose}
          />

          {/* Dialog */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="fixed inset-0 flex items-center justify-center z-50 p-4"
          >
            <div className="bg-surface-light dark:bg-surface-dark rounded-2xl shadow-2xl w-full max-w-lg max-h-[80vh] overflow-hidden flex flex-col">
              {/* Header */}
              <div className="flex items-center justify-between px-6 py-4 border-b border-border-light dark:border-border-dark">
                <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">
                  Confirm Tagging Settings
                </h2>
                <button
                  onClick={onClose}
                  className="p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Content */}
              <div className="flex-1 overflow-auto px-6 py-4 space-y-6">
                {/* Summary */}
                <div className="p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-xl">
                  <p className="text-sm text-amber-800 dark:text-amber-200">
                    <strong>{fileCount}</strong> files will be tagged with:{' '}
                    <strong>{enabledTags.join(', ') || 'No tags selected'}</strong>
                  </p>
                </div>

                {/* Tags to Write */}
                <section>
                  <div className="flex items-center gap-2 mb-3">
                    <Settings2 className="w-4 h-4 text-stone-400" />
                    <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300">
                      Tags to Write
                    </h3>
                  </div>
                  <div className="space-y-2">
                    <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                      <input
                        type="checkbox"
                        checked={taggingPreferences.genre.enabled}
                        onChange={(e) => updateFieldPref('genre', e.target.checked)}
                        className="checkbox"
                      />
                      <span className="text-sm text-stone-700 dark:text-stone-300">Genre</span>
                      {lexicon && (
                        <span className="text-xs text-stone-400 ml-auto">
                          → {lexicon.categories.genre.id3_frame}
                        </span>
                      )}
                    </label>
                    <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                      <input
                        type="checkbox"
                        checked={taggingPreferences.album.enabled}
                        onChange={(e) => updateFieldPref('album', e.target.checked)}
                        className="checkbox"
                      />
                      <span className="text-sm text-stone-700 dark:text-stone-300">Album (Mood)</span>
                      {lexicon && (
                        <span className="text-xs text-stone-400 ml-auto">
                          → {lexicon.categories.timing.id3_frame}
                        </span>
                      )}
                    </label>
                    <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                      <input
                        type="checkbox"
                        checked={taggingPreferences.comments.enabled}
                        onChange={(e) => updateFieldPref('comments', e.target.checked)}
                        className="checkbox"
                      />
                      <span className="text-sm text-stone-700 dark:text-stone-300">Comments</span>
                      {lexicon && (
                        <span className="text-xs text-stone-400 ml-auto">
                          → {lexicon.categories.mood.id3_frame}
                        </span>
                      )}
                    </label>
                    <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                      <input
                        type="checkbox"
                        checked={taggingPreferences.likeness.enabled}
                        onChange={(e) => updateFieldPref('likeness', e.target.checked)}
                        className="checkbox"
                      />
                      <span className="text-sm text-stone-700 dark:text-stone-300">Likeness Scores</span>
                    </label>
                  </div>
                </section>

                {/* AI Features */}
                <section>
                  <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">
                    AI Features
                  </h3>
                  <div className="space-y-2">
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
                  </div>
                </section>

                {/* Overwrite Option */}
                <section>
                  <label className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.overwrite}
                      onChange={(e) => setTaggingPreferences({ overwrite: e.target.checked })}
                      className="checkbox"
                    />
                    <span className="text-sm font-medium text-stone-700 dark:text-stone-300">
                      Overwrite existing tags
                    </span>
                  </label>
                </section>

                {/* Lexicon Preview */}
                <section>
                  <button
                    onClick={() => setShowLexiconDetails(!showLexiconDetails)}
                    className="flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400 hover:underline"
                  >
                    <BookOpen className="w-4 h-4" />
                    {showLexiconDetails ? 'Hide' : 'Show'} Lexicon Details
                  </button>
                  {showLexiconDetails && lexicon && (
                    <div className="mt-3 p-3 bg-surface-sunken dark:bg-surface-dark-sunken rounded-lg text-xs space-y-2">
                      {Object.entries(lexicon.categories).map(([key, cat]) => (
                        <div key={key} className="flex justify-between">
                          <span className="capitalize text-stone-600 dark:text-stone-400">{key}:</span>
                          <span className="text-stone-800 dark:text-stone-200 font-mono">{cat.id3_frame}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </section>
              </div>

              {/* Footer */}
              <div className="flex justify-end gap-3 px-6 py-4 border-t border-border-light dark:border-border-dark">
                <button onClick={onClose} className="btn btn-secondary">
                  Cancel
                </button>
                <button
                  onClick={onConfirm}
                  disabled={enabledTags.length === 0}
                  className="btn btn-primary"
                >
                  <Play className="w-4 h-4" />
                  Start Tagging
                </button>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
```

**Step 2: Update TaggingView to use confirmation dialog**

In TaggingView.tsx, add the dialog:

Add import at top:
```typescript
import { TaggingConfirmationDialog } from './TaggingConfirmationDialog'
```

Add state:
```typescript
const [showConfirmDialog, setShowConfirmDialog] = useState(false)
```

Update the Start Tagging button handler:
```typescript
<button
  onClick={() => setShowConfirmDialog(true)}  // Changed from handleStartTagging
  disabled={!canStart}
  className="btn btn-primary"
>
  <Play className="w-4 h-4" />
  Start Tagging ({pendingCount} files)
</button>
```

Add dialog before closing tags:
```tsx
{/* Tagging Confirmation Dialog */}
<TaggingConfirmationDialog
  isOpen={showConfirmDialog}
  onClose={() => setShowConfirmDialog(false)}
  onConfirm={() => {
    setShowConfirmDialog(false)
    handleStartTagging()
  }}
  fileCount={pendingCount}
/>
```

**Step 3: Run type check**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No type errors

**Step 4: Commit**

```bash
git add desktop/src/components/TaggingConfirmationDialog.tsx desktop/src/components/TaggingView.tsx
git commit -m "feat: add tagging confirmation dialog before starting"
```

---

## Task 7: Update Training Console to Match Tagging Status UI

**Files:**
- Modify: `desktop/src/components/TrainTab.tsx`
- Modify: `desktop/src/components/TrainingProgress.tsx`
- Modify: `desktop/src/hooks/useTraining.ts`

**Problem:** Training console should follow same UI as tagging status (grey/green/yellow, time per track, time left to completion).

**Step 1: Add time tracking to useTraining hook**

In `useTraining.ts`, add startTime tracking:

Add to TrainingState interface:
```typescript
startTime: number | null
```

Initialize in useState:
```typescript
startTime: null,
```

Set when training starts (in startTraining function):
```typescript
setState((prev) => ({
  ...prev,
  status: 'running',
  phase: 'collecting',
  progress: 0,
  error: null,
  metrics: null,
  startTime: Date.now(),  // Add this
}))
```

**Step 2: Update TrainingProgress to show time estimates**

In TrainingProgress.tsx, add time calculation and display:

Add props to interface:
```typescript
startTime?: number | null
```

Add time calculation inside component:
```typescript
// Calculate time estimates
const elapsedSeconds = startTime ? (Date.now() - startTime) / 1000 : 0
const avgTimePerFile = filesProcessed > 0 ? elapsedSeconds / filesProcessed : 0
const remainingFiles = totalFiles - filesProcessed
const etaSeconds = avgTimePerFile * remainingFiles

function formatTime(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`
  const mins = Math.floor(seconds / 60)
  const secs = Math.round(seconds % 60)
  return `${mins}m ${secs}s`
}
```

Add to stats grid (replace the third stat box):
```tsx
<div className="grid grid-cols-4 gap-4">
  <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
    <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">Files</div>
    <div className="font-display font-semibold text-stone-900 dark:text-stone-100">
      {filesProcessed} <span className="text-stone-400 font-normal">/ {totalFiles}</span>
    </div>
  </div>
  <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
    <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">Samples</div>
    <div className="font-display font-semibold text-stone-900 dark:text-stone-100">
      {samplesCollected.toLocaleString()}
    </div>
  </div>
  <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
    <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">Time/File</div>
    <div className="font-display font-semibold text-stone-900 dark:text-stone-100">
      {avgTimePerFile > 0 ? `${avgTimePerFile.toFixed(1)}s` : '-'}
    </div>
  </div>
  <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
    <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">ETA</div>
    <div className={clsx('font-display font-semibold', config.color)}>
      {remainingFiles > 0 && avgTimePerFile > 0 ? formatTime(etaSeconds) : status}
    </div>
  </div>
</div>
```

**Step 3: Pass startTime from TrainTab to TrainingProgress**

In TrainTab.tsx, update the TrainingProgress calls to include startTime:
```tsx
<TrainingProgress
  status={status as 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'}
  phase={phase}
  progress={progress}
  currentFile={currentFile || undefined}
  filesProcessed={filesProcessed}
  totalFiles={totalFiles}
  samplesCollected={samplesCollected}
  startTime={startTime}  // Add this (need to expose from hook)
  onCancel={cancelTraining}
/>
```

**Step 4: Commit**

```bash
git add desktop/src/components/TrainTab.tsx desktop/src/components/TrainingProgress.tsx desktop/src/hooks/useTraining.ts
git commit -m "feat: add time estimates to training progress display"
```

---

## Task 8: Add Training Pause/Resume and Stop/Restart Buttons

**Files:**
- Modify: `desktop/src/hooks/useTraining.ts`
- Modify: `desktop/src/components/TrainTab.tsx`
- Modify: `backend/api_server.py`

**Problem:** Training needs Pause/Resume and Stop/Restart buttons that flip state depending on status.

**Step 1: Add pause/resume to useTraining hook**

In useTraining.ts, add:
```typescript
// Pause training
const pauseTraining = useCallback(async () => {
  if (!state.taskId) return
  addLog('Pausing training...')
  try {
    await api.pauseTraining(state.taskId)
    setState((prev) => ({ ...prev, status: 'paused' }))
    addLog('Training paused')
  } catch (error) {
    addLog(`Failed to pause: ${error}`)
  }
}, [state.taskId, addLog])

// Resume training
const resumeTraining = useCallback(async () => {
  if (!state.taskId) return
  addLog('Resuming training...')
  try {
    await api.resumeTraining(state.taskId)
    setState((prev) => ({ ...prev, status: 'running' }))
    addLog('Training resumed')
  } catch (error) {
    addLog(`Failed to resume: ${error}`)
  }
}, [state.taskId, addLog])
```

Add to return object:
```typescript
return {
  // ... existing
  pauseTraining,
  resumeTraining,
}
```

**Step 2: Add API methods if missing**

In `desktop/src/api/client.ts`, add:
```typescript
async pauseTraining(taskId: string): Promise<void> {
  const response = await fetch(`${this.baseUrl}/training/${taskId}/pause`, {
    method: 'POST',
  })
  if (!response.ok) throw new Error('Failed to pause training')
}

async resumeTraining(taskId: string): Promise<void> {
  const response = await fetch(`${this.baseUrl}/training/${taskId}/resume`, {
    method: 'POST',
  })
  if (!response.ok) throw new Error('Failed to resume training')
}
```

**Step 3: Update TrainTab with control buttons**

In TrainTab.tsx, update the training controls section:
```tsx
{/* Training Actions (when training) */}
{isTraining && (
  <motion.div variants={itemVariants} className="flex gap-3 mt-4">
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
)}
```

Add imports:
```typescript
import { Play, Pause, Square } from 'lucide-react'
```

Destructure from hook:
```typescript
const { ..., pauseTraining, resumeTraining } = useTraining()
```

**Step 4: Commit**

```bash
git add desktop/src/hooks/useTraining.ts desktop/src/components/TrainTab.tsx desktop/src/api/client.ts
git commit -m "feat: add pause/resume and stop buttons to training"
```

---

## Task 9: Create Training Completion Dialog

**Files:**
- Create: `desktop/src/components/TrainingCompletionDialog.tsx`
- Modify: `desktop/src/components/TrainTab.tsx`

**Problem:** Show popup at end of training with success/fail counts and error messages.

**Step 1: Create TrainingCompletionDialog component**

Create `desktop/src/components/TrainingCompletionDialog.tsx`:

```tsx
/**
 * TrainingCompletionDialog
 * Shows training results with success/fail counts and error details.
 */
import { CheckCircle2, XCircle, AlertTriangle, X } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'

interface TrainingCompletionDialogProps {
  isOpen: boolean
  onClose: () => void
  status: 'completed' | 'failed' | 'cancelled'
  filesProcessed: number
  totalFiles: number
  samplesCollected: number
  metrics?: {
    genreAccuracy?: number
    albumAccuracy?: number
    commentsF1?: number
  }
  error?: string
  onLoadModel?: () => void
  onTrainAnother?: () => void
}

export function TrainingCompletionDialog({
  isOpen,
  onClose,
  status,
  filesProcessed,
  totalFiles,
  samplesCollected,
  metrics,
  error,
  onLoadModel,
  onTrainAnother,
}: TrainingCompletionDialogProps) {
  const failedCount = totalFiles - filesProcessed

  const statusConfig = {
    completed: {
      icon: CheckCircle2,
      title: 'Training Complete!',
      color: 'text-emerald-500',
      bgColor: 'bg-emerald-100 dark:bg-emerald-900/30',
    },
    failed: {
      icon: XCircle,
      title: 'Training Failed',
      color: 'text-red-500',
      bgColor: 'bg-red-100 dark:bg-red-900/30',
    },
    cancelled: {
      icon: AlertTriangle,
      title: 'Training Cancelled',
      color: 'text-amber-500',
      bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    },
  }

  const config = statusConfig[status]
  const Icon = config.icon

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/50 z-40"
            onClick={onClose}
          />

          {/* Dialog */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="fixed inset-0 flex items-center justify-center z-50 p-4"
          >
            <div className="bg-surface-light dark:bg-surface-dark rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
              {/* Header */}
              <div className="flex items-center justify-between px-6 py-4 border-b border-border-light dark:border-border-dark">
                <div className="flex items-center gap-3">
                  <div className={clsx('w-10 h-10 rounded-xl flex items-center justify-center', config.bgColor)}>
                    <Icon className={clsx('w-5 h-5', config.color)} />
                  </div>
                  <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">
                    {config.title}
                  </h2>
                </div>
                <button
                  onClick={onClose}
                  className="p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Content */}
              <div className="px-6 py-4 space-y-4">
                {/* Stats */}
                <div className="grid grid-cols-3 gap-3">
                  <div className="p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 text-center">
                    <div className="text-2xl font-bold text-emerald-600 dark:text-emerald-400">
                      {filesProcessed}
                    </div>
                    <div className="text-xs text-emerald-600 dark:text-emerald-400">Processed</div>
                  </div>
                  {failedCount > 0 && (
                    <div className="p-3 rounded-xl bg-red-50 dark:bg-red-900/20 text-center">
                      <div className="text-2xl font-bold text-red-600 dark:text-red-400">
                        {failedCount}
                      </div>
                      <div className="text-xs text-red-600 dark:text-red-400">Failed</div>
                    </div>
                  )}
                  <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken text-center">
                    <div className="text-2xl font-bold text-stone-700 dark:text-stone-300">
                      {samplesCollected.toLocaleString()}
                    </div>
                    <div className="text-xs text-stone-500">Samples</div>
                  </div>
                </div>

                {/* Metrics (if completed) */}
                {status === 'completed' && metrics && (
                  <div className="p-4 bg-surface-sunken dark:bg-surface-dark-sunken rounded-xl">
                    <h4 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">
                      Model Accuracy
                    </h4>
                    <div className="space-y-2">
                      {metrics.genreAccuracy !== undefined && (
                        <div className="flex justify-between text-sm">
                          <span className="text-stone-500">Genre:</span>
                          <span className="font-medium text-emerald-600 dark:text-emerald-400">
                            {(metrics.genreAccuracy * 100).toFixed(1)}%
                          </span>
                        </div>
                      )}
                      {metrics.albumAccuracy !== undefined && (
                        <div className="flex justify-between text-sm">
                          <span className="text-stone-500">Album:</span>
                          <span className="font-medium text-emerald-600 dark:text-emerald-400">
                            {(metrics.albumAccuracy * 100).toFixed(1)}%
                          </span>
                        </div>
                      )}
                      {metrics.commentsF1 !== undefined && (
                        <div className="flex justify-between text-sm">
                          <span className="text-stone-500">Comments F1:</span>
                          <span className="font-medium text-emerald-600 dark:text-emerald-400">
                            {(metrics.commentsF1 * 100).toFixed(1)}%
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                )}

                {/* Error Message */}
                {error && (
                  <div className="p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl">
                    <h4 className="text-sm font-medium text-red-700 dark:text-red-300 mb-1">
                      Error Details
                    </h4>
                    <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
                  </div>
                )}
              </div>

              {/* Footer */}
              <div className="flex justify-end gap-3 px-6 py-4 border-t border-border-light dark:border-border-dark">
                <button onClick={onTrainAnother} className="btn btn-secondary">
                  Train Another
                </button>
                {status === 'completed' && onLoadModel && (
                  <button onClick={onLoadModel} className="btn btn-primary">
                    Load Model
                  </button>
                )}
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
```

**Step 2: Add dialog to TrainTab**

In TrainTab.tsx, add:

Import:
```typescript
import { TrainingCompletionDialog } from './TrainingCompletionDialog'
```

Add state:
```typescript
const [showCompletionDialog, setShowCompletionDialog] = useState(false)
```

Show dialog when training completes (add useEffect):
```typescript
useEffect(() => {
  if (isComplete) {
    setShowCompletionDialog(true)
  }
}, [isComplete])
```

Add dialog to JSX:
```tsx
<TrainingCompletionDialog
  isOpen={showCompletionDialog}
  onClose={() => setShowCompletionDialog(false)}
  status={status as 'completed' | 'failed' | 'cancelled'}
  filesProcessed={filesProcessed}
  totalFiles={totalFiles}
  samplesCollected={samplesCollected}
  metrics={metrics || undefined}
  error={error || undefined}
  onLoadModel={() => {
    setShowCompletionDialog(false)
    // Load the trained model
  }}
  onTrainAnother={() => {
    setShowCompletionDialog(false)
    reset()
  }}
/>
```

**Step 3: Commit**

```bash
git add desktop/src/components/TrainingCompletionDialog.tsx desktop/src/components/TrainTab.tsx
git commit -m "feat: add training completion dialog with results summary"
```

---

## Task 10: Update Version in Settings Footer

**Files:**
- Modify: `desktop/src/components/SettingsPanel.tsx:359`

**Problem:** Version should be updated with each build (3.x.x format).

**Step 1: Update version string**

In SettingsPanel.tsx line 359, update:
```tsx
<div className="text-xs text-stone-400 text-center">
  CrateBot v3.1.0
</div>
```

**Step 2: Commit**

```bash
git add desktop/src/components/SettingsPanel.tsx
git commit -m "chore: bump version to 3.1.0"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Update splash screen text | desktop/index.html |
| 2 | Expand lexicon ID3 frames | desktop/src/components/settings/LexiconEditor.tsx |
| 3 | Add vibes tag field assignment | appStore.ts, SettingsPanel.tsx |
| 4 | Fix tagging status visuals | FileQueue.tsx, useTagging.ts |
| 5 | Update file queue header stats | FileQueue.tsx |
| 6 | Create tagging confirmation dialog | TaggingConfirmationDialog.tsx, TaggingView.tsx |
| 7 | Add time estimates to training | TrainingProgress.tsx, useTraining.ts |
| 8 | Add training pause/stop buttons | TrainTab.tsx, useTraining.ts, api/client.ts |
| 9 | Create training completion dialog | TrainingCompletionDialog.tsx, TrainTab.tsx |
| 10 | Update version number | SettingsPanel.tsx |

---

## Verification Plan

After implementing all tasks:

1. **Splash Screen**: Launch app, verify new tagline text displays
2. **Lexicon**: Open Settings → Lexicon, verify expanded ID3 frame options
3. **Vibes Fields**: Enable Vibes, verify short/long field selectors appear
4. **Tagging Status**: Add files, start tagging, verify pending/processing/complete states
5. **File Queue Header**: Verify stats show correctly during processing
6. **Confirmation Dialog**: Click Start Tagging, verify dialog appears with settings
7. **Training Time**: Start training, verify time/file and ETA display
8. **Training Controls**: Verify Pause/Resume and Stop buttons work
9. **Training Completion**: Complete training, verify results dialog appears
10. **Version**: Open Settings, verify version shows 3.1.0
