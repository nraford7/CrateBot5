/**
 * TrainingProgress Component - Redesigned
 * Training progress display with metrics
 */
import { CheckCircle2, XCircle, Pause, Play, Square, Disc3 } from 'lucide-react'
import { motion } from 'framer-motion'
import { clsx } from 'clsx'
import { formatTime } from '../utils/formatTime'

interface TrainingProgressProps {
  status: 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'
  phase: string
  progress: number
  currentFile?: string
  filesProcessed: number
  totalFiles: number
  samplesCollected: number
  startTime?: number | null
  metrics?: {
    genreAccuracy?: number
    timingAccuracy?: number
    moodAccuracy?: number
    descriptiveF1?: number
  }
  error?: string
  onPause?: () => void
  onResume?: () => void
  onCancel?: () => void
}

const phaseLabels: Record<string, string> = {
  idle: 'Preparing...',
  scanning: 'Scanning directory',
  collecting: 'Extracting features',
  training: 'Training model',
  saving: 'Saving model',
  complete: 'Training complete',
}

const statusConfig = {
  running: { color: 'text-amber-500', bgColor: 'bg-amber-100 dark:bg-amber-900/30', progressColor: 'bg-amber-500' },
  paused: { color: 'text-amber-500', bgColor: 'bg-amber-100 dark:bg-amber-900/30', progressColor: 'bg-amber-500' },
  completed: { color: 'text-emerald-500', bgColor: 'bg-emerald-100 dark:bg-emerald-900/30', progressColor: 'bg-emerald-500' },
  failed: { color: 'text-red-500', bgColor: 'bg-red-100 dark:bg-red-900/30', progressColor: 'bg-red-500' },
  cancelled: { color: 'text-stone-500', bgColor: 'bg-stone-100 dark:bg-stone-800', progressColor: 'bg-stone-500' },
}

export function TrainingProgress({
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
  onPause,
  onResume,
  onCancel,
}: TrainingProgressProps) {
  const isActive = status === 'running' || status === 'paused'
  const config = statusConfig[status]

  // Calculate time estimates
  const elapsedSeconds = startTime ? (Date.now() - startTime) / 1000 : 0
  const avgTimePerFile = filesProcessed > 0 ? elapsedSeconds / filesProcessed : 0
  const remainingFiles = totalFiles - filesProcessed
  const etaSeconds = avgTimePerFile * remainingFiles

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="card"
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-3">
          <div className={clsx('w-10 h-10 rounded-xl flex items-center justify-center', config.bgColor)}>
            {status === 'running' && (
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
              >
                <Disc3 className={clsx('w-5 h-5', config.color)} />
              </motion.div>
            )}
            {status === 'paused' && (
              <Pause className={clsx('w-5 h-5', config.color)} />
            )}
            {status === 'completed' && (
              <CheckCircle2 className={clsx('w-5 h-5', config.color)} />
            )}
            {(status === 'failed' || status === 'cancelled') && (
              <XCircle className={clsx('w-5 h-5', config.color)} />
            )}
          </div>
          <div>
            <h3 className="font-display font-semibold text-stone-900 dark:text-stone-100">
              {phaseLabels[phase] || phase}
            </h3>
            {currentFile && status === 'running' && (
              <p className="text-sm text-stone-500 dark:text-stone-400 truncate max-w-md">
                {currentFile}
              </p>
            )}
          </div>
        </div>

        {/* Controls */}
        {isActive && (
          <div className="flex gap-2">
            {status === 'running' && onPause && (
              <motion.button
                onClick={onPause}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className="btn btn-ghost p-2"
                title="Pause"
              >
                <Pause className="w-4 h-4" />
              </motion.button>
            )}
            {status === 'paused' && onResume && (
              <motion.button
                onClick={onResume}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className="btn btn-ghost p-2"
                title="Resume"
              >
                <Play className="w-4 h-4" />
              </motion.button>
            )}
            {onCancel && (
              <motion.button
                onClick={onCancel}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className="btn btn-ghost p-2 text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
                title="Cancel"
              >
                <Square className="w-4 h-4" />
              </motion.button>
            )}
          </div>
        )}
      </div>

      {/* Progress Bar */}
      <div className="mb-5">
        <div className="flex justify-between text-sm mb-2">
          <span className="text-stone-500 dark:text-stone-400">Progress</span>
          <span className="font-medium text-stone-700 dark:text-stone-300">{progress.toFixed(0)}%</span>
        </div>
        <div className="progress-track h-2.5">
          <motion.div
            className={clsx('h-full rounded-full', config.progressColor)}
            initial={{ width: 0 }}
            animate={{ width: `${progress}%` }}
            transition={{ duration: 0.5, ease: 'easeOut' }}
          />
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-4 gap-4">
        <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
          <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">Files</div>
          <div className="font-display font-semibold text-stone-900 dark:text-stone-100">
            {filesProcessed} <span className="text-stone-400 font-normal">/ {totalFiles}</span>
          </div>
        </div>
        <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
          <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">Samples</div>
          <div className="font-display font-semibold text-stone-900 dark:text-stone-100">
            {samplesCollected.toLocaleString()}
          </div>
        </div>
        <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
          <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">Time/File</div>
          <div className="font-display font-semibold text-stone-900 dark:text-stone-100">
            {avgTimePerFile > 0 ? `${avgTimePerFile.toFixed(1)}s` : '-'}
          </div>
        </div>
        <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
          <div className="text-xs text-stone-500 dark:text-stone-400 mb-1">ETA</div>
          <div className={clsx('font-display font-semibold', config.color)}>
            {remainingFiles > 0 && avgTimePerFile > 0 ? formatTime(etaSeconds) : status}
          </div>
        </div>
      </div>

      {/* Metrics (after training) */}
      {metrics && status === 'completed' && (
        <motion.div
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: 'auto' }}
          className="mt-5 pt-5 border-t border-border-light dark:border-border-dark"
        >
          <h4 className="text-sm font-medium text-stone-900 dark:text-stone-100 mb-4">
            Training Metrics
          </h4>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {metrics.genreAccuracy !== undefined && (
              <div className="p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800">
                <div className="text-xs text-emerald-600 dark:text-emerald-400 mb-1">Genre Accuracy</div>
                <div className="font-display font-bold text-xl text-emerald-600 dark:text-emerald-400">
                  {(metrics.genreAccuracy * 100).toFixed(1)}%
                </div>
              </div>
            )}
            {metrics.timingAccuracy !== undefined && (
              <div className="p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800">
                <div className="text-xs text-emerald-600 dark:text-emerald-400 mb-1">Timing Accuracy</div>
                <div className="font-display font-bold text-xl text-emerald-600 dark:text-emerald-400">
                  {(metrics.timingAccuracy * 100).toFixed(1)}%
                </div>
              </div>
            )}
            {metrics.moodAccuracy !== undefined && (
              <div className="p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800">
                <div className="text-xs text-emerald-600 dark:text-emerald-400 mb-1">Mood Accuracy</div>
                <div className="font-display font-bold text-xl text-emerald-600 dark:text-emerald-400">
                  {(metrics.moodAccuracy * 100).toFixed(1)}%
                </div>
              </div>
            )}
            {metrics.descriptiveF1 !== undefined && (
              <div className="p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800">
                <div className="text-xs text-emerald-600 dark:text-emerald-400 mb-1">Comments F1</div>
                <div className="font-display font-bold text-xl text-emerald-600 dark:text-emerald-400">
                  {(metrics.descriptiveF1 * 100).toFixed(1)}%
                </div>
              </div>
            )}
          </div>
        </motion.div>
      )}

      {/* Error Message */}
      {error && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="mt-5 p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl"
        >
          <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
        </motion.div>
      )}
    </motion.div>
  )
}
