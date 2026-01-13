import { useState, useEffect } from 'react'
import { FilePlus, Play, Square, Pause, AlertCircle, FolderPlus } from 'lucide-react'
import { motion } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'
import { useTagging } from '../hooks/useTagging'
import { FileQueue } from './FileQueue'
import { DropZone } from './DropZone'
import { CompletionDialog } from './CompletionDialog'
import { TaggingConfirmationDialog } from './TaggingConfirmationDialog'

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

export function TaggingView() {
  const { serverStatus, model, taggingPreferences } = useAppStore()
  const { dialog } = useElectron()

  const {
    files,
    isProcessing,
    isPaused,
    currentIndex,
    error,
    startTime,
    addFiles,
    removeFile,
    clearFiles,
    startTagging,
    stopTagging,
    pauseTagging,
    resumeTagging,
    retryFile,
    loadFromDirectory,
  } = useTagging()

  const handleSelectFiles = async () => {
    const selectedFiles = await dialog.openFiles({
      filters: [{ name: 'MP3 Files', extensions: ['mp3'] }],
    })
    if (selectedFiles.length === 0) {
      const directory = await dialog.openDirectory()
      if (directory) {
        await loadFromDirectory(directory)
      }
      return
    }

    const filePaths = selectedFiles.filter((path) => path.toLowerCase().endsWith('.mp3'))
    const dirPaths = selectedFiles.filter((path) => !path.toLowerCase().endsWith('.mp3'))

    if (filePaths.length > 0) {
      addFiles(filePaths)
    }
    for (const dirPath of dirPaths) {
      await loadFromDirectory(dirPath)
    }
  }

  const handleSelectDirectory = async () => {
    const directory = await dialog.openDirectory()
    if (directory) {
      await loadFromDirectory(directory)
    }
  }

  const handleStartTagging = () => {
    // Use preferences from store (new structure)
    startTagging({
      writeGenre: taggingPreferences.genre.enabled,
      genreTargetField: taggingPreferences.genre.targetField,
      writeAlbum: taggingPreferences.album.enabled,
      albumTargetField: taggingPreferences.album.targetField,
      writeMood: taggingPreferences.mood.enabled,
      moodTargetField: taggingPreferences.mood.targetField,
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

  const handleRetryFile = (path: string) => {
    retryFile(path, {
      writeGenre: taggingPreferences.genre.enabled,
      genreTargetField: taggingPreferences.genre.targetField,
      writeAlbum: taggingPreferences.album.enabled,
      albumTargetField: taggingPreferences.album.targetField,
      writeMood: taggingPreferences.mood.enabled,
      moodTargetField: taggingPreferences.mood.targetField,
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

  const isServerDisconnected = serverStatus !== 'connected'
  const canStart = !isServerDisconnected && model.loaded && files.length > 0 && !isProcessing

  const pendingCount = files.filter((f) => f.status === 'pending').length
  const taggedCount = files.filter((f) => f.status === 'tagged').length
  const failedCount = files.filter((f) => f.status === 'failed').length

  const [showCompletionDialog, setShowCompletionDialog] = useState(false)
  const [showConfirmDialog, setShowConfirmDialog] = useState(false)

  // Show completion dialog when tagging finishes
  useEffect(() => {
    // Only show when we have tagged files, no pending, and not currently processing
    if (!isProcessing && taggedCount > 0 && pendingCount === 0 && files.length > 0) {
      // Small delay to let the UI settle
      const timer = setTimeout(() => {
        setShowCompletionDialog(true)
      }, 500)
      return () => clearTimeout(timer)
    }
  }, [isProcessing, taggedCount, pendingCount, files.length])

  const handleReview = () => {
    // Store the tagged file paths for RefineTab to load
    const taggedFiles = files.filter(f => f.status === 'tagged').map(f => f.path)
    useAppStore.getState().setRecentlyTaggedFiles(taggedFiles)

    setShowCompletionDialog(false)
    window.dispatchEvent(new CustomEvent('navigate-to-refine'))
  }

  return (
    <DropZone onDrop={addFiles} disabled={isProcessing}>
      <motion.div
        variants={containerVariants}
        initial="hidden"
        animate="visible"
        className="p-8 h-full flex flex-col max-w-4xl mx-auto w-full"
      >
        {/* Drop Zone / Add Files Area */}
        {files.length === 0 ? (
          <motion.div
            variants={itemVariants}
            className="flex-1 flex flex-col items-center justify-center"
          >
            <div className="text-center mb-8">
              <h2 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
                Drop files to tag
              </h2>
              <p className="text-stone-500 dark:text-stone-400">
                Drag MP3 files or folders here, or use the buttons below
              </p>
            </div>

            <div className="flex gap-3">
              <button onClick={handleSelectFiles} className="btn btn-primary">
                <FilePlus className="w-4 h-4" />
                Add Files
              </button>
              <button onClick={handleSelectDirectory} className="btn btn-secondary">
                <FolderPlus className="w-4 h-4" />
                Add Folder
              </button>
            </div>
          </motion.div>
        ) : (
          <>
            {/* File Actions */}
            <motion.div variants={itemVariants} className="flex gap-3 mb-4">
              <button
                onClick={handleSelectFiles}
                disabled={isProcessing}
                className="btn btn-secondary"
              >
                <FilePlus className="w-4 h-4" />
                Add More
              </button>
              <button
                onClick={handleSelectDirectory}
                disabled={isProcessing}
                className="btn btn-secondary"
              >
                <FolderPlus className="w-4 h-4" />
                Add Folder
              </button>
            </motion.div>

            {/* File Queue */}
            <motion.div variants={itemVariants} className="flex-1 min-h-0">
              <FileQueue
                files={files}
                onRemove={isProcessing ? undefined : removeFile}
                onClear={isProcessing ? undefined : clearFiles}
                onRetry={isProcessing ? undefined : handleRetryFile}
                currentIndex={currentIndex}
                isProcessing={isProcessing}
                isPaused={isPaused}
                startTime={startTime}
              />
            </motion.div>

            {/* Error Message */}
            {error && (
              <motion.div
                variants={itemVariants}
                className="mt-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg flex items-start gap-2"
              >
                <AlertCircle className="w-4 h-4 text-red-500 flex-shrink-0 mt-0.5" />
                <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
              </motion.div>
            )}

            {/* Completion Summary */}
            {!isProcessing && taggedCount > 0 && (
              <motion.div
                variants={itemVariants}
                className="mt-4 card bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800"
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-emerald-100 dark:bg-emerald-800 rounded-full flex items-center justify-center">
                    <span className="text-emerald-600 dark:text-emerald-300 font-bold">
                      {taggedCount}
                    </span>
                  </div>
                  <div>
                    <p className="font-medium text-emerald-800 dark:text-emerald-200">
                      Files tagged successfully
                    </p>
                    {failedCount > 0 && (
                      <p className="text-sm text-emerald-700 dark:text-emerald-300">
                        {failedCount} failed - click to retry
                      </p>
                    )}
                  </div>
                </div>
              </motion.div>
            )}

            {/* Start/Control Buttons */}
            <motion.div
              variants={itemVariants}
              className="mt-6 pt-4 border-t border-border-light dark:border-border-dark"
            >
              {isProcessing ? (
                <div className="flex gap-3">
                  <button
                    onClick={isPaused ? resumeTagging : pauseTagging}
                    className="btn btn-secondary"
                  >
                    {isPaused ? (
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
                  <button onClick={stopTagging} className="btn btn-secondary">
                    <Square className="w-4 h-4" />
                    Stop
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => setShowConfirmDialog(true)}
                  disabled={!canStart}
                  className="btn btn-primary"
                >
                  <Play className="w-4 h-4" />
                  Start Tagging ({pendingCount} files)
                </button>
              )}
            </motion.div>
          </>
        )}
      </motion.div>

      {/* Completion Dialog */}
      <CompletionDialog
        isOpen={showCompletionDialog}
        onClose={() => setShowCompletionDialog(false)}
        onReview={handleReview}
        taggedCount={taggedCount}
        failedCount={failedCount}
      />

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
    </DropZone>
  )
}
