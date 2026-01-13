# CrateBot3 Bug Fix Plan

**STATUS: ALL FIXES COMPLETED**

Based on the independent code review, this document outlines the fixes required for 6 major integration issues.

---

## Issue 1: WebSocket Progress Not Working

**Location:** `backend/api_server.py:900`

**Problem:** WebSocket progress handler defines `send_update` but never subscribes to task updates. TaskManager callbacks are sync-only, so clients only receive initial state and heartbeats, never real-time progress.

**Files to Modify:**
- `backend/api_server.py`
- `backend/task_manager.py`

**Fix Steps:**
1. Add async callback support to `TaskManager` for progress updates
2. Create a pub/sub mechanism or use `asyncio.Queue` for task progress events
3. In the WebSocket handler, subscribe to task progress updates
4. Forward progress events to connected WebSocket clients
5. Ensure cleanup of subscriptions when WebSocket disconnects

---

## Issue 2: Tag Scan API Contract Mismatch

**Location:** `backend/api_server.py:379`, `desktop/src/api/client.ts:232`, `python/src/core/tag_scanner.py:146`

**Problem:**
- Backend endpoint expects `directory` as a query parameter
- Frontend client sends JSON body
- Response returns `values` as list + `total_mp3s`
- UI expects `Record<string, number>` + `total_files`

**Files to Modify:**
- `backend/api_server.py`
- `desktop/src/api/client.ts`
- `python/src/core/tag_scanner.py` (optional, if response format needs changing at source)

**Fix Steps:**
1. Decide on API contract: either query param or JSON body (recommend JSON body for consistency)
2. Update backend endpoint to accept JSON body with `directory` field:
   ```python
   class ScanTagsRequest(BaseModel):
       directory: str
       recursive: bool = True
   ```
3. Update response format to match frontend expectations:
   ```python
   {
       "genre": {"values": {"Rock": 10, "Jazz": 5}},
       "album": {"values": {"Album1": 3}},
       "comments": {"values": {"Tag1": 2}},
       "total_files": 100
   }
   ```
4. Update `tag_scanner.py` to return `dict` instead of list for values
5. Rename `total_mp3s` to `total_files` in response

---

## Issue 3: Training Path Tilde Expansion

**Location:** `desktop/src/hooks/useTraining.ts:134`, `backend/api_server.py:500`

**Problem:** Frontend sends `~/.cratebot/models/...` without expanding the tilde. Backend saves to literal `~` folder instead of home directory.

**Files to Modify:**
- `backend/api_server.py`

**Fix Steps:**
1. Add path expansion in backend before saving:
   ```python
   import os
   output_path = os.path.expanduser(request.output_path)
   ```
2. Apply same expansion when loading/listing models
3. Add validation to ensure path is absolute after expansion
4. Consider also expanding paths in:
   - Model load endpoint
   - Model list endpoint
   - Any other path-handling endpoints

---

## Issue 4: Production Python Binary Mismatch

**Location:** `desktop/electron/main.ts:65`, `scripts/build.sh:50`

**Problem:** Build script creates standalone `cratebot-server` binary via PyInstaller, but Electron main process spawns `python3 run_server.py`. Packaged app fails on systems without Python installed.

**Files to Modify:**
- `desktop/electron/main.ts`

**Fix Steps:**
1. Detect if running in packaged mode (`app.isPackaged`)
2. In production, spawn the bundled `cratebot-server` binary:
   ```typescript
   const serverPath = isDev
     ? null  // Use python3 in dev
     : path.join(process.resourcesPath, 'cratebot-server')

   if (isDev) {
     pythonProcess = spawn('python3', [path.join(projectRoot, 'backend', 'run_server.py')])
   } else {
     pythonProcess = spawn(serverPath)
   }
   ```
3. Ensure `electron-builder` config includes `cratebot-server` in `extraResources`
4. Handle platform differences (`.exe` on Windows)
5. Add error handling if binary is missing

---

## Issue 5: Batch Tagging Options Ignored

**Location:** `backend/api_server.py:636`

**Problem:** `tag_batch` endpoint ignores `generate_vibes` and `generate_hooks` fields from `TaggingBatchRequest`. UI options have no effect.

**Files to Modify:**
- `backend/api_server.py`

**Fix Steps:**
1. Pass `generate_vibes` and `generate_hooks` to the batch processing logic:
   ```python
   result = auto_tagger.tag_file(
       file_path,
       overwrite=request.overwrite,
       dry_run=request.dry_run,
       generate_vibes=request.generate_vibes,  # Add this
       generate_hooks=request.generate_hooks,   # Add this
       ...
   )
   ```
2. Verify `AutoTagger.tag_file()` accepts and uses these parameters
3. If not, update `python/src/core/auto_tagger.py` to support vibe/hook generation
4. Add integration with `vibe_generator.py` and `hook_transcriber.py`

---

## Issue 6: Stop Button Doesn't Cancel Backend Task

**Location:** `desktop/src/hooks/useTagging.ts:73`, `backend/task_manager.py:222`

**Problem:**
- Stop button only stops UI polling
- Backend task continues running
- `file_paths` built from stale state after reset

**Files to Modify:**
- `desktop/src/hooks/useTagging.ts`
- `desktop/src/api/client.ts`
- `backend/api_server.py`

**Fix Steps:**
1. Add cancel endpoint for tagging tasks (if not exists):
   ```python
   @app.post("/api/v1/tag/cancel/{task_id}")
   async def cancel_tagging(task_id: str):
       task_manager.cancel_task(task_id)
       return {"status": "cancelled"}
   ```
2. Add client method:
   ```typescript
   cancelTagging: (taskId: string) =>
     request(`/api/v1/tag/cancel/${taskId}`, { method: 'POST' })
   ```
3. Update `stopTagging` in useTagging.ts to call cancel endpoint:
   ```typescript
   const stopTagging = useCallback(async () => {
     if (taskIdRef.current) {
       await api.cancelTagging(taskIdRef.current)
     }
     // ... existing cleanup
   }, [])
   ```
4. Fix stale state issue by capturing `files` before any state updates:
   ```typescript
   const startTagging = useCallback(async (options) => {
     const filesToProcess = state.files.filter(f => f.status === 'pending')
     // Use filesToProcess instead of state.files
   }, [state.files])
   ```

---

## Implementation Order

Recommended sequence based on dependencies and impact:

1. **Issue 3** - Path expansion (quick fix, no API changes)
2. **Issue 5** - Batch options (backend-only, straightforward)
3. **Issue 2** - Tag scan API (requires frontend+backend coordination)
4. **Issue 6** - Cancel functionality (requires new endpoint + frontend)
5. **Issue 1** - WebSocket progress (most complex, architectural change)
6. **Issue 4** - Production binary (requires build/packaging testing)

---

## Testing Checklist

- [ ] Tag scanning returns correct format and UI displays tags
- [ ] Training saves models to correct expanded path (`~/.cratebot/models/`)
- [ ] WebSocket shows real-time progress during training/tagging
- [ ] Stop button actually stops backend processing
- [ ] Vibe/hook generation works in batch mode
- [ ] Packaged app starts backend successfully without system Python

---

## Changes Made

### Issue 1: WebSocket Progress (FIXED)
- Updated `backend/task_manager.py`: Added async queue support with `subscribe_async()` and `unsubscribe_async()` methods
- Updated `_notify_progress()` to push updates to async queues using `call_soon_threadsafe`
- Updated `backend/api_server.py`: Rewrote `websocket_progress` to subscribe to async queues and forward updates to WebSocket clients

### Issue 2: Tag Scan API Contract (FIXED)
- Added `ScanTagsRequest` model to `backend/models/schemas.py`
- Updated `scan_tags` endpoint to accept JSON body instead of query param
- Added conversion logic to transform list of tuples to dict format
- Renamed `total_mp3s` to `total_files` in response

### Issue 3: Path Tilde Expansion (FIXED)
- Added `os.path.expanduser()` to training output path in `start_training`
- Added path expansion to `load_model` endpoint
- Added path expansion to `scan_tags` endpoint

### Issue 4: Production Binary Spawning (FIXED)
- Updated `desktop/electron/main.ts` to detect production mode
- In production, spawns bundled `cratebot-server` binary from `process.resourcesPath`
- Added fallback to python3 if binary not found

### Issue 5: Batch Tagging Options (FIXED)
- Updated `tag_batch` endpoint to check `generate_vibes` and `generate_hooks` flags
- Added initialization of `CachedVibeGenerator` and `CachedHookTranscriber` when requested
- Added vibe/hook generation calls after successful tagging

### Issue 6: Stop Button Cancellation (FIXED)
- Added `/api/v1/tag/cancel/{task_id}` endpoint to `backend/api_server.py`
- Added `cancelTagging` method to `desktop/src/api/client.ts`
- Updated `useTagging.ts` to:
  - Store taskId in a ref for access in stopTagging
  - Capture file paths before state reset to avoid stale state
  - Call cancel endpoint when stopping
