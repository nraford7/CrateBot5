import { Loader2, CheckCircle2, XCircle, Pause, Play, Square } from 'lucide-react'
import { clsx } from 'clsx'

interface TrainingProgressProps {
  status: 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'
  phase: string
  progress: number
  currentFile?: string
  filesProcessed: number
  totalFiles: number
  samplesCollected: number
  metrics?: {
    genreAccuracy?: number
    albumAccuracy?: number
    commentsF1?: number
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

export function TrainingProgress({
  status,
  phase,
  progress,
  currentFile,
  filesProcessed,
  totalFiles,
  samplesCollected,
  metrics,
  error,
  onPause,
  onResume,
  onCancel,
}: TrainingProgressProps) {
  const isActive = status === 'running' || status === 'paused'

  return (
    <div className="card">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          {status === 'running' && (
            <Loader2 className="w-5 h-5 text-accent animate-spin" />
          )}
          {status === 'paused' && (
            <Pause className="w-5 h-5 text-amber-500" />
          )}
          {status === 'completed' && (
            <CheckCircle2 className="w-5 h-5 text-green-500" />
          )}
          {(status === 'failed' || status === 'cancelled') && (
            <XCircle className="w-5 h-5 text-red-500" />
          )}
          <div>
            <h3 className="font-medium text-gray-900 dark:text-white">
              {phaseLabels[phase] || phase}
            </h3>
            {currentFile && status === 'running' && (
              <p className="text-sm text-muted truncate max-w-md">
                {currentFile}
              </p>
            )}
          </div>
        </div>

        {/* Controls */}
        {isActive && (
          <div className="flex gap-2">
            {status === 'running' && onPause && (
              <button
                onClick={onPause}
                className="btn btn-ghost p-2"
                title="Pause"
              >
                <Pause className="w-4 h-4" />
              </button>
            )}
            {status === 'paused' && onResume && (
              <button
                onClick={onResume}
                className="btn btn-ghost p-2"
                title="Resume"
              >
                <Play className="w-4 h-4" />
              </button>
            )}
            {onCancel && (
              <button
                onClick={onCancel}
                className="btn btn-ghost p-2 text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
                title="Cancel"
              >
                <Square className="w-4 h-4" />
              </button>
            )}
          </div>
        )}
      </div>

      {/* Progress Bar */}
      <div className="mb-4">
        <div className="flex justify-between text-sm mb-1">
          <span className="text-muted">Progress</span>
          <span className="font-medium">{progress.toFixed(0)}%</span>
        </div>
        <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden">
          <div
            className={clsx(
              'h-full rounded-full transition-all duration-300',
              status === 'completed' ? 'bg-green-500' :
              status === 'failed' || status === 'cancelled' ? 'bg-red-500' :
              status === 'paused' ? 'bg-amber-500' :
              'bg-accent'
            )}
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 text-sm">
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
          <div className="text-muted mb-1">Files</div>
          <div className="font-medium">
            {filesProcessed} / {totalFiles}
          </div>
        </div>
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
          <div className="text-muted mb-1">Samples</div>
          <div className="font-medium">{samplesCollected}</div>
        </div>
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
          <div className="text-muted mb-1">Status</div>
          <div className={clsx(
            'font-medium capitalize',
            status === 'completed' ? 'text-green-600' :
            status === 'failed' || status === 'cancelled' ? 'text-red-600' :
            status === 'paused' ? 'text-amber-600' :
            'text-accent'
          )}>
            {status}
          </div>
        </div>
      </div>

      {/* Metrics (after training) */}
      {metrics && status === 'completed' && (
        <div className="mt-4 pt-4 border-t border-border dark:border-border-dark">
          <h4 className="text-sm font-medium text-gray-900 dark:text-white mb-3">
            Training Metrics
          </h4>
          <div className="grid grid-cols-3 gap-4 text-sm">
            {metrics.genreAccuracy !== undefined && (
              <div>
                <div className="text-muted mb-1">Genre Accuracy</div>
                <div className="font-medium text-green-600">
                  {(metrics.genreAccuracy * 100).toFixed(1)}%
                </div>
              </div>
            )}
            {metrics.albumAccuracy !== undefined && (
              <div>
                <div className="text-muted mb-1">Album Accuracy</div>
                <div className="font-medium text-green-600">
                  {(metrics.albumAccuracy * 100).toFixed(1)}%
                </div>
              </div>
            )}
            {metrics.commentsF1 !== undefined && (
              <div>
                <div className="text-muted mb-1">Comments F1</div>
                <div className="font-medium text-green-600">
                  {(metrics.commentsF1 * 100).toFixed(1)}%
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Error Message */}
      {error && (
        <div className="mt-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
        </div>
      )}
    </div>
  )
}
