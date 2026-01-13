import { useState, useEffect } from 'react'
import { FolderOpen, Play, RotateCcw, Save, GraduationCap, FileText } from 'lucide-react'
import { motion } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { useElectron } from '../hooks/useElectron'
import { useTraining } from '../hooks/useTraining'
import { TagSelectionDialog } from './TagSelectionDialog'
import { TrainingProgress } from './TrainingProgress'
import { TrainingConsole } from './TrainingConsole'
import { TrainingCompletionDialog } from './TrainingCompletionDialog'

const LAST_MODEL_KEY = 'cratebot-last-model-name'

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

export function TrainTab() {
  const { serverStatus, model, settings, setToast } = useAppStore()
  const { dialog } = useElectron()

  const {
    status,
    phase,
    progress,
    currentFile,
    filesProcessed,
    totalFiles,
    samplesCollected,
    startTime,
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
  const [tagSources, setTagSources] = useState({
    genreFrame: 'TCON',
    timingFrame: '',
    moodFrame: 'TALB',
    commentsFrame: 'COMM',
  })
  const [showTagDialog, setShowTagDialog] = useState(false)
  const [showCompletionDialog, setShowCompletionDialog] = useState(false)

  useEffect(() => {
    if (modelName) {
      localStorage.setItem(LAST_MODEL_KEY, modelName)
    }
  }, [modelName])

  // Show completion dialog when training finishes
  useEffect(() => {
    if (status === 'completed' || status === 'failed' || status === 'cancelled') {
      // Small delay to let the UI settle
      const timer = setTimeout(() => {
        setShowCompletionDialog(true)
      }, 500)
      return () => clearTimeout(timer)
    }
  }, [status])

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
      const fullPath = files[0]
      const fileName = fullPath.split('/').pop() || ''
      const nameWithoutExt = fileName.replace(/\.pkl$/, '')
      setModelName(nameWithoutExt)
    }
  }

  const handleScanAndSelectTags = async () => {
    if (!trainingDir) return

    setShowTagDialog(true)
  }

  const handleStartTraining = async (selectedTags: { genre: string[]; timing: string[]; mood: string[]; descriptive: string[] }) => {
    setShowTagDialog(false)
    await startTraining(
      trainingDir,
      selectedTags,
      modelName,
      {
        genre_frame: tagSources.genreFrame || undefined,
        timing_frame: tagSources.timingFrame || undefined,
        mood_frame: tagSources.moodFrame || undefined,
        comments_frame: tagSources.commentsFrame || undefined,
      }
    )
  }

  const isServerDisconnected = serverStatus !== 'connected'
  const isIdle = status === 'idle'
  const isTraining = status === 'running' || status === 'paused'
  const isComplete = status === 'completed' || status === 'failed' || status === 'cancelled'

  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="p-8 max-w-4xl w-full"
    >
      <motion.div variants={itemVariants} className="mb-8">
        <h1 className="font-display text-2xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
          Train Model
        </h1>
        <p className="text-sm text-stone-500 dark:text-stone-400">
          Train a new tagging model from your organized music collection.
        </p>
      </motion.div>

      {/* Training Directory */}
      <motion.div variants={itemVariants} className="card mb-6">
        <CardHeader icon={FolderOpen} title="Training Directory" />
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
            className="btn btn-secondary"
          >
            <FolderOpen className="w-4 h-4" />
            Browse
          </button>
        </div>
        <p className="text-xs text-stone-500 dark:text-stone-400 mt-2">
          Select a folder containing MP3 files with existing Genre, Timing, Mood, and Comment tags.
        </p>
      </motion.div>

      {/* Model Name */}
      <motion.div variants={itemVariants} className="card mb-6">
        <CardHeader icon={FileText} title="Model Name" />
        <div className="flex gap-3 items-center">
          <input
            type="text"
            value={modelName}
            onChange={(e) => setModelName(e.target.value.replace(/[^a-zA-Z0-9_-]/g, ''))}
            placeholder="cratebot"
            className="input flex-1"
            disabled={isTraining}
          />
          <span className="text-sm text-stone-500 dark:text-stone-400">.pkl</span>
          <button
            onClick={handleBrowseModel}
            disabled={isTraining}
            className="btn btn-secondary"
          >
            <FolderOpen className="w-4 h-4" />
            Browse
          </button>
        </div>
        <p className="text-xs text-stone-500 dark:text-stone-400 mt-2">
          Model will be saved to {(settings.modelsDirectory || '~/.cratebot/models')}/{modelName || 'cratebot'}.pkl
        </p>
      </motion.div>

      {/* Current Model Info */}
      {model.loaded && model.selectedTags && isIdle && (
        <motion.div variants={itemVariants} className="card mb-6 border border-emerald-200 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-900/20">
          <CardHeader icon={GraduationCap} title="Current Model Loaded" />
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <span className="text-stone-500 dark:text-stone-400">Genre Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.genre.length}</span>
            </div>
            <div>
              <span className="text-stone-500 dark:text-stone-400">Timing Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.timing.length}</span>
            </div>
            <div>
              <span className="text-stone-500 dark:text-stone-400">Mood Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.mood.length}</span>
            </div>
            <div>
              <span className="text-stone-500 dark:text-stone-400">Comment Tags:</span>
              <span className="ml-2 font-medium">{model.selectedTags.descriptive.length}</span>
            </div>
          </div>
          <p className="text-xs text-stone-500 dark:text-stone-400 mt-3">
            Training a new model will not affect the current model until you load it.
          </p>
        </motion.div>
      )}

      {/* Training Actions (when idle) */}
      {isIdle && (
        <motion.div variants={itemVariants} className="flex gap-3">
          <button
            onClick={handleScanAndSelectTags}
            disabled={isServerDisconnected || !trainingDir || isScanning}
            className="btn btn-primary"
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
        </motion.div>
      )}

      {/* Training Progress */}
      {isTraining && (
        <motion.div variants={itemVariants} className="space-y-6">
          <TrainingProgress
            status={status as 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'}
            phase={phase}
            progress={progress}
            currentFile={currentFile || undefined}
            filesProcessed={filesProcessed}
            totalFiles={totalFiles}
            samplesCollected={samplesCollected}
            startTime={startTime}
            onCancel={cancelTraining}
          />

          <TrainingConsole logs={logs} onClear={clearLogs} />
        </motion.div>
      )}

      {/* Completed State */}
      {isComplete && (
        <motion.div variants={itemVariants} className="space-y-6">
          <TrainingProgress
            status={status as 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'}
            phase={phase}
            progress={progress}
            currentFile={currentFile || undefined}
            filesProcessed={filesProcessed}
            totalFiles={totalFiles}
            samplesCollected={samplesCollected}
            startTime={startTime}
            metrics={metrics || undefined}
            error={error || undefined}
          />
          <TrainingConsole logs={logs} onClear={clearLogs} />

          <div className="flex gap-3">
            <button onClick={reset} className="btn btn-secondary">
              <RotateCcw className="w-4 h-4" />
              Train Another
            </button>
            {status === 'completed' && (
              <button
                onClick={() => reset()}
                className="btn btn-primary"
              >
                <Save className="w-4 h-4" />
                Load Trained Model
              </button>
            )}
          </div>
        </motion.div>
      )}

      {/* Tag Selection Dialog */}
      <TagSelectionDialog
        isOpen={showTagDialog}
        onClose={() => setShowTagDialog(false)}
        onConfirm={handleStartTraining}
        discoveredTags={discoveredTags}
        isLoading={isScanning}
        tagSources={tagSources}
        onTagSourcesChange={setTagSources}
        onScan={async () => {
          try {
            const payload = {
              genre_frame: tagSources.genreFrame || undefined,
              timing_frame: tagSources.timingFrame || undefined,
              mood_frame: tagSources.moodFrame || undefined,
              comments_frame: tagSources.commentsFrame || undefined,
            }
            console.info('[training] Scan tags request', { directory: trainingDir, tag_sources: payload })
            const result = await scanDirectory(trainingDir, payload)
            console.info('[training] Scan tags result', {
              total_files: result.total_files,
              genre: Object.keys(result.genre?.values || {}).length,
              timing: Object.keys(result.timing?.values || {}).length,
              mood: Object.keys(result.mood?.values || {}).length,
              descriptive: Object.keys(result.descriptive?.values || {}).length,
            })
          } catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to scan directory'
            setToast(message, 'error')
          }
        }}
      />

      {/* Training Completion Dialog */}
      {isComplete && (
        <TrainingCompletionDialog
          isOpen={showCompletionDialog}
          onClose={() => setShowCompletionDialog(false)}
          status={status}
          filesProcessed={filesProcessed}
          filesSkipped={status === 'cancelled' ? totalFiles - filesProcessed : 0}
          filesFailed={status === 'failed' ? 1 : 0}
          totalFiles={totalFiles}
          samplesCollected={samplesCollected}
          metrics={metrics || undefined}
          error={error || undefined}
          onLoadModel={status === 'completed' ? () => {
            setShowCompletionDialog(false)
            // Model should auto-load, just close the dialog
          } : undefined}
          onTrainAnother={() => {
            setShowCompletionDialog(false)
            reset()
          }}
        />
      )}
    </motion.div>
  )
}
