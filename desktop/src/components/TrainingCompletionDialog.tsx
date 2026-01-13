/**
 * TrainingCompletionDialog
 * Shows training results with success/fail counts and error details.
 */
import { CheckCircle2, XCircle, AlertTriangle, X } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'

interface TrainingCompletionDialogProps {
  isOpen: boolean
  onClose: () => void
  status: 'completed' | 'failed' | 'cancelled'
  filesProcessed: number
  filesSkipped: number
  filesFailed: number
  totalFiles: number
  samplesCollected: number
  metrics?: {
    genreAccuracy?: number
    timingAccuracy?: number
    moodAccuracy?: number
    descriptiveF1?: number
  }
  error?: string
  onLoadModel?: () => void
  onTrainAnother?: () => void
}

export function TrainingCompletionDialog({
  isOpen,
  onClose,
  status,
  filesProcessed,
  filesSkipped,
  filesFailed,
  totalFiles: _totalFiles,
  samplesCollected,
  metrics,
  error,
  onLoadModel,
  onTrainAnother,
}: TrainingCompletionDialogProps) {
  if (!isOpen) return null

  // Show skipped for cancelled, failed for failed status
  const showSkipped = status === 'cancelled' && filesSkipped > 0
  const showFailed = status === 'failed' && filesFailed > 0

  const statusConfig = {
    completed: {
      icon: CheckCircle2,
      title: 'Training Complete!',
      color: 'text-emerald-500',
      bgColor: 'bg-emerald-100 dark:bg-emerald-900/30',
    },
    failed: {
      icon: XCircle,
      title: 'Training Failed',
      color: 'text-red-500',
      bgColor: 'bg-red-100 dark:bg-red-900/30',
    },
    cancelled: {
      icon: AlertTriangle,
      title: 'Training Cancelled',
      color: 'text-amber-500',
      bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    },
  }

  const config = statusConfig[status]
  if (!config) return null
  const Icon = config.icon

  return (
    <AnimatePresence>
      <>
        {/* Backdrop */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 bg-black/50 z-40"
          onClick={onClose}
        />

        {/* Dialog */}
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          className="fixed inset-0 flex items-center justify-center z-50 p-4"
        >
          <div className="bg-surface-light dark:bg-surface-dark rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
            {/* Header */}
            <div className="flex items-center justify-between px-6 py-4 border-b border-border-light dark:border-border-dark">
              <div className="flex items-center gap-3">
                <div className={clsx('w-10 h-10 rounded-xl flex items-center justify-center', config.bgColor)}>
                  <Icon className={clsx('w-5 h-5', config.color)} />
                </div>
                <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">
                  {config.title}
                </h2>
              </div>
              <button
                onClick={onClose}
                className="p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Content */}
            <div className="px-6 py-4 space-y-4">
              {/* Stats */}
              <div className={clsx('grid gap-3', (showSkipped || showFailed) ? 'grid-cols-3' : 'grid-cols-2')}>
                <div className="p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 text-center">
                  <div className="text-2xl font-bold text-emerald-600 dark:text-emerald-400">
                    {filesProcessed}
                  </div>
                  <div className="text-xs text-emerald-600 dark:text-emerald-400">Processed</div>
                </div>
                {showSkipped && (
                  <div className="p-3 rounded-xl bg-amber-50 dark:bg-amber-900/20 text-center">
                    <div className="text-2xl font-bold text-amber-600 dark:text-amber-400">
                      {filesSkipped}
                    </div>
                    <div className="text-xs text-amber-600 dark:text-amber-400">Skipped</div>
                  </div>
                )}
                {showFailed && (
                  <div className="p-3 rounded-xl bg-red-50 dark:bg-red-900/20 text-center">
                    <div className="text-2xl font-bold text-red-600 dark:text-red-400">
                      {filesFailed}
                    </div>
                    <div className="text-xs text-red-600 dark:text-red-400">Failed</div>
                  </div>
                )}
                <div className="p-3 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken text-center">
                  <div className="text-2xl font-bold text-stone-700 dark:text-stone-300">
                    {samplesCollected.toLocaleString()}
                  </div>
                  <div className="text-xs text-stone-500">Samples</div>
                </div>
              </div>

              {/* Metrics (if completed) */}
              {status === 'completed' && metrics && (
                <div className="p-4 bg-surface-sunken dark:bg-surface-dark-sunken rounded-xl">
                  <h4 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">
                    Model Accuracy
                  </h4>
                  <div className="space-y-2">
                    {metrics.genreAccuracy !== undefined && (
                      <div className="flex justify-between text-sm">
                        <span className="text-stone-500">Genre:</span>
                        <span className="font-medium text-emerald-600 dark:text-emerald-400">
                          {(metrics.genreAccuracy * 100).toFixed(1)}%
                        </span>
                      </div>
                    )}
                    {metrics.timingAccuracy !== undefined && (
                      <div className="flex justify-between text-sm">
                        <span className="text-stone-500">Timing:</span>
                        <span className="font-medium text-emerald-600 dark:text-emerald-400">
                          {(metrics.timingAccuracy * 100).toFixed(1)}%
                        </span>
                      </div>
                    )}
                    {metrics.moodAccuracy !== undefined && (
                      <div className="flex justify-between text-sm">
                        <span className="text-stone-500">Mood:</span>
                        <span className="font-medium text-emerald-600 dark:text-emerald-400">
                          {(metrics.moodAccuracy * 100).toFixed(1)}%
                        </span>
                      </div>
                    )}
                    {metrics.descriptiveF1 !== undefined && (
                      <div className="flex justify-between text-sm">
                        <span className="text-stone-500">Comments F1:</span>
                        <span className="font-medium text-emerald-600 dark:text-emerald-400">
                          {(metrics.descriptiveF1 * 100).toFixed(1)}%
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Error Message */}
              {error && (
                <div className="p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl">
                  <h4 className="text-sm font-medium text-red-700 dark:text-red-300 mb-1">
                    Error Details
                  </h4>
                  <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="flex justify-end gap-3 px-6 py-4 border-t border-border-light dark:border-border-dark">
              <button onClick={onTrainAnother} className="btn btn-secondary">
                Train Another
              </button>
              {status === 'completed' && onLoadModel && (
                <button onClick={onLoadModel} className="btn btn-primary">
                  Load Model
                </button>
              )}
            </div>
          </div>
        </motion.div>
      </>
    </AnimatePresence>
  )
}
