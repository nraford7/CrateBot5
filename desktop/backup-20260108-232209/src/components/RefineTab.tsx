/**
 * RefineTab Component
 * Tag refinement workflow with audio playback and tag editing.
 */
import { useState, useCallback, useMemo } from 'react'
import { Music, Check, SkipForward, Loader2 } from 'lucide-react'
import { useElectron } from '../hooks/useElectron'
import { useRefinement } from '../hooks/useRefinement'
import {
  AudioPlayer,
  TagEditor,
  CommentTagGrid,
  VibeEditor,
  PlaylistPanel,
} from './refine'

export function RefineTab() {
  const { dialog } = useElectron()
  const {
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
  } = useRefinement()

  const [isSaving, setIsSaving] = useState(false)

  // Handle directory selection
  const handleLoadDirectory = useCallback(async () => {
    const dir = await dialog.openDirectory()
    if (dir) {
      await loadDirectory(dir)
    }
  }, [dialog, loadDirectory])

  // Get current tag values (edited or original)
  const currentTags = useMemo(() => {
    if (!currentItem) {
      return {
        genre: '',
        album: '',
        comments: [] as string[],
        vibe: '',
        description: '',
      }
    }

    if (currentItem.editedTags) {
      return {
        genre: currentItem.editedTags.genre || '',
        album: currentItem.editedTags.album || '',
        comments: currentItem.editedTags.comments || [],
        vibe: currentItem.editedTags.vibe || '',
        description: currentItem.editedTags.description || '',
      }
    }

    // Parse comments from comma-separated string
    const commentsStr = currentItem.originalTags.comments || ''
    const comments = commentsStr
      .split(',')
      .map((c) => c.trim())
      .filter(Boolean)

    return {
      genre: currentItem.originalTags.genre || '',
      album: currentItem.originalTags.album || '',
      comments,
      vibe: currentItem.originalTags.vibe || '',
      description: currentItem.originalTags.description || '',
    }
  }, [currentItem])

  // Handle approve and save
  const handleApprove = useCallback(async () => {
    setIsSaving(true)
    try {
      await approveAndNext()
    } finally {
      setIsSaving(false)
    }
  }, [approveAndNext])

  return (
    <div className="flex h-full">
      {/* Playlist Panel (Left Sidebar) */}
      <PlaylistPanel
        items={items}
        selectedIndex={currentIndex}
        stats={stats}
        onSelectItem={selectItem}
        onLoadDirectory={handleLoadDirectory}
        onClearSession={clearSession}
      />

      {/* Editor Panel (Right) */}
      <div className="flex-1 flex flex-col min-w-0">
        {isLoading ? (
          <div className="flex-1 flex items-center justify-center">
            <div className="text-center">
              <Loader2 className="w-8 h-8 mx-auto mb-2 animate-spin text-accent" />
              <p className="text-muted">Loading files...</p>
            </div>
          </div>
        ) : error ? (
          <div className="flex-1 flex items-center justify-center">
            <div className="text-center text-red-500">
              <p className="font-medium">Error</p>
              <p className="text-sm">{error}</p>
            </div>
          </div>
        ) : currentItem ? (
          <>
            {/* Audio Player */}
            <AudioPlayer
              filePath={currentItem.path}
              onPrev={prevItem}
              onNext={nextItem}
              hasPrev={currentIndex > 0}
              hasNext={currentIndex < items.length - 1}
            />

            {/* Tag Editor */}
            <div className="flex-1 overflow-auto p-6">
              {/* Track Name */}
              <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-4 truncate">
                {currentItem.name}
              </h2>

              <div className="space-y-6">
                {/* Genre & Album */}
                <TagEditor
                  genre={currentTags.genre}
                  album={currentTags.album}
                  genreOptions={availableTags.genre}
                  albumOptions={availableTags.album}
                  genreConfidence={currentItem.confidence?.genre}
                  albumConfidence={currentItem.confidence?.album}
                  onGenreChange={(value) => updateTags({ genre: value })}
                  onAlbumChange={(value) => updateTags({ album: value })}
                />

                {/* Comment Tags */}
                <CommentTagGrid
                  availableTags={availableTags.comments}
                  selectedTags={currentTags.comments}
                  onChange={(tags) => updateTags({ comments: tags })}
                />

                {/* Vibe & Description */}
                <VibeEditor
                  vibe={currentTags.vibe}
                  description={currentTags.description}
                  hook={currentItem.originalTags.hook}
                  onVibeChange={(value) => updateTags({ vibe: value })}
                  onDescriptionChange={(value) =>
                    updateTags({ description: value })
                  }
                />
              </div>

              {/* Action Buttons */}
              <div className="mt-6 flex gap-3">
                <button
                  onClick={handleApprove}
                  disabled={isSaving}
                  className="btn btn-primary flex items-center gap-2"
                >
                  {isSaving ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Check className="w-4 h-4" />
                  )}
                  Approve & Next
                </button>
                <button
                  onClick={skipAndNext}
                  disabled={isSaving}
                  className="btn btn-secondary flex items-center gap-2"
                >
                  <SkipForward className="w-4 h-4" />
                  Skip
                </button>
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-muted">
            <div className="text-center">
              <Music className="w-12 h-12 mx-auto mb-4 opacity-30" />
              <p>Select a track to edit tags</p>
              <p className="text-sm mt-1">
                or load a directory to start a refinement session
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
