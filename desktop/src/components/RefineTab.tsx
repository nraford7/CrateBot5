/**
 * RefineTab Component - Redesigned
 * Tag refinement workflow with audio playback and tag editing.
 */
import { useState, useCallback, useEffect } from 'react'
import { Music, Check, SkipForward, Loader2 } from 'lucide-react'
import { motion } from 'framer-motion'
import { useElectron } from '../hooks/useElectron'
import { useRefinement } from '../hooks/useRefinement'
import { useAppStore } from '../stores/appStore'
import {
  AudioPlayer,
  TagEditor,
  PlaylistPanel,
} from './refine'

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.08, delayChildren: 0.1 },
  },
}

const itemVariants = {
  hidden: { opacity: 0, y: 15 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.4, ease: [0.4, 0, 0.2, 1] as const } },
}

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

  const [isSaving, setIsSaving] = useState(false)

  // Auto-load recently tagged files when navigating from "Review Tags"
  useEffect(() => {
    const { recentlyTaggedFiles, clearRecentlyTaggedFiles } = useAppStore.getState()
    if (recentlyTaggedFiles.length > 0) {
      // Only clear after successful load
      loadFiles(recentlyTaggedFiles).then(() => {
        clearRecentlyTaggedFiles()
      }).catch(() => {
        // Keep files in store for retry on error
        console.error('Failed to auto-load recently tagged files')
      })
    }
  }, [loadFiles])

  // Handle directory selection
  const handleLoadDirectory = useCallback(async () => {
    const dir = await dialog.openDirectory()
    if (dir) {
      await loadDirectory(dir)
    }
  }, [dialog, loadDirectory])

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
      <div className="flex-1 flex flex-col min-w-0 bg-surface-light dark:bg-surface-dark">
        {isLoading ? (
          <div className="flex-1 flex items-center justify-center">
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="text-center"
            >
              <Loader2 className="w-8 h-8 mx-auto mb-3 animate-spin text-amber-500" />
              <p className="text-stone-500 dark:text-stone-400">Loading files...</p>
            </motion.div>
          </div>
        ) : error ? (
          <div className="flex-1 flex items-center justify-center">
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="text-center p-6"
            >
              <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center">
                <span className="text-red-500 text-xl">!</span>
              </div>
              <p className="font-medium text-red-600 dark:text-red-400">Error</p>
              <p className="text-sm text-red-500 dark:text-red-400/80 mt-1">{error}</p>
            </motion.div>
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
            <motion.div
              variants={containerVariants}
              initial="hidden"
              animate="visible"
              className="flex-1 overflow-auto p-6"
            >
              {/* Track Name */}
              <motion.h2
                variants={itemVariants}
                className="text-lg font-display font-semibold text-stone-900 dark:text-stone-100 mb-6 truncate"
              >
                {currentItem.name}
              </motion.h2>

              <div className="space-y-6">
                {/* Genre & Album */}
                <motion.div variants={itemVariants}>
                  <TagEditor
                    genre={currentItem?.editedTags?.genre ?? currentItem?.originalTags?.genre}
                    timing={currentItem?.editedTags?.timing ?? currentItem?.originalTags?.timing}
                    mood={currentItem?.editedTags?.mood ?? currentItem?.originalTags?.mood}
                    descriptive={currentItem?.editedTags?.descriptive ?? currentItem?.originalTags?.descriptive ?? []}
                    availableTags={availableTags}
                    onChange={updateTags}
                    disabled={!currentItem}
                  />
                </motion.div>

              </div>

              {/* Action Buttons */}
              <motion.div variants={itemVariants} className="mt-8 flex gap-3">
                <motion.button
                  onClick={handleApprove}
                  disabled={isSaving}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="btn btn-primary"
                >
                  {isSaving ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Check className="w-4 h-4" />
                  )}
                  Approve & Next
                </motion.button>
                <motion.button
                  onClick={skipAndNext}
                  disabled={isSaving}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="btn btn-secondary"
                >
                  <SkipForward className="w-4 h-4" />
                  Skip
                </motion.button>
                <button
                  onClick={saveAsCorrection}
                  disabled={!currentItem}
                  className="px-4 py-2 text-sm font-medium text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg hover:bg-amber-100 dark:hover:bg-amber-900/30 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {currentItem?.hasOverride ? 'Correction Saved' : 'Save as Correction'}
                </button>
              </motion.div>
            </motion.div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5 }}
              className="text-center"
            >
              <div className="w-20 h-20 mx-auto mb-6 rounded-2xl bg-surface-sunken dark:bg-surface-dark-sunken flex items-center justify-center">
                <Music className="w-10 h-10 text-stone-300 dark:text-stone-600" />
              </div>
              <p className="text-stone-600 dark:text-stone-400 font-medium">Select a track to edit tags</p>
              <p className="text-sm text-stone-400 dark:text-stone-500 mt-2">
                or load a directory to start a refinement session
              </p>
            </motion.div>
          </div>
        )}
      </div>
    </div>
  )
}
