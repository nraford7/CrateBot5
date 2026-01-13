/**
 * FileQueue Component - Redesigned
 * Queue of files with status indicators
 */
import { useState } from 'react'
import {
  Music,
  CheckCircle2,
  XCircle,
  Clock,
  Loader2,
  AlertTriangle,
  ChevronRight,
  Trash2,
  X,
  RotateCcw,
} from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'
import { formatTime } from '../utils/formatTime'

export type FileStatus = 'pending' | 'processing' | 'tagged' | 'failed' | 'skipped' | 'review'

export interface QueuedFile {
  path: string
  name: string
  status: FileStatus
  error?: string
  tags?: {
    genre?: string
    album?: string
    comments?: string
  }
  vibe?: string
  hook?: string
}

interface FileQueueProps {
  files: QueuedFile[]
  onRemove?: (path: string) => void
  onClear?: () => void
  onRetry?: (path: string) => void
  currentIndex?: number
  isProcessing?: boolean
  isPaused?: boolean
  startTime?: number | null
}

const statusConfig: Record<FileStatus, { icon: typeof CheckCircle2; color: string; bgColor: string; label: string; labelColor: string }> = {
  pending: {
    icon: Clock,
    color: 'text-stone-400',
    bgColor: 'bg-stone-100 dark:bg-stone-800',
    label: 'Pending',
    labelColor: 'text-stone-400'
  },
  processing: {
    icon: Loader2,
    color: 'text-amber-500',
    bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    label: 'Processing',
    labelColor: 'text-amber-500'
  },
  tagged: {
    icon: CheckCircle2,
    color: 'text-emerald-500',
    bgColor: 'bg-emerald-100 dark:bg-emerald-900/30',
    label: 'Complete',
    labelColor: 'text-emerald-500'
  },
  failed: {
    icon: XCircle,
    color: 'text-red-500',
    bgColor: 'bg-red-100 dark:bg-red-900/30',
    label: 'Failed',
    labelColor: 'text-red-500'
  },
  skipped: {
    icon: AlertTriangle,
    color: 'text-amber-500',
    bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    label: 'Skipped',
    labelColor: 'text-amber-500'
  },
  review: {
    icon: AlertTriangle,
    color: 'text-violet-500',
    bgColor: 'bg-violet-100 dark:bg-violet-900/30',
    label: 'Review',
    labelColor: 'text-violet-500'
  },
}

export function FileQueue({
  files,
  onRemove,
  onClear,
  onRetry,
  currentIndex = -1,
  isProcessing = false,
  isPaused = false,
  startTime = null,
}: FileQueueProps) {
  const [expandedPaths, setExpandedPaths] = useState<Set<string>>(new Set())

  const toggleExpand = (path: string) => {
    setExpandedPaths((prev) => {
      const next = new Set(prev)
      if (next.has(path)) {
        next.delete(path)
      } else {
        next.add(path)
      }
      return next
    })
  }

  // Group stats
  const stats = {
    total: files.length,
    pending: files.filter((f) => f.status === 'pending').length,
    processing: files.filter((f) => f.status === 'processing').length,
    tagged: files.filter((f) => f.status === 'tagged').length,
    failed: files.filter((f) => f.status === 'failed').length,
    skipped: files.filter((f) => f.status === 'skipped').length,
  }

  // Calculate completed count and remaining
  const completedCount = stats.tagged + stats.failed + stats.skipped
  const remainingCount = stats.total - completedCount

  // Calculate time estimates
  const elapsedSeconds = startTime ? (Date.now() - startTime) / 1000 : 0
  const avgTimePerTrack = completedCount > 0 ? elapsedSeconds / completedCount : 0
  const etaSeconds = avgTimePerTrack * remainingCount

  if (files.length === 0) {
    return (
      <div className="card flex flex-col items-center justify-center py-12">
        <div className="w-16 h-16 rounded-2xl bg-surface-sunken dark:bg-surface-dark-sunken flex items-center justify-center mb-4">
          <Music className="w-8 h-8 text-stone-300 dark:text-stone-600" />
        </div>
        <p className="text-lg text-stone-600 dark:text-stone-400 font-medium mb-1">No files in queue</p>
        <p className="text-sm text-stone-400 dark:text-stone-500">Add files or select a directory to get started</p>
      </div>
    )
  }

  return (
    <div className="card p-0 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-surface-sunken dark:bg-surface-dark-sunken border-b border-border-light dark:border-border-dark">
        <div className="flex items-center gap-4">
          <span className="font-medium text-stone-900 dark:text-stone-100">
            {stats.total} files
          </span>
          <div className="flex items-center gap-3 text-xs">
            {stats.pending > 0 && (
              <span className="flex items-center gap-1 text-stone-400">
                <Clock className="w-3 h-3" />
                {stats.pending} pending
              </span>
            )}
            {stats.processing > 0 && (
              <span className="flex items-center gap-1 text-amber-500">
                <Loader2 className={clsx('w-3 h-3', !isPaused && 'animate-spin')} />
                {stats.processing} {isPaused ? 'paused' : 'active'}
              </span>
            )}
            {stats.tagged > 0 && (
              <span className="flex items-center gap-1 text-emerald-500">
                <CheckCircle2 className="w-3 h-3" />
                {stats.tagged} complete
              </span>
            )}
            {stats.failed > 0 && (
              <span className="flex items-center gap-1 text-red-500">
                <XCircle className="w-3 h-3" />
                {stats.failed} failed
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-4">
          {/* Time estimates during processing */}
          {isProcessing && (
            <div className="flex items-center gap-3 text-xs text-stone-500 dark:text-stone-400">
              {avgTimePerTrack > 0 && (
                <span>{avgTimePerTrack.toFixed(1)}s/track</span>
              )}
              {etaSeconds > 0 && (
                <span>ETA: {formatTime(etaSeconds)}</span>
              )}
            </div>
          )}
          {onClear && !isProcessing && (
            <motion.button
              onClick={onClear}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              className="text-xs text-stone-400 hover:text-red-500 flex items-center gap-1 transition-colors"
            >
              <Trash2 className="w-3 h-3" />
              Clear all
            </motion.button>
          )}
        </div>
      </div>

      {/* File List */}
      <div className="max-h-96 overflow-auto">
        <AnimatePresence>
          {files.map((file, index) => {
            const config = statusConfig[file.status]
            const Icon = config.icon
            const isExpanded = expandedPaths.has(file.path)
            const isCurrent = index === currentIndex
            const hasDetails = file.tags || file.vibe || file.hook || file.error

            return (
              <motion.div
                key={file.path}
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                exit={{ opacity: 0, height: 0 }}
                className={clsx(
                  'border-b border-border-light dark:border-border-dark last:border-b-0 transition-colors',
                  isCurrent && 'bg-amber-50 dark:bg-amber-900/10'
                )}
              >
                <div
                  className={clsx(
                    'flex items-center gap-3 px-4 py-2.5',
                    hasDetails && 'cursor-pointer hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken'
                  )}
                  onClick={() => hasDetails && toggleExpand(file.path)}
                >
                  {/* Expand Toggle */}
                  <div className="w-4">
                    {hasDetails && (
                      <motion.div
                        animate={{ rotate: isExpanded ? 90 : 0 }}
                        transition={{ duration: 0.2 }}
                      >
                        <ChevronRight className="w-4 h-4 text-stone-400" />
                      </motion.div>
                    )}
                  </div>

                  {/* Status Icon */}
                  <div className={clsx('w-6 h-6 rounded-full flex items-center justify-center', config.bgColor)}>
                    <Icon
                      className={clsx(
                        'w-3.5 h-3.5',
                        config.color,
                        file.status === 'processing' && !isPaused && 'animate-spin'
                      )}
                    />
                  </div>

                  {/* File Name */}
                  <span className="flex-1 text-sm truncate text-stone-700 dark:text-stone-300">
                    {file.name}
                  </span>

                  {/* Status Label */}
                  <span className={clsx('text-xs font-medium', config.labelColor)}>
                    {config.label}
                  </span>

                  {/* Actions */}
                  {!isProcessing && (
                    <div className="flex items-center gap-1">
                      {file.status === 'failed' && onRetry && (
                        <motion.button
                          onClick={(e) => {
                            e.stopPropagation()
                            onRetry(file.path)
                          }}
                          whileHover={{ scale: 1.1 }}
                          whileTap={{ scale: 0.9 }}
                          className="p-1.5 hover:bg-amber-100 dark:hover:bg-amber-900/30 rounded-lg text-stone-400 hover:text-amber-500 transition-colors"
                          title="Retry"
                        >
                          <RotateCcw className="w-3.5 h-3.5" />
                        </motion.button>
                      )}
                      {onRemove && (
                        <motion.button
                          onClick={(e) => {
                            e.stopPropagation()
                            onRemove(file.path)
                          }}
                          whileHover={{ scale: 1.1 }}
                          whileTap={{ scale: 0.9 }}
                          className="p-1.5 hover:bg-red-100 dark:hover:bg-red-900/30 rounded-lg text-stone-400 hover:text-red-500 transition-colors"
                          title="Remove"
                        >
                          <X className="w-3.5 h-3.5" />
                        </motion.button>
                      )}
                    </div>
                  )}
                </div>

                {/* Expanded Details */}
                <AnimatePresence>
                  {isExpanded && hasDetails && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      className="px-4 pb-3 pl-14"
                    >
                      <div className="text-xs space-y-1.5 p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                        {file.error && (
                          <div className="text-red-500">
                            <span className="text-red-400">Error:</span> {file.error}
                          </div>
                        )}
                        {file.tags?.genre && (
                          <div>
                            <span className="text-stone-400">Genre:</span>{' '}
                            <span className="text-stone-600 dark:text-stone-300">{file.tags.genre}</span>
                          </div>
                        )}
                        {file.tags?.album && (
                          <div>
                            <span className="text-stone-400">Timing:</span>{' '}
                            <span className="text-stone-600 dark:text-stone-300">{file.tags.album}</span>
                          </div>
                        )}
                        {file.tags?.comments && (
                          <div>
                            <span className="text-stone-400">Comments:</span>{' '}
                            <span className="text-stone-600 dark:text-stone-300">{file.tags.comments}</span>
                          </div>
                        )}
                        {file.vibe && (
                          <div>
                            <span className="text-stone-400">Vibe:</span>{' '}
                            <span className="text-stone-600 dark:text-stone-300">{file.vibe}</span>
                          </div>
                        )}
                        {file.hook && (
                          <div>
                            <span className="text-stone-400">Hook:</span>{' '}
                            <span className="text-stone-600 dark:text-stone-300 italic">"{file.hook}"</span>
                          </div>
                        )}
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </motion.div>
            )
          })}
        </AnimatePresence>
      </div>
    </div>
  )
}
