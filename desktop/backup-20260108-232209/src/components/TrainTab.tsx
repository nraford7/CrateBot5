import { useState, useEffect } from 'react'
import { FolderOpen, Play, RotateCcw, Save } from 'lucide-react'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'
import { useTraining } from '../hooks/useTraining'
import { TagSelectionDialog } from './TagSelectionDialog'
import { TrainingProgress } from './TrainingProgress'
import { TrainingConsole } from './TrainingConsole'

const LAST_MODEL_KEY = 'cratebot-last-model-name'

export function TrainTab() {
  const { serverStatus, model, settings } = useAppStore()
  const { dialog } = useElectron()

  const {
    status,
    phase,
    progress,
    currentFile,
    filesProcessed,
    totalFiles,
    samplesCollected,
    metrics,
    error,
    logs,
    discoveredTags,
    isScanning,
    scanDirectory,
    startTraining,
    cancelTraining,
    clearLogs,
    reset,
  } = useTraining()

  const [trainingDir, setTrainingDir] = useState('')
  const [modelName, setModelName] = useState(() => {
    return localStorage.getItem(LAST_MODEL_KEY) || 'cratebot'
  })
  const [showTagDialog, setShowTagDialog] = useState(false)

  // Persist model name
  useEffect(() => {
    if (modelName) {
      localStorage.setItem(LAST_MODEL_KEY, modelName)
    }
  }, [modelName])

  const handleSelectDirectory = async () => {
    const dir = await dialog.openDirectory()
    if (dir) {
      setTrainingDir(dir)
    }
  }

  const handleBrowseModel = async () => {
    const files = await dialog.openFiles({
      filters: [{ name: 'Model Files', extensions: ['pkl'] }],
    })
    if (files.length > 0) {
      // Extract model name from path (without extension)
      const fullPath = files[0]
      const fileName = fullPath.split('/').pop() || ''
      const nameWithoutExt = fileName.replace(/\.pkl$/, '')
      setModelName(nameWithoutExt)
    }
  }

  const handleScanAndSelectTags = async () => {
    if (!trainingDir) return

    try {
      await scanDirectory(trainingDir)
      setShowTagDialog(true)
    } catch (error) {
      // Error is already logged
    }
  }

  const handleStartTraining = async (selectedTags: { genre: string[]; album: string[]; comments: string[] }) => {
    setShowTagDialog(false)
    await startTraining(trainingDir, selectedTags, modelName)
  }

  const isServerDisconnected = serverStatus !== 'connected'
  const isIdle = status === 'idle'
  const isTraining = status === 'running' || status === 'paused'
  const isComplete = status === 'completed' || status === 'failed' || status === 'cancelled'

  return (
    <div className="p-6 max-w-4xl w-full">
      <div className="mb-8">
        <h1 className="text-2xl font-semibold text-gray-900 dark:text-white mb-2">
          Train Model
        </h1>
        <p className="text-muted">
          Train a new tagging model from your organized music collection.
        </p>
      </div>

      {/* Training Directory */}
      <div className="card mb-6">
        <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-4">
          Training Directory
        </h2>
        <div className="flex gap-3">
          <input
            type="text"
            value={trainingDir}
            onChange={(e) => setTrainingDir(e.target.value)}
            placeholder="Select a directory with tagged MP3s..."
            className="input flex-1"
            disabled={isTraining}
          />
          <button
            onClick={handleSelectDirectory}
            disabled={isTraining}
            className="btn btn-secondary flex items-center gap-2"
          >
            <FolderOpen className="w-4 h-4" />
            Browse
          </button>
        </div>
        <p className="text-sm text-muted mt-2 text-left">
          Select a folder containing MP3 files with existing Genre, Album, and Comment tags.
        </p>
      </div>

      {/* Model Name */}
      <div className="card mb-6">
        <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-4">
          Model Name
        </h2>
        <div className="flex gap-3 items-center">
          <input
            type="text"
            value={modelName}
            onChange={(e) => setModelName(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ''))}
            placeholder="cratebot"
            className="input flex-1"
            disabled={isTraining}
          />
          <span className="text-sm text-muted">.pkl</span>
          <button
            onClick={handleBrowseModel}
            disabled={isTraining}
            className="btn btn-secondary flex items-center gap-2"
          >
            <FolderOpen className="w-4 h-4" />
            Browse
          </button>
        </div>
        <p className="text-sm text-muted mt-2 text-left">
          Model will be saved to {(settings.modelsDirectory || '~/.cratebot/models')}/{modelName || 'cratebot'}.pkl
        </p>
      </div>

      {/* Current Model Info */}
      {model.loaded && model.selectedTags && isIdle && (
        <div className="card mb-6 border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-900/20">
          <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-4">
            Current Model Loaded
          </h2>
          <div className="grid grid-cols-3 gap-4 text-sm">
            <div>
              <span className="text-muted">Genre Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.genre.length}</span>
            </div>
            <div>
              <span className="text-muted">Album Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.album.length}</span>
            </div>
            <div>
              <span className="text-muted">Comment Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.comments.length}</span>
            </div>
          </div>
          <p className="text-sm text-muted mt-3 text-left">
            Training a new model will not affect the current model until you load it.
          </p>
        </div>
      )}

      {/* Training Actions (when idle) */}
      {isIdle && (
        <div className="flex gap-3">
          <button
            onClick={handleScanAndSelectTags}
            disabled={isServerDisconnected || !trainingDir || isScanning}
            className="btn btn-primary flex items-center gap-2"
          >
            {isScanning ? (
              <>
                <span className="animate-spin">⏳</span>
                Scanning...
              </>
            ) : (
              <>
                <Play className="w-4 h-4" />
                Scan & Select Tags
              </>
            )}
          </button>
        </div>
      )}

      {/* Training Progress */}
      {isTraining && (
        <div className="space-y-6">
          <TrainingProgress
            status={status as 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'}
            phase={phase}
            progress={progress}
            currentFile={currentFile || undefined}
            filesProcessed={filesProcessed}
            totalFiles={totalFiles}
            samplesCollected={samplesCollected}
            onCancel={cancelTraining}
          />
          <TrainingConsole logs={logs} onClear={clearLogs} />
        </div>
      )}

      {/* Completed State */}
      {isComplete && (
        <div className="space-y-6">
          <TrainingProgress
            status={status as 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'}
            phase={phase}
            progress={progress}
            currentFile={currentFile || undefined}
            filesProcessed={filesProcessed}
            totalFiles={totalFiles}
            samplesCollected={samplesCollected}
            metrics={metrics || undefined}
            error={error || undefined}
          />
          <TrainingConsole logs={logs} onClear={clearLogs} />

          <div className="flex gap-3">
            <button
              onClick={reset}
              className="btn btn-secondary flex items-center gap-2"
            >
              <RotateCcw className="w-4 h-4" />
              Train Another
            </button>
            {status === 'completed' && (
              <button
                onClick={() => {
                  // Will load the newly trained model
                  // For now just reset
                  reset()
                }}
                className="btn btn-primary flex items-center gap-2"
              >
                <Save className="w-4 h-4" />
                Load Trained Model
              </button>
            )}
          </div>
        </div>
      )}

      {/* Tag Selection Dialog */}
      <TagSelectionDialog
        isOpen={showTagDialog}
        onClose={() => setShowTagDialog(false)}
        onConfirm={handleStartTraining}
        discoveredTags={discoveredTags}
        isLoading={isScanning}
      />
    </div>
  )
}
