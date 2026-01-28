# Bug: Blank Screen When Clicking "Train Custom Model" in Setup Wizard

**Status:** UNRESOLVED
**Date:** 2026-01-10
**Severity:** Critical - blocks user flow

## Problem

When a user clicks "Train Custom Model" in the setup wizard (SetupWizard.tsx line 302), the app transitions to a blank screen instead of showing the TrainTab.

## Expected Behavior

User clicks "Train Custom Model" → Wizard closes → TrainTab appears with title, directory picker, model name input, and "Scan & Select Tags" button.

## Actual Behavior

User clicks "Train Custom Model" → Wizard closes → Blank screen (no content visible).

## Root Cause Analysis

The issue involves a race condition between React local state updates and Zustand store updates.

### The Flow

1. **SetupWizard.tsx:302** - User clicks "Train Custom Model"
2. Calls `completeSetup('train')`
3. **appStore.ts:269-271** - Sets `setupComplete = true` and `pendingView = 'train'` in Zustand
4. App.tsx re-renders because `setupComplete` changed
5. App no longer returns `<SetupWizard />` early
6. App renders main content

### The Problem

The `pendingView` needs to be consumed to set `advancedView` (local React state) to `'train'`. However:

1. When `clearPendingView()` updates Zustand, it triggers an immediate re-render
2. React's `setState` (for `advancedView`) is batched and may not be processed yet
3. This creates a render where `pendingView = null` AND `advancedView = 'none'`
4. Result: `effectiveView = 'none'` → TaggingView renders (or blank due to animation issues)

## Attempted Fixes

### Attempt 1: useLayoutEffect
Changed from `useEffect` to `useLayoutEffect` to update state synchronously before paint.
**Result:** Failed - still blank screen

### Attempt 2: Derived effectiveView
Computed `effectiveView` directly from `pendingView` during render:
```javascript
const effectiveView = (pendingView === 'train' ? 'train' : advancedView)
```
**Result:** Failed - race condition still occurs when clearing pendingView

### Attempt 3: Separated Effects
Split into two effects - one to sync state, one to clear pendingView only after state matches:
```javascript
useEffect(() => {
  if (pendingView) {
    setAdvancedViewState(pendingView)
  }
}, [pendingView])

useEffect(() => {
  if (pendingView && advancedView === pendingView) {
    clearPendingView()
  }
}, [pendingView, advancedView, clearPendingView])
```
**Result:** Failed - still blank screen

## Potential Causes Not Yet Investigated

1. **AnimatePresence mode="wait"** - May be causing animation issues during rapid state changes
2. **TrainTab internal animations** - Uses containerVariants with opacity 0 → 1, may not trigger
3. **CSS/Layout issue** - Content may render but be invisible due to styling
4. **React 18 concurrent features** - May cause unexpected batching behavior
5. **Framer Motion + Zustand interaction** - May have undocumented edge cases

## Files Involved

- `desktop/src/App.tsx` - Main app component with view switching logic
- `desktop/src/stores/appStore.ts` - Zustand store with `completeSetup`, `pendingView`, `clearPendingView`
- `desktop/src/components/SetupWizard.tsx` - Wizard with "Train Custom Model" button (line 302)
- `desktop/src/components/TrainTab.tsx` - The component that should render

## Related Issue: SDL2 Library Error

When opening the app, user reports: "Failed to Load SDL2 library"

This may be the **actual root cause** of the blank screen. If the Python backend fails to start:
1. Server status remains 'disconnected'
2. App behavior becomes undefined
3. TrainTab may not render properly

### SDL2 Investigation

- `pygame` is excluded in `cratebot_server.spec` (line 123)
- `python/src/core/audio_player.py` uses pygame but is NOT imported by the server
- SDL2 might be pulled in by: `laion-clap`, `soundfile`, or `librosa` dependencies
- Check if bundled `cratebot-server` binary has SDL2 issues on ARM64 macOS

### To Debug SDL2

1. Run the bundled server directly: `./desktop/resources/python/cratebot-server`
2. Check for SDL2 error output
3. If it fails, the React issue is secondary - fix the backend first

## Suggested Next Steps

1. **FIX SDL2 FIRST** - run bundled server directly to see the full error
2. **Add console.log debugging** to trace exact render sequence and state values
3. **Remove AnimatePresence temporarily** to see if animations are the issue
4. **Test without framer-motion** on TrainTab to isolate animation problems
5. **Move advancedView to Zustand** instead of local state to avoid React/Zustand sync issues
6. **Use React DevTools Profiler** to trace exactly what renders and when

## Current State of Code

App.tsx currently has:
- `effectiveView` derived from `pendingView` and `advancedView`
- Two separate useEffects for syncing state and clearing pendingView
- AnimatePresence with mode="wait" wrapping view transitions

The bug persists despite multiple fix attempts.
