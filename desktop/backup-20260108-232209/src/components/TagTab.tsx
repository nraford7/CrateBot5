import { useEffect, useState } from 'react'
import { FilePlus, Play, Square, AlertCircle, FolderOpen, Loader2 } from 'lucide-react'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'
import { useTagging } from '../hooks/useTagging'
import { FileQueue } from './FileQueue'
import { DropZone } from './DropZone'
import { clsx } from 'clsx'

interface TaggingOptions {
  writeGenre: boolean
  writeAlbum: boolean
  writeComments: boolean
  writeLikeness: boolean
  generateVibes: boolean
  detectHooks: boolean
  overwrite: boolean
}

export function TagTab() {
  const { serverStatus, model, settings, loadModel, setToast } = useAppStore()
  const { dialog } = useElectron()

  const {
    files,
    isProcessing,
    currentIndex,
    error,
    addFiles,
    removeFile,
    clearFiles,
    startTagging,
    stopTagging,
    retryFile,
    loadFromDirectory,
  } = useTagging()

  const [options, setOptions] = useState<TaggingOptions>({
    writeGenre: true,
    writeAlbum: true,
    writeComments: true,
    writeLikeness: true,
    generateVibes: settings.vibeAvailable,
    detectHooks: settings.hookAvailable,
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

  // Count stats
  const pendingCount = files.filter((f) => f.status === 'pending').length
  const taggedCount = files.filter((f) => f.status === 'tagged').length
  const failedCount = files.filter((f) => f.status === 'failed').length

  return (
    <DropZone onDrop={addFiles} disabled={isProcessing}>
      <div className="p-6 h-full flex flex-col max-w-4xl w-full">
        <div className="w-full flex-1 flex flex-col">
          {/* Header */}
          <div className="mb-6">
            <h1 className="text-2xl font-semibold text-gray-900 dark:text-white mb-2">
              Tag Files
            </h1>
            <p className="text-sm text-muted text-left">
              Apply ML-predicted tags and AI-generated vibes to your music.
            </p>
          </div>

          {/* Model Selector */}
          <div className="card mb-6">
            <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-3">
              Model
            </h2>
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
                className="btn btn-secondary flex items-center gap-2 min-w-[120px] justify-center"
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
              <p className="text-xs text-red-600 dark:text-red-400 mt-2 text-left">
                {modelError}
              </p>
            )}
            {model.loaded && model.selectedTags && (
              <p className="text-xs text-muted mt-2 text-left">
                {model.selectedTags.genre.length} genres, {model.selectedTags.album.length} albums, {model.selectedTags.comments.length} comments
              </p>
            )}
            {!model.loaded && serverStatus === 'connected' && (
              <p className="text-xs text-amber-600 dark:text-amber-400 mt-2 text-left">
                Train a new model or browse to select an existing one.
              </p>
            )}
          </div>

          {/* Tagging Options - Compact Grid */}
          <div className="card mb-6">
            <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-3">
              Tagging Options
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-x-6 gap-y-3">
              {/* ML Tags */}
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                isProcessing && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.writeGenre}
                  onChange={(e) => update('writeGenre', e.target.checked)}
                  disabled={isProcessing}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white">Genre</span>
              </label>
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                isProcessing && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.writeAlbum}
                  onChange={(e) => update('writeAlbum', e.target.checked)}
                  disabled={isProcessing}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white">Album (Mood)</span>
              </label>
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                isProcessing && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.writeComments}
                  onChange={(e) => update('writeComments', e.target.checked)}
                  disabled={isProcessing}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white">Comments</span>
              </label>
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                isProcessing && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.writeLikeness}
                  onChange={(e) => update('writeLikeness', e.target.checked)}
                  disabled={isProcessing}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white">Likeness Scores</span>
              </label>

              {/* AI Features */}
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                (isProcessing || !settings.vibeAvailable) && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.generateVibes}
                  onChange={(e) => update('generateVibes', e.target.checked)}
                  disabled={isProcessing || !settings.vibeAvailable}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white">Generate Vibes</span>
                {!settings.vibeAvailable && (
                  <span className="text-xs text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 px-1.5 py-0.5 rounded">
                    {settings.vibeStatus}
                  </span>
                )}
              </label>
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                (isProcessing || !settings.hookAvailable) && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.detectHooks}
                  onChange={(e) => update('detectHooks', e.target.checked)}
                  disabled={isProcessing || !settings.hookAvailable}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white">Detect Hooks</span>
                {!settings.hookAvailable && (
                  <span className="text-xs text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-800 px-1.5 py-0.5 rounded">
                    {settings.hookStatus}
                  </span>
                )}
              </label>

              <div className="col-span-full border-t border-border dark:border-border-dark my-1" />

              {/* Overwrite */}
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer',
                isProcessing && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.overwrite}
                  onChange={(e) => update('overwrite', e.target.checked)}
                  disabled={isProcessing}
                  className="rounded border-border text-accent focus:ring-accent"
                />
                <span className="text-sm text-gray-900 dark:text-white font-semibold">Overwrite existing</span>
              </label>
            </div>
          </div>

          {/* Add Files */}
          <div className="flex gap-3 mb-4">
            <button
              onClick={handleSelectFiles}
              disabled={isProcessing}
              className="btn btn-secondary flex items-center gap-2"
            >
              <FilePlus className="w-4 h-4" />
              Add Files
            </button>
          </div>

          {/* File Queue */}
          <div className="flex-1 min-h-0">
            <FileQueue
              files={files}
              onRemove={isProcessing ? undefined : removeFile}
              onClear={isProcessing ? undefined : clearFiles}
              onRetry={isProcessing ? undefined : handleRetryFile}
              currentIndex={currentIndex}
              isProcessing={isProcessing}
            />
          </div>

          {/* Error Message */}
          {error && (
            <div className="mt-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-red-500 flex-shrink-0 mt-0.5" />
              <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
            </div>
          )}

          {/* Completion Summary */}
          {!isProcessing && taggedCount > 0 && (
            <div className="mt-4 card bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-green-100 dark:bg-green-800 rounded-full flex items-center justify-center">
                  <span className="text-green-600 dark:text-green-300 font-bold">
                    {taggedCount}
                  </span>
                </div>
                <div>
                  <p className="font-medium text-green-800 dark:text-green-200">
                    Files tagged successfully
                  </p>
                  {failedCount > 0 && (
                    <p className="text-sm text-green-700 dark:text-green-300">
                      {failedCount} failed - click to retry
                    </p>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Start Tagging - Fixed at bottom */}
          <div className="mt-6 pt-4 border-t border-border dark:border-border-dark sticky bottom-0 bg-surface dark:bg-surface-dark -mx-6 px-6 pb-4">
            {isProcessing ? (
              <button
                onClick={stopTagging}
                className="btn btn-secondary flex items-center gap-2"
              >
                <Square className="w-4 h-4" />
                Stop
              </button>
            ) : (
              <button
                onClick={handleStartTagging}
                disabled={!canStart}
                className="btn btn-primary flex items-center gap-2"
              >
                <Play className="w-4 h-4" />
                Start Tagging ({pendingCount} files)
              </button>
            )}
          </div>
        </div>
      </div>
    </DropZone>
  )
}
