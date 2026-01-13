# Frontend UI Updates Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align frontend UI with new backend Lexicon/Override systems and 4-field taxonomy

**Architecture:** Add API endpoints for lexicon and overrides, create LexiconEditor component, update RefineTab with save correction feature, and update TagEditor to show all 4 taxonomy fields.

**Tech Stack:** React 18.2, TypeScript, FastAPI, TailwindCSS

---

## Task 1: Add Lexicon API Endpoints to Backend

**Files:**
- Modify: `/Users/noahraford/CrateBot3/backend/api_server.py`

**Step 1: Add lexicon import and instance**

At the top of api_server.py, add import:
```python
from core.lexicon import Lexicon
```

In the initialization section (around line 50), add:
```python
lexicon = Lexicon()
```

**Step 2: Add GET /lexicon endpoint**

After the existing endpoints, add:
```python
@app.get("/lexicon")
async def get_lexicon():
    """Get current lexicon configuration."""
    return {
        "categories": {
            category: {
                "id3_frame": lexicon.get_id3_frame(category),
                "mappings": lexicon._lexicon.get(category, {}).get("mappings", {})
            }
            for category in ["genre", "timing", "mood", "descriptive"]
        }
    }
```

**Step 3: Add PUT /lexicon endpoint**

```python
class LexiconUpdate(BaseModel):
    category: str
    id3_frame: Optional[str] = None
    mappings: Optional[Dict[str, str]] = None

@app.put("/lexicon")
async def update_lexicon(update: LexiconUpdate):
    """Update lexicon configuration."""
    if update.id3_frame is not None:
        lexicon.set_id3_frame(update.category, update.id3_frame)
    if update.mappings is not None:
        for canonical, user_value in update.mappings.items():
            if user_value:
                lexicon.set_mapping(update.category, canonical, user_value)
            else:
                lexicon.remove_mapping(update.category, canonical)
    lexicon.save()
    return {"status": "ok"}
```

**Step 4: Verify endpoint works**

Run: `curl http://localhost:8742/lexicon`
Expected: JSON with categories object

**Step 5: Commit**

```bash
git add backend/api_server.py
git commit -m "feat: add lexicon API endpoints"
```

---

## Task 2: Add Override API Endpoints to Backend

**Files:**
- Modify: `/Users/noahraford/CrateBot3/backend/api_server.py`

**Step 1: Add override imports**

```python
from core.overrides import OverrideStore
from core.audio_hash import compute_audio_hash
```

In initialization:
```python
override_store = OverrideStore()
```

**Step 2: Add POST /override endpoint**

```python
class OverrideRequest(BaseModel):
    file_path: str
    tags: Dict[str, Any]

@app.post("/override")
async def save_override(request: OverrideRequest):
    """Save a per-track correction."""
    try:
        audio_hash = compute_audio_hash(request.file_path)
        override_store.set(audio_hash, request.tags)
        return {"status": "ok", "hash": audio_hash}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

**Step 3: Add GET /override endpoint**

```python
@app.get("/override/{file_path:path}")
async def get_override(file_path: str):
    """Get override for a file if it exists."""
    try:
        audio_hash = compute_audio_hash(file_path)
        tags = override_store.get(audio_hash)
        return {"has_override": tags is not None, "tags": tags, "hash": audio_hash}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

**Step 4: Verify endpoint works**

Run: `curl -X POST http://localhost:8742/override -H "Content-Type: application/json" -d '{"file_path": "/tmp/test.mp3", "tags": {"genre": "House"}}'`
Expected: JSON with status "ok" and hash

**Step 5: Commit**

```bash
git add backend/api_server.py
git commit -m "feat: add override API endpoints"
```

---

## Task 3: Update API Client with New Endpoints

**Files:**
- Modify: `/Users/noahraford/CrateBot3/desktop/src/api/client.ts`

**Step 1: Add lexicon types**

```typescript
export interface LexiconCategory {
  id3_frame: string
  mappings: Record<string, string>
}

export interface LexiconConfig {
  categories: {
    genre: LexiconCategory
    timing: LexiconCategory
    mood: LexiconCategory
    descriptive: LexiconCategory
  }
}

export interface LexiconUpdate {
  category: string
  id3_frame?: string
  mappings?: Record<string, string>
}
```

**Step 2: Add lexicon API methods**

```typescript
async getLexicon(): Promise<LexiconConfig> {
  const response = await fetch(`${this.baseUrl}/lexicon`)
  if (!response.ok) throw new Error('Failed to get lexicon')
  return response.json()
}

async updateLexicon(update: LexiconUpdate): Promise<void> {
  const response = await fetch(`${this.baseUrl}/lexicon`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(update)
  })
  if (!response.ok) throw new Error('Failed to update lexicon')
}
```

**Step 3: Add override types and methods**

```typescript
export interface OverrideResponse {
  has_override: boolean
  tags: Record<string, any> | null
  hash: string
}

async saveOverride(filePath: string, tags: Record<string, any>): Promise<{ status: string; hash: string }> {
  const response = await fetch(`${this.baseUrl}/override`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ file_path: filePath, tags })
  })
  if (!response.ok) throw new Error('Failed to save override')
  return response.json()
}

async getOverride(filePath: string): Promise<OverrideResponse> {
  const response = await fetch(`${this.baseUrl}/override/${encodeURIComponent(filePath)}`)
  if (!response.ok) throw new Error('Failed to get override')
  return response.json()
}
```

**Step 4: Commit**

```bash
git add desktop/src/api/client.ts
git commit -m "feat: add lexicon and override methods to API client"
```

---

## Task 4: Create LexiconEditor Component

**Files:**
- Create: `/Users/noahraford/CrateBot3/desktop/src/components/settings/LexiconEditor.tsx`

**Step 1: Create the component**

```tsx
/**
 * LexiconEditor Component
 * Allows users to customize vocabulary mappings and ID3 frame assignments.
 */
import { useState, useEffect } from 'react'
import { api, LexiconConfig, LexiconCategory } from '../../api/client'

const DEFAULT_FRAMES: Record<string, string> = {
  genre: 'TCON',
  timing: 'TALB',
  mood: 'TIT1',
  descriptive: 'COMM'
}

const CANONICAL_VALUES: Record<string, string[]> = {
  genre: ['House', 'Techno', 'Jungle/DnB', 'Rap', 'DiscoFunk', 'Breakbeat', 'Ambient', 'Dubstep', 'Trance'],
  timing: ['Start', 'Build', 'Peak', 'Sustain', 'Release'],
  mood: ['Happy', 'Dark', 'Emotional', 'Aggressive', 'Dreamy', 'Groovy'],
  descriptive: []
}

interface CategoryEditorProps {
  category: string
  label: string
  config: LexiconCategory
  onUpdate: (category: string, id3_frame?: string, mappings?: Record<string, string>) => void
}

function CategoryEditor({ category, label, config, onUpdate }: CategoryEditorProps) {
  const [editingMapping, setEditingMapping] = useState<string | null>(null)
  const [mappingValue, setMappingValue] = useState('')

  const handleFrameChange = (frame: string) => {
    onUpdate(category, frame)
  }

  const handleMappingEdit = (canonical: string) => {
    setEditingMapping(canonical)
    setMappingValue(config.mappings[canonical] || '')
  }

  const handleMappingSave = (canonical: string) => {
    const newMappings = { ...config.mappings }
    if (mappingValue.trim()) {
      newMappings[canonical] = mappingValue.trim()
    } else {
      delete newMappings[canonical]
    }
    onUpdate(category, undefined, newMappings)
    setEditingMapping(null)
  }

  const canonicals = CANONICAL_VALUES[category]

  return (
    <div className="border border-stone-200 dark:border-stone-700 rounded-lg p-4 mb-4">
      <h4 className="font-medium text-stone-800 dark:text-stone-200 mb-3 capitalize">{label}</h4>

      {/* ID3 Frame selector */}
      <div className="mb-4">
        <label className="block text-sm text-stone-600 dark:text-stone-400 mb-1">ID3 Frame</label>
        <select
          value={config.id3_frame}
          onChange={(e) => handleFrameChange(e.target.value)}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm"
        >
          <option value="TCON">TCON (Genre)</option>
          <option value="TALB">TALB (Album)</option>
          <option value="TIT1">TIT1 (Content Group)</option>
          <option value="COMM">COMM (Comments)</option>
          <option value={`TXXX:CRATEBOT_${category.toUpperCase()}`}>TXXX:CRATEBOT_{category.toUpperCase()} (Custom)</option>
        </select>
      </div>

      {/* Vocabulary mappings */}
      {canonicals.length > 0 && (
        <div>
          <label className="block text-sm text-stone-600 dark:text-stone-400 mb-2">Vocabulary Mappings</label>
          <div className="space-y-2">
            {canonicals.map(canonical => (
              <div key={canonical} className="flex items-center gap-2">
                <span className="w-24 text-sm text-stone-700 dark:text-stone-300">{canonical}</span>
                <span className="text-stone-400">→</span>
                {editingMapping === canonical ? (
                  <>
                    <input
                      type="text"
                      value={mappingValue}
                      onChange={(e) => setMappingValue(e.target.value)}
                      placeholder={canonical}
                      className="flex-1 px-2 py-1 text-sm bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                      onKeyDown={(e) => e.key === 'Enter' && handleMappingSave(canonical)}
                    />
                    <button
                      onClick={() => handleMappingSave(canonical)}
                      className="px-2 py-1 text-xs bg-green-600 text-white rounded hover:bg-green-700"
                    >
                      Save
                    </button>
                  </>
                ) : (
                  <>
                    <span className="flex-1 text-sm text-stone-600 dark:text-stone-400">
                      {config.mappings[canonical] || canonical}
                    </span>
                    <button
                      onClick={() => handleMappingEdit(canonical)}
                      className="px-2 py-1 text-xs text-stone-600 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200"
                    >
                      Edit
                    </button>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

export function LexiconEditor() {
  const [config, setConfig] = useState<LexiconConfig | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    loadLexicon()
  }, [])

  const loadLexicon = async () => {
    try {
      setLoading(true)
      const data = await api.getLexicon()
      setConfig(data)
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load lexicon')
    } finally {
      setLoading(false)
    }
  }

  const handleUpdate = async (category: string, id3_frame?: string, mappings?: Record<string, string>) => {
    if (!config) return
    try {
      await api.updateLexicon({ category, id3_frame, mappings })
      // Optimistic update
      setConfig(prev => {
        if (!prev) return prev
        return {
          ...prev,
          categories: {
            ...prev.categories,
            [category]: {
              id3_frame: id3_frame ?? prev.categories[category as keyof typeof prev.categories].id3_frame,
              mappings: mappings ?? prev.categories[category as keyof typeof prev.categories].mappings
            }
          }
        }
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update lexicon')
      loadLexicon() // Reload on error
    }
  }

  if (loading) {
    return <div className="text-stone-500 dark:text-stone-400">Loading lexicon...</div>
  }

  if (error) {
    return (
      <div className="text-red-500">
        {error}
        <button onClick={loadLexicon} className="ml-2 underline">Retry</button>
      </div>
    )
  }

  if (!config) return null

  return (
    <div>
      <p className="text-sm text-stone-600 dark:text-stone-400 mb-4">
        Customize tag vocabulary and ID3 frame assignments for each category.
      </p>
      <CategoryEditor category="genre" label="Genre" config={config.categories.genre} onUpdate={handleUpdate} />
      <CategoryEditor category="timing" label="Timing" config={config.categories.timing} onUpdate={handleUpdate} />
      <CategoryEditor category="mood" label="Mood" config={config.categories.mood} onUpdate={handleUpdate} />
      <CategoryEditor category="descriptive" label="Descriptive" config={config.categories.descriptive} onUpdate={handleUpdate} />
    </div>
  )
}
```

**Step 2: Commit**

```bash
git add desktop/src/components/settings/LexiconEditor.tsx
git commit -m "feat: add LexiconEditor component"
```

---

## Task 5: Update SettingsPanel with Lexicon Section

**Files:**
- Modify: `/Users/noahraford/CrateBot3/desktop/src/components/SettingsPanel.tsx`

**Step 1: Import LexiconEditor**

At the top of the file:
```typescript
import { LexiconEditor } from './settings/LexiconEditor'
```

**Step 2: Add Lexicon section**

Find the "Tagging Preferences" section and add after it:

```tsx
{/* Lexicon & Vocabulary */}
<div className="bg-white dark:bg-stone-800 rounded-lg shadow p-6">
  <h3 className="text-lg font-semibold text-stone-800 dark:text-stone-200 mb-4">
    Lexicon & Vocabulary
  </h3>
  <LexiconEditor />
</div>
```

**Step 3: Commit**

```bash
git add desktop/src/components/SettingsPanel.tsx
git commit -m "feat: add Lexicon section to Settings panel"
```

---

## Task 6: Update useRefinement Hook for New Taxonomy

**Files:**
- Modify: `/Users/noahraford/CrateBot3/desktop/src/hooks/useRefinement.ts`

**Step 1: Update RefinementItem interface**

Replace the originalTags and editedTags types:
```typescript
export interface RefinementItem {
  path: string
  name: string
  status: ItemStatus
  // Tags loaded from file
  originalTags: {
    genre?: string
    timing?: string
    mood?: string
    descriptive?: string[]
  }
  // User-edited tags (null if not edited)
  editedTags: {
    genre?: string
    timing?: string
    mood?: string
    descriptive?: string[]
  } | null
  // Confidence scores from prediction
  confidence?: {
    genre?: number
    timing?: number
    mood?: number
  }
  // Override saved for this track
  hasOverride?: boolean
}
```

**Step 2: Update AvailableTags interface**

```typescript
export interface AvailableTags {
  genre: string[]
  timing: string[]
  mood: string[]
  descriptive: string[]
}
```

**Step 3: Update loadTagsForItem function**

Replace the tags mapping:
```typescript
const loadTagsForItem = async (itemList: RefinementItem[], index: number) => {
  const item = itemList[index]
  if (!item || item.originalTags.genre !== undefined) {
    return // Already loaded
  }

  try {
    const response = await api.readTags(item.path)
    const tags = response.tags || {}

    // Check for override
    let hasOverride = false
    try {
      const overrideResponse = await api.getOverride(item.path)
      hasOverride = overrideResponse.has_override
    } catch {
      // Ignore override check errors
    }

    setItems(prev => {
      if (prev[index]?.path !== item.path) {
        return prev
      }
      const updated = [...prev]
      updated[index] = {
        ...updated[index],
        originalTags: {
          genre: tags.genre as string | undefined,
          timing: tags.timing as string | undefined,
          mood: tags.mood as string | undefined,
          descriptive: tags.descriptive ? (tags.descriptive as string).split(', ').filter(Boolean) : [],
        },
        hasOverride,
      }
      return updated
    })
  } catch (err) {
    console.warn(`Failed to load tags for ${item.name}:`, err)
  }
}
```

**Step 4: Update updateTags function**

```typescript
const updateTags = useCallback((tags: Partial<RefinementItem['editedTags']>) => {
  setItems(prev => {
    const updated = [...prev]
    const item = updated[currentIndex]
    if (item) {
      const currentEdited = item.editedTags || {
        genre: item.originalTags.genre,
        timing: item.originalTags.timing,
        mood: item.originalTags.mood,
        descriptive: item.originalTags.descriptive || [],
      }

      updated[currentIndex] = {
        ...item,
        editedTags: { ...currentEdited, ...tags },
        status: item.status === 'pending' ? 'corrected' : item.status,
      }
    }
    return updated
  })
}, [currentIndex])
```

**Step 5: Update approveAndNext function**

```typescript
const approveAndNext = useCallback(async () => {
  const item = items[currentIndex]
  if (!item) return

  const tagsToWrite = item.editedTags || {
    genre: item.originalTags.genre,
    timing: item.originalTags.timing,
    mood: item.originalTags.mood,
    descriptive: item.originalTags.descriptive || [],
  }

  try {
    await api.writeTags(item.path, {
      genre: tagsToWrite.genre,
      timing: tagsToWrite.timing,
      mood: tagsToWrite.mood,
      descriptive: Array.isArray(tagsToWrite.descriptive)
        ? tagsToWrite.descriptive.join(', ')
        : tagsToWrite.descriptive,
    })

    setItems(prev => {
      const updated = [...prev]
      updated[currentIndex] = {
        ...updated[currentIndex],
        status: 'approved',
      }
      return updated
    })

    nextItem()
  } catch (err) {
    setError(err instanceof Error ? err.message : 'Failed to save tags')
  }
}, [items, currentIndex, nextItem])
```

**Step 6: Add saveAsCorrection function**

Add to the hook:
```typescript
const saveAsCorrection = useCallback(async () => {
  const item = items[currentIndex]
  if (!item) return

  const tagsToSave = item.editedTags || {
    genre: item.originalTags.genre,
    timing: item.originalTags.timing,
    mood: item.originalTags.mood,
    descriptive: item.originalTags.descriptive || [],
  }

  try {
    await api.saveOverride(item.path, tagsToSave)

    setItems(prev => {
      const updated = [...prev]
      updated[currentIndex] = {
        ...updated[currentIndex],
        hasOverride: true,
      }
      return updated
    })
  } catch (err) {
    setError(err instanceof Error ? err.message : 'Failed to save correction')
  }
}, [items, currentIndex])
```

Add to return object:
```typescript
return {
  // ... existing
  saveAsCorrection,
}
```

**Step 7: Commit**

```bash
git add desktop/src/hooks/useRefinement.ts
git commit -m "feat: update useRefinement for new taxonomy and override support"
```

---

## Task 7: Update TagEditor for 4-Field Taxonomy

**Files:**
- Modify: `/Users/noahraford/CrateBot3/desktop/src/components/refine/TagEditor.tsx`

**Step 1: Update props interface**

```typescript
interface TagEditorProps {
  genre?: string
  timing?: string
  mood?: string
  descriptive?: string[]
  availableTags: {
    genre: string[]
    timing: string[]
    mood: string[]
    descriptive: string[]
  }
  onChange: (tags: { genre?: string; timing?: string; mood?: string; descriptive?: string[] }) => void
  disabled?: boolean
}
```

**Step 2: Replace component implementation**

Replace the full component with 4 fields:
```tsx
export function TagEditor({
  genre,
  timing,
  mood,
  descriptive = [],
  availableTags,
  onChange,
  disabled = false
}: TagEditorProps) {
  const handleGenreChange = (value: string) => {
    onChange({ genre: value, timing, mood, descriptive })
  }

  const handleTimingChange = (value: string) => {
    onChange({ genre, timing: value, mood, descriptive })
  }

  const handleMoodChange = (value: string) => {
    onChange({ genre, timing, mood: value, descriptive })
  }

  const handleDescriptiveToggle = (tag: string) => {
    const newDescriptive = descriptive.includes(tag)
      ? descriptive.filter(t => t !== tag)
      : [...descriptive, tag]
    onChange({ genre, timing, mood, descriptive: newDescriptive })
  }

  return (
    <div className="space-y-4">
      {/* Genre */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1">
          Genre
        </label>
        <select
          value={genre || ''}
          onChange={(e) => handleGenreChange(e.target.value)}
          disabled={disabled}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm disabled:opacity-50"
        >
          <option value="">Select genre...</option>
          {availableTags.genre.map(tag => (
            <option key={tag} value={tag}>{tag}</option>
          ))}
        </select>
      </div>

      {/* Timing */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1">
          Timing
        </label>
        <select
          value={timing || ''}
          onChange={(e) => handleTimingChange(e.target.value)}
          disabled={disabled}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm disabled:opacity-50"
        >
          <option value="">Select timing...</option>
          {availableTags.timing.map(tag => (
            <option key={tag} value={tag}>{tag}</option>
          ))}
        </select>
      </div>

      {/* Mood */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1">
          Mood
        </label>
        <select
          value={mood || ''}
          onChange={(e) => handleMoodChange(e.target.value)}
          disabled={disabled}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm disabled:opacity-50"
        >
          <option value="">Select mood...</option>
          {availableTags.mood.map(tag => (
            <option key={tag} value={tag}>{tag}</option>
          ))}
        </select>
      </div>

      {/* Descriptive Tags */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-2">
          Descriptive Tags
        </label>
        <div className="flex flex-wrap gap-2">
          {availableTags.descriptive.map(tag => (
            <button
              key={tag}
              type="button"
              onClick={() => handleDescriptiveToggle(tag)}
              disabled={disabled}
              className={`px-3 py-1 text-sm rounded-full border transition-colors ${
                descriptive.includes(tag)
                  ? 'bg-amber-500 text-white border-amber-500'
                  : 'bg-white dark:bg-stone-800 text-stone-700 dark:text-stone-300 border-stone-300 dark:border-stone-600 hover:border-amber-400'
              } disabled:opacity-50`}
            >
              {tag}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
```

**Step 3: Commit**

```bash
git add desktop/src/components/refine/TagEditor.tsx
git commit -m "feat: update TagEditor for 4-field taxonomy"
```

---

## Task 8: Add Save as Correction Button to RefineTab

**Files:**
- Modify: `/Users/noahraford/CrateBot3/desktop/src/components/refine/RefineTab.tsx`

**Step 1: Get saveAsCorrection from hook**

Update the destructuring from useRefinement:
```typescript
const {
  items,
  currentIndex,
  currentItem,
  availableTags,
  isLoading,
  error,
  stats,
  loadDirectory,
  loadFiles,
  selectItem,
  nextItem,
  prevItem,
  updateTags,
  approveAndNext,
  skipAndNext,
  clearSession,
  saveAsCorrection,
} = useRefinement()
```

**Step 2: Add Save as Correction button**

Find the action buttons section (near approveAndNext and skipAndNext buttons) and add:
```tsx
<button
  onClick={saveAsCorrection}
  disabled={!currentItem}
  className="px-4 py-2 text-sm font-medium text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg hover:bg-amber-100 dark:hover:bg-amber-900/30 disabled:opacity-50 disabled:cursor-not-allowed"
>
  {currentItem?.hasOverride ? '✓ Correction Saved' : 'Save as Correction'}
</button>
```

**Step 3: Update TagEditor usage**

Update the TagEditor call to use new props:
```tsx
<TagEditor
  genre={currentItem?.editedTags?.genre ?? currentItem?.originalTags?.genre}
  timing={currentItem?.editedTags?.timing ?? currentItem?.originalTags?.timing}
  mood={currentItem?.editedTags?.mood ?? currentItem?.originalTags?.mood}
  descriptive={currentItem?.editedTags?.descriptive ?? currentItem?.originalTags?.descriptive ?? []}
  availableTags={availableTags}
  onChange={updateTags}
  disabled={!currentItem}
/>
```

**Step 4: Commit**

```bash
git add desktop/src/components/refine/RefineTab.tsx
git commit -m "feat: add Save as Correction button to RefineTab"
```

---

## Task 9: Update Backend Tag Reading/Writing for New Taxonomy

**Files:**
- Modify: `/Users/noahraford/CrateBot3/backend/api_server.py`

**Step 1: Update read_tags endpoint**

Find the read_tags endpoint and update to return new taxonomy fields:
```python
@app.get("/tags/{file_path:path}")
async def read_tags(file_path: str):
    """Read tags from an audio file."""
    try:
        tags = tag_manager.read_tags(file_path, lexicon=lexicon)
        return {"tags": tags}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

**Step 2: Update write_tags endpoint**

Find the write_tags endpoint and update:
```python
@app.post("/tags/{file_path:path}")
async def write_tags(file_path: str, tags: Dict[str, Any] = Body(...)):
    """Write tags to an audio file."""
    try:
        tag_manager.write_tags(file_path, tags, lexicon=lexicon)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

**Step 3: Commit**

```bash
git add backend/api_server.py
git commit -m "feat: pass lexicon to tag read/write operations"
```

---

## Task 10: Run Tests and Verify

**Step 1: Run Python tests**

Run: `cd /Users/noahraford/CrateBot3/python && python -m pytest tests/ -v`
Expected: All tests pass

**Step 2: Run TypeScript type check**

Run: `cd /Users/noahraford/CrateBot3/desktop && npm run typecheck`
Expected: No type errors

**Step 3: Final commit**

If any adjustments were needed:
```bash
git add -A
git commit -m "fix: address test and type issues"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add Lexicon API endpoints | backend/api_server.py |
| 2 | Add Override API endpoints | backend/api_server.py |
| 3 | Update API client | desktop/src/api/client.ts |
| 4 | Create LexiconEditor component | desktop/src/components/settings/LexiconEditor.tsx |
| 5 | Add Lexicon to Settings | desktop/src/components/SettingsPanel.tsx |
| 6 | Update useRefinement hook | desktop/src/hooks/useRefinement.ts |
| 7 | Update TagEditor for 4 fields | desktop/src/components/refine/TagEditor.tsx |
| 8 | Add Save as Correction button | desktop/src/components/refine/RefineTab.tsx |
| 9 | Update backend tag operations | backend/api_server.py |
| 10 | Run tests and verify | - |
