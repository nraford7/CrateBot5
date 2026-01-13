import { Wifi, WifiOff, Loader2, CheckCircle2 } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { clsx } from 'clsx'

interface StatusIndicatorProps {
  status: 'connected' | 'connecting' | 'disconnected' | 'error'
}

function ConnectionIndicator({ status }: StatusIndicatorProps) {
  const config = {
    connected: {
      icon: Wifi,
      label: 'Connected',
      dotClass: 'statusbar-dot-success',
      textClass: 'text-emerald-600 dark:text-emerald-400',
    },
    connecting: {
      icon: Loader2,
      label: 'Connecting',
      dotClass: 'statusbar-dot-warning',
      textClass: 'text-amber-600 dark:text-amber-400',
    },
    disconnected: {
      icon: WifiOff,
      label: 'Offline',
      dotClass: 'statusbar-dot-danger',
      textClass: 'text-red-600 dark:text-red-400',
    },
    error: {
      icon: WifiOff,
      label: 'Error',
      dotClass: 'statusbar-dot-danger',
      textClass: 'text-red-600 dark:text-red-400',
    },
  }[status]

  const Icon = config.icon

  return (
    <div className="statusbar-indicator">
      <div className={clsx('statusbar-dot', config.dotClass)} />
      <Icon
        className={clsx(
          'w-3.5 h-3.5',
          config.textClass,
          status === 'connecting' && 'animate-spin'
        )}
      />
      <span className={clsx('text-xs font-medium', config.textClass)}>
        {config.label}
      </span>
    </div>
  )
}

function formatTime(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`
  const mins = Math.floor(seconds / 60)
  const secs = Math.round(seconds % 60)
  return `${mins}m ${secs}s`
}

export function StatusBar() {
  const { serverStatus, model, currentTask, taggingStats } = useAppStore()

  return (
    <footer className="statusbar justify-between">
      <div className="flex items-center gap-4">
        <ConnectionIndicator status={serverStatus} />

        <div className="divider-vertical" />

        <div className="statusbar-indicator">
          {model.loaded ? (
            <>
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" />
              <span className="text-xs text-stone-600 dark:text-stone-400">
                Model: <span className="font-medium">{model.name || 'Loaded'}</span>
              </span>
            </>
          ) : (
            <span className="text-xs text-stone-400 dark:text-stone-500">No model</span>
          )}
        </div>
      </div>

      <div className="flex items-center gap-4">
        {/* Tagging Stats */}
        <AnimatePresence>
          {taggingStats && taggingStats.startTime !== null && taggingStats.completed < taggingStats.total && (
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 20 }}
              className="flex items-center gap-3 text-xs text-stone-500 dark:text-stone-400"
            >
              <span className="font-medium">
                {taggingStats.completed}/{taggingStats.total} files
              </span>
              {taggingStats.avgTimePerFile > 0 && (
                <>
                  <div className="divider-vertical" />
                  <span>{taggingStats.avgTimePerFile.toFixed(1)}s/file</span>
                </>
              )}
              {taggingStats.eta > 0 && (
                <>
                  <div className="divider-vertical" />
                  <span>ETA: {formatTime(taggingStats.eta)}</span>
                </>
              )}
            </motion.div>
          )}
        </AnimatePresence>

        {/* Current Task Progress */}
        <AnimatePresence mode="wait">
          {currentTask && (
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 20 }}
              className="flex items-center gap-3"
            >
              <div className="flex items-center gap-1.5">
                <Loader2 className="w-3.5 h-3.5 text-amber-500 animate-spin" />
                <span className="text-xs font-medium text-stone-700 dark:text-stone-300 capitalize">
                  {currentTask.type}
                </span>
              </div>

              <div className="w-24 h-1.5 rounded-full bg-surface-sunken dark:bg-surface-dark-sunken overflow-hidden">
                <motion.div
                  className="h-full rounded-full bg-amber-500"
                  initial={{ width: 0 }}
                  animate={{ width: `${currentTask.progress}%` }}
                  transition={{ duration: 0.3, ease: 'easeOut' }}
                />
              </div>

              <span className="text-xs font-mono text-stone-500 dark:text-stone-400 min-w-[36px]">
                {currentTask.progress.toFixed(0)}%
              </span>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </footer>
  )
}
