/**
 * CrateBot3 - Redesigned StatusBar
 * "Vinyl Warmth" Design System
 *
 * Key changes:
 * - Simplified: Only essential info (connection, current task)
 * - Glowing status indicators
 * - Progress bar for current task
 * - Removed build stamp (moved to Settings)
 * - Cleaner typography
 */

import { Wifi, WifiOff, Loader2, CheckCircle2 } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { clsx } from 'clsx'

interface StatusIndicatorProps {
  status: 'connected' | 'connecting' | 'disconnected'
}

function ConnectionIndicator({ status }: StatusIndicatorProps) {
  const config = {
    connected: {
      icon: Wifi,
      label: 'Connected',
      dotClass: 'statusbar-dot-success',
      textClass: 'text-success',
    },
    connecting: {
      icon: Loader2,
      label: 'Connecting',
      dotClass: 'statusbar-dot-warning',
      textClass: 'text-warning',
    },
    disconnected: {
      icon: WifiOff,
      label: 'Offline',
      dotClass: 'statusbar-dot-danger',
      textClass: 'text-danger',
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
      <span className={clsx('text-caption font-medium', config.textClass)}>
        {config.label}
      </span>
    </div>
  )
}

interface TaskProgressProps {
  type: string
  progress: number
  message?: string
}

function TaskProgress({ type, progress, message }: TaskProgressProps) {
  return (
    <motion.div
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 20 }}
      className="flex items-center gap-3"
    >
      {/* Task type */}
      <div className="flex items-center gap-1.5">
        <Loader2 className="w-3.5 h-3.5 text-amber-500 animate-spin" />
        <span className="text-caption font-medium text-text-primary capitalize">
          {type}
        </span>
      </div>

      {/* Mini progress bar */}
      <div className="w-24 h-1.5 rounded-full bg-surface-sunken dark:bg-surface-dark-sunken overflow-hidden">
        <motion.div
          className="h-full rounded-full bg-amber-500"
          initial={{ width: 0 }}
          animate={{ width: `${progress}%` }}
          transition={{ duration: 0.3, ease: 'easeOut' }}
        />
      </div>

      {/* Percentage */}
      <span className="text-caption font-mono text-text-muted min-w-[36px]">
        {progress.toFixed(0)}%
      </span>

      {/* Optional message */}
      {message && (
        <>
          <div className="divider-vertical" />
          <span className="text-caption text-text-muted truncate max-w-[200px]">
            {message}
          </span>
        </>
      )}
    </motion.div>
  )
}

export function StatusBar() {
  const { serverStatus, model, currentTask } = useAppStore()

  return (
    <footer className="statusbar flex items-center justify-between px-4">
      {/* Left side: Connection + Model status */}
      <div className="flex items-center gap-4">
        {/* Server connection */}
        <ConnectionIndicator status={serverStatus} />

        {/* Divider */}
        <div className="divider-vertical" />

        {/* Model status */}
        <div className="statusbar-indicator">
          {model.loaded ? (
            <>
              <CheckCircle2 className="w-3.5 h-3.5 text-success" />
              <span className="text-caption text-text-secondary">
                Model: <span className="font-medium">{model.name || 'Loaded'}</span>
              </span>
            </>
          ) : (
            <span className="text-caption text-text-muted">No model</span>
          )}
        </div>
      </div>

      {/* Right side: Current task progress */}
      <AnimatePresence mode="wait">
        {currentTask && (
          <TaskProgress
            type={currentTask.type}
            progress={currentTask.progress}
            message={currentTask.message}
          />
        )}
      </AnimatePresence>
    </footer>
  )
}

/**
 * DESIGN NOTES:
 *
 * 1. SIMPLIFIED CONTENT:
 *    - Removed build stamp (moved to Settings > About)
 *    - Only shows: connection, model, current task
 *    - Less visual clutter
 *
 * 2. STATUS INDICATORS:
 *    - Glowing dots for status (CSS glow effect)
 *    - Color-coded: green (connected), amber (connecting), red (offline)
 *    - Icons reinforce status
 *
 * 3. TASK PROGRESS:
 *    - Animated entrance/exit
 *    - Mini progress bar with amber fill
 *    - Mono font for percentage (tabular nums)
 *    - Optional message with truncation
 *
 * 4. LAYOUT:
 *    - Left: static info (connection, model)
 *    - Right: dynamic info (current task)
 *    - Vertical dividers for visual separation
 *
 * 5. TYPOGRAPHY:
 *    - caption size throughout
 *    - font-medium for important values
 *    - font-mono for numbers
 */
