import { useState } from 'react'
import {
  Music,
  CheckCircle2,
  XCircle,
  Clock,
  Loader2,
  AlertTriangle,
  ChevronDown,
  ChevronRight,
  Trash2,
  X,
} from 'lucide-react'
import { clsx } from 'clsx'

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
}

const statusConfig: Record<FileStatus, { icon: typeof CheckCircle2; color: string; label: string }> = {
  pending: { icon: Clock, color: 'text-muted', label: 'Pending' },
  processing: { icon: Loader2, color: 'text-accent', label: 'Processing' },
  tagged: { icon: CheckCircle2, color: 'text-green-500', label: 'Tagged' },
  failed: { icon: XCircle, color: 'text-red-500', label: 'Failed' },
  skipped: { icon: AlertTriangle, color: 'text-amber-500', label: 'Skipped' },
  review: { icon: AlertTriangle, color: 'text-amber-500', label: 'Review' },
}

export function FileQueue({
  files,
  onRemove,
  onClear,
  onRetry,
  currentIndex = -1,
  isProcessing = false,
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

  if (files.length === 0) {
    return (
      <div className="card flex flex-col items-center justify-center py-12 text-muted">
        <Music className="w-12 h-12 mb-4 opacity-30" />
        <p className="text-lg mb-2">No files in queue</p>
        <p className="text-sm">Add files or select a directory to get started</p>
      </div>
    )
  }

  return (
    <div className="card p-0 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-gray-50 dark:bg-gray-800 border-b border-border dark:border-border-dark">
        <div className="flex items-center gap-4">
          <span className="font-medium text-gray-900 dark:text-white">
            {stats.total} files
          </span>
          <div className="flex items-center gap-3 text-xs">
            {stats.tagged > 0 && (
              <span className="flex items-center gap-1 text-green-600">
                <CheckCircle2 className="w-3 h-3" />
                {stats.tagged}
              </span>
            )}
            {stats.processing > 0 && (
              <span className="flex items-center gap-1 text-accent">
                <Loader2 className="w-3 h-3 animate-spin" />
                {stats.processing}
              </span>
            )}
            {stats.pending > 0 && (
              <span className="flex items-center gap-1 text-muted">
                <Clock className="w-3 h-3" />
                {stats.pending}
              </span>
            )}
            {stats.failed > 0 && (
              <span className="flex items-center gap-1 text-red-500">
                <XCircle className="w-3 h-3" />
                {stats.failed}
              </span>
            )}
          </div>
        </div>
        {onClear && !isProcessing && (
          <button
            onClick={onClear}
            className="text-xs text-muted hover:text-red-500 flex items-center gap-1"
          >
            <Trash2 className="w-3 h-3" />
            Clear all
          </button>
        )}
      </div>

      {/* File List */}
      <div className="max-h-96 overflow-auto divide-y divide-border dark:divide-border-dark">
        {files.map((file, index) => {
          const config = statusConfig[file.status]
          const Icon = config.icon
          const isExpanded = expandedPaths.has(file.path)
          const isCurrent = index === currentIndex
          const hasDetails = file.tags || file.vibe || file.hook || file.error

          return (
            <div
              key={file.path}
              className={clsx(
                'transition-colors',
                isCurrent && 'bg-accent/5'
              )}
            >
              <div
                className={clsx(
                  'flex items-center gap-3 px-4 py-2',
                  hasDetails && 'cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800'
                )}
                onClick={() => hasDetails && toggleExpand(file.path)}
              >
                {/* Expand Toggle */}
                <div className="w-4">
                  {hasDetails && (
                    isExpanded ? (
                      <ChevronDown className="w-4 h-4 text-muted" />
                    ) : (
                      <ChevronRight className="w-4 h-4 text-muted" />
                    )
                  )}
                </div>

                {/* Status Icon */}
                <Icon
                  className={clsx(
                    'w-4 h-4 flex-shrink-0',
                    config.color,
                    file.status === 'processing' && 'animate-spin'
                  )}
                />

                {/* File Name */}
                <span className="flex-1 text-sm truncate text-gray-900 dark:text-white">
                  {file.name}
                </span>

                {/* Status Label */}
                <span className={clsx('text-xs', config.color)}>
                  {config.label}
                </span>

                {/* Actions */}
                {!isProcessing && (
                  <div className="flex items-center gap-1">
                    {file.status === 'failed' && onRetry && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          onRetry(file.path)
                        }}
                        className="p-1 hover:bg-gray-200 dark:hover:bg-gray-700 rounded text-muted hover:text-accent"
                        title="Retry"
                      >
                        <Loader2 className="w-3 h-3" />
                      </button>
                    )}
                    {onRemove && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          onRemove(file.path)
                        }}
                        className="p-1 hover:bg-gray-200 dark:hover:bg-gray-700 rounded text-muted hover:text-red-500"
                        title="Remove"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    )}
                  </div>
                )}
              </div>

              {/* Expanded Details */}
              {isExpanded && hasDetails && (
                <div className="px-4 pb-3 pl-12 text-xs space-y-1">
                  {file.error && (
                    <div className="text-red-500">
                      Error: {file.error}
                    </div>
                  )}
                  {file.tags?.genre && (
                    <div className="text-muted">
                      <span className="text-gray-500">Genre:</span> {file.tags.genre}
                    </div>
                  )}
                  {file.tags?.album && (
                    <div className="text-muted">
                      <span className="text-gray-500">Album:</span> {file.tags.album}
                    </div>
                  )}
                  {file.tags?.comments && (
                    <div className="text-muted">
                      <span className="text-gray-500">Comments:</span> {file.tags.comments}
                    </div>
                  )}
                  {file.vibe && (
                    <div className="text-muted">
                      <span className="text-gray-500">Vibe:</span> {file.vibe}
                    </div>
                  )}
                  {file.hook && (
                    <div className="text-muted">
                      <span className="text-gray-500">Hook:</span> "{file.hook}"
                    </div>
                  )}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Progress Bar (during processing) */}
      {isProcessing && stats.total > 0 && (
        <div className="px-4 py-2 bg-gray-50 dark:bg-gray-800 border-t border-border dark:border-border-dark">
          <div className="flex justify-between text-xs mb-1">
            <span className="text-muted">Progress</span>
            <span className="font-medium">
              {stats.tagged + stats.failed + stats.skipped} / {stats.total}
            </span>
          </div>
          <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
            <div
              className="bg-accent h-1.5 rounded-full transition-all duration-300"
              style={{
                width: `${((stats.tagged + stats.failed + stats.skipped) / stats.total) * 100}%`,
              }}
            />
          </div>
        </div>
      )}
    </div>
  )
}
