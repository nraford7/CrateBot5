/**
 * useRefinement Hook
 * Manages refinement session state, tag editing, and API integration.
 */
import { useState, useCallback, useEffect } from 'react'
import { api } from '../api/client'

export type ItemStatus = 'pending' | 'approved' | 'corrected' | 'skipped'

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

export interface AvailableTags {
  genre: string[]
  timing: string[]
  mood: string[]
  descriptive: string[]
}

interface UseRefinementReturn {
  // State
  items: RefinementItem[]
  currentIndex: number
  currentItem: RefinementItem | null
  availableTags: AvailableTags
  isLoading: boolean
  error: string | null

  // Stats
  stats: {
    total: number
    approved: number
    corrected: number
    skipped: number
    pending: number
  }

  // Actions
  loadDirectory: (dirPath: string) => Promise<void>
  loadFiles: (filePaths: string[]) => Promise<void>
  selectItem: (index: number) => void
  nextItem: () => void
  prevItem: () => void
  updateTags: (tags: Partial<RefinementItem['editedTags']>) => void
  approveAndNext: () => Promise<void>
  skipAndNext: () => void
  clearSession: () => void
  saveAsCorrection: () => Promise<void>
}

export function useRefinement(): UseRefinementReturn {
  const [items, setItems] = useState<RefinementItem[]>([])
  const [currentIndex, setCurrentIndex] = useState<number>(0)
  const [availableTags, setAvailableTags] = useState<AvailableTags>({
    genre: [],
    timing: [],
    mood: [],
    descriptive: [],
  })
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Load available tags from model on mount
  useEffect(() => {
    async function loadModelTags() {
      try {
        const modelInfo = await api.getModelInfo()
        if (modelInfo.selected_tags) {
          // Type assertion for new taxonomy fields with fallback to old field names
          const tags = modelInfo.selected_tags as Record<string, string[] | undefined>
          setAvailableTags({
            genre: tags.genre || [],
            timing: tags.timing || tags.album || [],
            mood: tags.mood || [],
            descriptive: tags.descriptive || tags.comments || [],
          })
        }
      } catch (err) {
        console.warn('Could not load model tags:', err)
      }
    }
    loadModelTags()
  }, [])

  const currentItem = items[currentIndex] || null

  // Calculate stats
  const stats = {
    total: items.length,
    approved: items.filter(i => i.status === 'approved').length,
    corrected: items.filter(i => i.status === 'corrected').length,
    skipped: items.filter(i => i.status === 'skipped').length,
    pending: items.filter(i => i.status === 'pending').length,
  }

  // Load directory and read tags for all files
  const loadDirectory = useCallback(async (dirPath: string) => {
    setIsLoading(true)
    setError(null)

    try {
      // Find all MP3s
      const result = await api.findMp3s(dirPath)

      // Create items with pending status
      const newItems: RefinementItem[] = result.files.map(f => ({
        path: f.path,
        name: f.name,
        status: 'pending' as ItemStatus,
        originalTags: {},
        editedTags: null,
      }))

      setItems(newItems)
      setCurrentIndex(0)

      // Load tags for first item immediately
      if (newItems.length > 0) {
        await loadTagsForItem(newItems, 0)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load directory')
    } finally {
      setIsLoading(false)
    }
  }, [])

  // Load specific files by path array
  const loadFiles = useCallback(async (filePaths: string[]) => {
    if (filePaths.length === 0) return

    setIsLoading(true)
    setError(null)

    try {
      // Create items with pending status
      const newItems: RefinementItem[] = filePaths.map(filePath => ({
        path: filePath,
        name: filePath.split(/[/\\]/).pop() || filePath,
        status: 'pending' as ItemStatus,
        originalTags: {},
        editedTags: null,
      }))

      setItems(newItems)
      setCurrentIndex(0)

      // Load tags for first item immediately
      if (newItems.length > 0) {
        await loadTagsForItem(newItems, 0)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load files')
    } finally {
      setIsLoading(false)
    }
  }, [])

  // Load tags for a specific item
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

      // Guard against race condition - verify item still matches before updating
      setItems(prev => {
        // Check if the item at this index still has the same path
        if (prev[index]?.path !== item.path) {
          // Item changed during async operation, skip update
          return prev
        }
        const updated = [...prev]
        updated[index] = {
          ...updated[index],
          originalTags: {
            genre: tags.genre as string | undefined,
            timing: tags.timing as string | undefined,
            mood: tags.mood as string | undefined,
            descriptive: tags.descriptive
              ? (typeof tags.descriptive === 'string' ? tags.descriptive.split(', ').filter(Boolean) : tags.descriptive as string[])
              : [],
          },
          hasOverride,
        }
        return updated
      })
    } catch (err) {
      console.warn(`Failed to load tags for ${item.name}:`, err)
    }
  }

  // Select item by index
  const selectItem = useCallback((index: number) => {
    if (index >= 0 && index < items.length) {
      setCurrentIndex(index)
      loadTagsForItem(items, index)
    }
  }, [items])

  // Navigate to next item
  const nextItem = useCallback(() => {
    const next = Math.min(currentIndex + 1, items.length - 1)
    setCurrentIndex(next)
    loadTagsForItem(items, next)
  }, [currentIndex, items])

  // Navigate to previous item
  const prevItem = useCallback(() => {
    const prev = Math.max(currentIndex - 1, 0)
    setCurrentIndex(prev)
    loadTagsForItem(items, prev)
  }, [currentIndex, items])

  // Update tags for current item
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

  // Approve current item and save tags, then move to next
  const approveAndNext = useCallback(async () => {
    const item = items[currentIndex]
    if (!item) return

    // Determine tags to write
    const tagsToWrite = item.editedTags || {
      genre: item.originalTags.genre,
      timing: item.originalTags.timing,
      mood: item.originalTags.mood,
      descriptive: item.originalTags.descriptive || [],
    }

    try {
      // Write tags to file
      await api.writeTags(item.path, {
        genre: tagsToWrite.genre,
        timing: tagsToWrite.timing,
        mood: tagsToWrite.mood,
        descriptive: Array.isArray(tagsToWrite.descriptive)
          ? tagsToWrite.descriptive.join(', ')
          : tagsToWrite.descriptive,
      })

      // Update status to approved
      setItems(prev => {
        const updated = [...prev]
        updated[currentIndex] = {
          ...updated[currentIndex],
          status: 'approved',
        }
        return updated
      })

      // Move to next
      nextItem()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save tags')
    }
  }, [items, currentIndex, nextItem])

  // Skip current item and move to next
  const skipAndNext = useCallback(() => {
    setItems(prev => {
      const updated = [...prev]
      if (updated[currentIndex]) {
        updated[currentIndex] = {
          ...updated[currentIndex],
          status: 'skipped',
        }
      }
      return updated
    })
    nextItem()
  }, [currentIndex, nextItem])

  // Clear session
  const clearSession = useCallback(() => {
    setItems([])
    setCurrentIndex(0)
    setError(null)
  }, [])

  // Save current tags as a correction/override for future predictions
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

  return {
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
  }
}
