# UX Fixes Batch 2 - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix remaining UX issues from the setup-first flow redesign

**Architecture:** Direct component modifications with minimal state changes

**Tech Stack:** React, TypeScript, Tailwind CSS, Zustand

---

## Task 1: Update Loading Screen to Match App Style

**Files:**
- Modify: `desktop/index.html`

**Problem:** Loading screen uses old gradient style with spinning SVG. Should match SetupWizard welcome screen (rounded amber circle with disc icon, clean typography on dark surface).

**Step 1: Update the loading screen HTML/CSS**

Replace the entire `<style>` and `#app-loading` sections:

```html
<style>
  #app-loading {
    position: fixed;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: #1a1918;
    color: #fafaf9;
    font-family: "DM Sans", system-ui, sans-serif;
    transition: opacity 300ms ease;
  }
  #app-loading.fade-out {
    opacity: 0;
  }
  #app-loading .logo-circle {
    width: 80px;
    height: 80px;
    border-radius: 50%;
    background: rgba(251, 191, 36, 0.15);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 24px;
  }
  #app-loading .logo-circle svg {
    width: 40px;
    height: 40px;
    color: #f59e0b;
  }
  #app-loading .brand {
    font-size: 32px;
    font-weight: 700;
    margin-bottom: 8px;
    color: #fafaf9;
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
    gap: 10px;
  }
  #app-loading .spinner {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    border: 2px solid rgba(245, 158, 11, 0.3);
    border-top-color: #f59e0b;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
```

Update the HTML structure:

```html
<div id="app-loading">
  <div class="logo-circle">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="10"/>
      <circle cx="12" cy="12" r="3"/>
    </svg>
  </div>
  <div class="brand">Crate<span>Bot</span></div>
  <div class="loading-text">
    <div class="spinner"></div>
    <span id="loading-status">Starting up...</span>
  </div>
</div>
```

**Step 2: Update CSP hash**

After changing the inline script, recalculate the hash if needed. Current script is unchanged so hash stays same.

---

## Task 2: Remove Horizontal Rule from Model Page Helper Text

**Files:**
- Modify: `desktop/src/components/SetupWizard.tsx:319`

**Problem:** The helper text "You can train your own model..." appears above a border-t divider in the footer. The user wants this divider removed.

**Step 1: Check if this is the footer border or a separate element**

Looking at lines 319: `<div className="flex justify-between pt-6 border-t border-border-light dark:border-border-dark">`

This is the navigation footer. The helper text at line 293-295 doesn't have its own hr. The "border-t" is on the footer nav.

**Resolution:** The helper text itself has no hr. The footer border is intentional UI separation. May need clarification - but if user wants NO line between content and buttons, remove `border-t border-border-light dark:border-border-dark` from footer div class.

---

## Task 3: Redesign "All Set" Completion Screen

**Files:**
- Modify: `desktop/src/components/SetupWizard.tsx:484-524`

**Problem:**
- Model name should be in green
- Remove "Genre → genre, Mood → album..." mapping text
- Show "Vibes & Hooks" in green if enabled

**Step 1: Update the summary section**

Replace lines 484-524 with:

```tsx
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

    {/* Tags */}
    <div className="flex justify-between items-center">
      <span className="text-stone-500 dark:text-stone-400">Tags:</span>
      <span className="font-medium text-emerald-600 dark:text-emerald-400">
        {[
          taggingPreferences.genre.enabled && 'Genre',
          taggingPreferences.album.enabled && 'Mood',
          taggingPreferences.comments.enabled && 'Comments',
          taggingPreferences.likeness.enabled && 'Likeness',
        ].filter(Boolean).join(', ') || 'None'}
      </span>
    </div>

    {/* AI Features */}
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
```

---

## Task 4: Fix Status Bar Model Display

**Files:**
- Modify: `desktop/src/components/MainHeader.tsx:49-61`

**Problem:** Shows "Model: Unknown" and includes "(7 genres)" text.

**Step 1: Update Model Info section**

Replace lines 49-61:

```tsx
{/* Model Info */}
<div className="ml-8 flex items-center gap-4 no-drag">
  <div className="text-sm">
    <span className="text-stone-400 dark:text-stone-500">Model:</span>
    <span className="ml-2 font-medium text-stone-700 dark:text-stone-300">
      {model.loaded ? (model.name || 'Loaded') : 'Not loaded'}
    </span>
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
```

---

## Task 5: Verify File Status Colors Are Applied

**Files:**
- Review: `desktop/src/components/FileQueue.tsx`

**Analysis:** The FileQueue already has correct statusConfig (lines 49-92):
- `pending`: grey clock, grey "Pending"
- `processing`: amber loader (spinning), amber "Processing"
- `tagged`: emerald check, emerald "Complete"

**Problem:** These ARE implemented correctly. If not showing, check if `files` state is being updated properly in `useTagging` hook.

**Step 1: Verify useTagging updates file status**

Check `desktop/src/hooks/useTagging.ts` to ensure file status updates to 'processing' and 'tagged'.

---

## Task 6: Add Time Estimates to Status Bar

**Files:**
- Modify: `desktop/src/components/StatusBar.tsx`
- Modify: `desktop/src/stores/appStore.ts`

**Problem:** Status bar should show file progress, time per file, and ETA during tagging.

**Analysis:** StatusBar already has this code (lines 83-109) but it only shows when `taggingStats.processing > 0`.

**Step 1: Ensure taggingStats is being set**

Check if `useTagging` hook calls `setTaggingStats()` from the store.

Check `desktop/src/hooks/useTagging.ts` for `setTaggingStats` calls.

---

## Task 7: Auto-load Tagged Files in RefineTab on "Review Tags"

**Files:**
- Modify: `desktop/src/components/TaggingView.tsx`
- Modify: `desktop/src/components/RefineTab.tsx`
- Modify: `desktop/src/hooks/useRefinement.ts`
- Modify: `desktop/src/stores/appStore.ts`

**Problem:** When clicking "Review Tags" in completion dialog, should auto-load the recently tagged files into RefineTab playlist.

**Step 1: Add recentlyTaggedFiles to appStore**

```typescript
// In appStore.ts interface
recentlyTaggedFiles: string[]
setRecentlyTaggedFiles: (files: string[]) => void
clearRecentlyTaggedFiles: () => void
```

**Step 2: Update TaggingView to store tagged file paths**

After tagging completes, call `setRecentlyTaggedFiles(taggedFilePaths)`.

**Step 3: Update handleReview to pass files**

```typescript
const handleReview = () => {
  const taggedFiles = files.filter(f => f.status === 'tagged').map(f => f.path)
  setRecentlyTaggedFiles(taggedFiles)
  setShowCompletionDialog(false)
  window.dispatchEvent(new CustomEvent('navigate-to-refine'))
}
```

**Step 4: Update RefineTab to auto-load on mount**

```typescript
// In RefineTab, useEffect on mount
useEffect(() => {
  const recentFiles = useAppStore.getState().recentlyTaggedFiles
  if (recentFiles.length > 0) {
    loadFiles(recentFiles)
    clearRecentlyTaggedFiles()
  }
}, [])
```

**Step 5: Add loadFiles to useRefinement hook**

Extend the hook to accept an array of file paths directly.

---

## Verification Plan

1. **Loading screen:** Run app, verify loading screen matches SetupWizard welcome style
2. **Model page:** Verify no horizontal line under helper text
3. **All Set screen:** Model name green, no mapping text, Vibes & Hooks green
4. **Header:** Model name shows correctly, no "(X genres)" text
5. **File states:** Add files, start tagging, verify:
   - Pending files show grey clock + grey "Pending"
   - Active file shows amber spinner + yellow "Processing"
   - Completed files show green check + green "Complete"
6. **Status bar:** During tagging, shows "X/Y files", "Xs/file", "ETA: Xm Xs"
7. **Review tags:** After tagging, click "Review Tags", verify files auto-load in RefineTab

---

## Summary of Changes

| File | Changes |
|------|---------|
| `desktop/index.html` | Loading screen redesign |
| `desktop/src/components/SetupWizard.tsx` | All Set screen summary redesign |
| `desktop/src/components/MainHeader.tsx` | Remove "(X genres)" from model display |
| `desktop/src/components/StatusBar.tsx` | Verify tagging stats display |
| `desktop/src/stores/appStore.ts` | Add recentlyTaggedFiles state |
| `desktop/src/components/TaggingView.tsx` | Store tagged files on completion |
| `desktop/src/hooks/useRefinement.ts` | Add loadFiles function |
| `desktop/src/components/RefineTab.tsx` | Auto-load on mount |
