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
    album?: string
    comments?: string
    vibe?: string
    description?: string
    hook?: string
  }
  // User-edited tags (null if not edited)
  editedTags: {
    genre?: string
    album?: string
    comments?: string[]
    vibe?: string
    description?: string
  } | null
  // Confidence scores from prediction
  confidence?: {
    genre?: number
    album?: number
  }
}

export interface AvailableTags {
  genre: string[]
  album: string[]
  comments: string[]
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
  selectItem: (index: number) => void
  nextItem: () => void
  prevItem: () => void
  updateTags: (tags: Partial<RefinementItem['editedTags']>) => void
  approveAndNext: () => Promise<void>
  skipAndNext: () => void
  clearSession: () => void
}

export function useRefinement(): UseRefinementReturn {
  const [items, setItems] = useState<RefinementItem[]>([])
  const [currentIndex, setCurrentIndex] = useState<number>(0)
  const [availableTags, setAvailableTags] = useState<AvailableTags>({
    genre: [],
    album: [],
    comments: [],
  })
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Load available tags from model on mount
  useEffect(() => {
    async function loadModelTags() {
      try {
        const modelInfo = await api.getModelInfo()
        if (modelInfo.selected_tags) {
          setAvailableTags({
            genre: modelInfo.selected_tags.genre || [],
            album: modelInfo.selected_tags.album || [],
            comments: modelInfo.selected_tags.comments || [],
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

  // Load tags for a specific item
  const loadTagsForItem = async (itemList: RefinementItem[], index: number) => {
    const item = itemList[index]
    if (!item || item.originalTags.genre !== undefined) {
      return // Already loaded
    }

    try {
      const response = await api.readTags(item.path)
      const tags = response.tags || {}

      setItems(prev => {
        const updated = [...prev]
        updated[index] = {
          ...updated[index],
          originalTags: {
            genre: tags.genre as string | undefined,
            album: tags.album as string | undefined,
            comments: tags.comments as string | undefined,
            vibe: (tags.composer || tags.vibe) as string | undefined,
            description: tags.description as string | undefined,
            hook: (tags.work || tags.hook) as string | undefined,
          },
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
          album: item.originalTags.album,
          comments: item.originalTags.comments?.split(', ').filter(Boolean) || [],
          vibe: item.originalTags.vibe,
          description: item.originalTags.description,
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
      album: item.originalTags.album,
      comments: item.originalTags.comments?.split(', ').filter(Boolean) || [],
      vibe: item.originalTags.vibe,
      description: item.originalTags.description,
    }

    try {
      // Write tags to file
      await api.writeTags(item.path, {
        genre: tagsToWrite.genre,
        album: tagsToWrite.album,
        comments: Array.isArray(tagsToWrite.comments)
          ? tagsToWrite.comments.join(', ')
          : tagsToWrite.comments,
        composer: tagsToWrite.vibe, // Vibe stored in composer field
        description: tagsToWrite.description,
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

  return {
    items,
    currentIndex,
    currentItem,
    availableTags,
    isLoading,
    error,
    stats,
    loadDirectory,
    selectItem,
    nextItem,
    prevItem,
    updateTags,
    approveAndNext,
    skipAndNext,
    clearSession,
  }
}
