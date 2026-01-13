import { useEffect, useState } from 'react'
import { FilePlus, Play, Square, Pause, AlertCircle, FolderOpen, Loader2, Disc3 } from 'lucide-react'
import { motion } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'
import { useTagging } from '../hooks/useTagging'
import { FileQueue } from './FileQueue'
import { DropZone } from './DropZone'
import { clsx } from 'clsx'

interface TaggingOptions {
  writeGenre: boolean
  genreTargetField: string
  writeAlbum: boolean
  albumTargetField: string
  writeMood: boolean
  moodTargetField: string
  writeComments: boolean
  commentsTargetField: string
  writeLikeness: boolean
  likenessTargetField: string
  generateVibes: boolean
  vibesShortTargetField: string
  vibesLongTargetField: string
  detectHooks: boolean
  hooksTargetField: string
  overwrite: boolean
}

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

function CardHeader({ icon: Icon, title }: { icon: any; title: string }) {
  return (
    <div className="flex items-center gap-2.5 mb-4">
      <div className="w-8 h-8 rounded-lg bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
        <Icon className="w-4 h-4 text-amber-600 dark:text-amber-400" />
      </div>
      <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">
        {title}
      </h2>
    </div>
  )
}

export function TagTab() {
  const { serverStatus, model, settings, loadModel, setToast } = useAppStore()
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

  const [options, setOptions] = useState<TaggingOptions>({
    writeGenre: true,
    genreTargetField: 'TCON',
    writeAlbum: true,
    albumTargetField: 'TALB',
    writeMood: true,
    moodTargetField: 'TIT1',
    writeComments: true,
    commentsTargetField: 'COMM',
    writeLikeness: true,
    likenessTargetField: 'TIT1',
    generateVibes: settings.vibeAvailable,
    vibesShortTargetField: 'TXXX:CRATEBOT_VIBE_SHORT',
    vibesLongTargetField: 'COMM',
    detectHooks: settings.hookAvailable,
    hooksTargetField: 'TXXX:CRATEBOT_HOOK',
    overwrite: true,
  })

  const [modelPath, setModelPath] = useState('')
  const [modelLoading, setModelLoading] = useState(false)
  const [modelError, setModelError] = useState<string | null>(null)

  useEffect(() => {
    setOptions((prev) => ({
      ...prev,
      generateVibes: prev.generateVibes && settings.vibeAvailable,
      detectHooks: prev.detectHooks && settings.hookAvailable,
    }))
  }, [settings.vibeAvailable, settings.hookAvailable])

  useEffect(() => {
    if (model.path && !modelPath) {
      setModelPath(model.path)
    }
  }, [model.path, modelPath])

  const handleLoadModel = async (path: string) => {
    if (!path) return
    setModelLoading(true)
    setModelError(null)
    try {
      await loadModel(path)
      setToast('Model loaded', 'success')
    } catch (error) {
      setModelError(error instanceof Error ? error.message : 'Failed to load model')
    } finally {
      setModelLoading(false)
    }
  }

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

  const handleBrowseModel = async () => {
    const files = await dialog.openFiles({
      filters: [{ name: 'Model Files', extensions: ['pkl'] }],
    })
    if (files.length > 0) {
      setModelPath(files[0])
      await handleLoadModel(files[0])
    }
  }

  const handleStartTagging = () => {
    startTagging(options)
  }

  const handleRetryFile = (path: string) => {
    retryFile(path, options)
  }

  const update = (key: keyof TaggingOptions, value: boolean) => {
    setOptions({ ...options, [key]: value })
  }

  const isServerDisconnected = serverStatus !== 'connected'
  const canStart = !isServerDisconnected && model.loaded && files.length > 0 && !isProcessing

  const pendingCount = files.filter((f) => f.status === 'pending').length
  const taggedCount = files.filter((f) => f.status === 'tagged').length
  const failedCount = files.filter((f) => f.status === 'failed').length

  return (
    <DropZone onDrop={addFiles} disabled={isProcessing}>
      <motion.div
        variants={containerVariants}
        initial="hidden"
        animate="visible"
        className="p-8 h-full flex flex-col max-w-4xl w-full"
      >
        {/* Header */}
        <motion.div variants={itemVariants} className="mb-8">
          <h1 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
            Tag Files
          </h1>
          <p className="text-sm text-stone-500 dark:text-stone-400">
            Apply ML-predicted tags and AI-generated vibes to your music.
          </p>
        </motion.div>

        {/* Model Selector */}
        <motion.div variants={itemVariants} className="card mb-6">
          <CardHeader icon={Disc3} title="Model" />
          <div className="flex gap-3 items-center">
            <input
              type="text"
              value={modelPath}
              placeholder="Select a model to use for tagging..."
              className="input flex-1"
              disabled={true}
              readOnly
            />
            <button
              onClick={handleBrowseModel}
              disabled={isProcessing || modelLoading}
              className="btn btn-secondary"
            >
              {modelLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Loading
                </>
              ) : (
                <>
                  <FolderOpen className="w-4 h-4" />
                  Browse
                </>
              )}
            </button>
          </div>
          {modelError && (
            <p className="text-xs text-red-600 dark:text-red-400 mt-2">
              {modelError}
            </p>
          )}
          {model.loaded && model.selectedTags && (
            <p className="text-xs text-stone-500 dark:text-stone-400 mt-2">
              {model.selectedTags.genre.length} genres, {model.selectedTags.timing.length} timing, {model.selectedTags.mood.length} moods, {model.selectedTags.descriptive.length} comments
            </p>
          )}
          {!model.loaded && serverStatus === 'connected' && (
            <p className="text-xs text-amber-600 dark:text-amber-400 mt-2">
              Train a new model or browse to select an existing one.
            </p>
          )}
        </motion.div>

        {/* Tagging Options */}
        <motion.div variants={itemVariants} className="card mb-6">
          <CardHeader icon={Disc3} title="Tagging Options" />
          <div className="grid grid-cols-2 md:grid-cols-3 gap-x-6 gap-y-3">
            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              isProcessing && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeGenre}
                onChange={(e) => update('writeGenre', e.target.checked)}
                disabled={isProcessing}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Genre</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              isProcessing && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeAlbum}
                onChange={(e) => update('writeAlbum', e.target.checked)}
                disabled={isProcessing}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Timing</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              isProcessing && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeMood}
                onChange={(e) => update('writeMood', e.target.checked)}
                disabled={isProcessing}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Mood</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              isProcessing && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeComments}
                onChange={(e) => update('writeComments', e.target.checked)}
                disabled={isProcessing}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Comments (Descriptive)</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              isProcessing && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeLikeness}
                onChange={(e) => update('writeLikeness', e.target.checked)}
                disabled={isProcessing}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Likeness Scores</span>
            </label>

            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              (isProcessing || !settings.vibeAvailable) && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.generateVibes}
                onChange={(e) => update('generateVibes', e.target.checked)}
                disabled={isProcessing || !settings.vibeAvailable}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Generate Vibes</span>
              {!settings.vibeAvailable && (
                <span className="badge badge-warning text-xs">{settings.vibeStatus}</span>
              )}
            </label>
            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              (isProcessing || !settings.hookAvailable) && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.detectHooks}
                onChange={(e) => update('detectHooks', e.target.checked)}
                disabled={isProcessing || !settings.hookAvailable}
                className="checkbox"
              />
              <span className="text-sm text-stone-700 dark:text-stone-300 group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">Detect Hooks</span>
              {!settings.hookAvailable && (
                <span className="badge badge-neutral text-xs">{settings.hookStatus}</span>
              )}
            </label>

            <div className="col-span-full border-t border-border-light dark:border-border-dark my-1" />

            <label className={clsx(
              'flex items-center gap-2.5 cursor-pointer group',
              isProcessing && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.overwrite}
                onChange={(e) => update('overwrite', e.target.checked)}
                disabled={isProcessing}
                className="checkbox"
              />
              <span className="text-sm font-semibold text-stone-700 dark:text-stone-300">Overwrite existing</span>
            </label>
          </div>
        </motion.div>

        {/* Add Files */}
        <motion.div variants={itemVariants} className="flex gap-3 mb-4">
          <button
            onClick={handleSelectFiles}
            disabled={isProcessing}
            className="btn btn-secondary"
          >
            <FilePlus className="w-4 h-4" />
            Add Files
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

        {/* Start Tagging */}
        <motion.div
          variants={itemVariants}
          className="mt-6 pt-4 border-t border-border-light dark:border-border-dark sticky bottom-0 bg-surface-light dark:bg-surface-dark -mx-8 px-8 pb-4"
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
              onClick={handleStartTagging}
              disabled={!canStart}
              className="btn btn-primary"
            >
              <Play className="w-4 h-4" />
              Start Tagging ({pendingCount} files)
            </button>
          )}
        </motion.div>
      </motion.div>
    </DropZone>
  )
}
