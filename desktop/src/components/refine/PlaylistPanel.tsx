/**
 * PlaylistPanel Component - Redesigned
 * Track list with status indicators
 */
import { FolderOpen, Music, Check, Edit3, X, Circle } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'
import { RefinementItem, ItemStatus } from '../../hooks/useRefinement'

interface PlaylistPanelProps {
  items: RefinementItem[]
  selectedIndex: number
  stats: {
    total: number
    approved: number
    corrected: number
    skipped: number
    pending: number
  }
  onSelectItem: (index: number) => void
  onLoadDirectory: () => void
  onClearSession: () => void
}

const statusConfig: Record<
  ItemStatus,
  { icon: typeof Check; color: string; bgColor: string; label: string }
> = {
  approved: {
    icon: Check,
    color: 'text-emerald-500',
    bgColor: 'bg-emerald-100 dark:bg-emerald-900/30',
    label: 'Approved',
  },
  corrected: {
    icon: Edit3,
    color: 'text-amber-500',
    bgColor: 'bg-amber-100 dark:bg-amber-900/30',
    label: 'Corrected',
  },
  skipped: {
    icon: X,
    color: 'text-stone-400',
    bgColor: 'bg-stone-100 dark:bg-stone-800',
    label: 'Skipped',
  },
  pending: {
    icon: Circle,
    color: 'text-stone-300 dark:text-stone-600',
    bgColor: '',
    label: 'Pending',
  },
}

function StatusIcon({ status }: { status: ItemStatus }) {
  const config = statusConfig[status]
  const Icon = config.icon
  return (
    <div className={clsx('w-6 h-6 rounded-full flex items-center justify-center', config.bgColor)}>
      <Icon className={clsx('w-3.5 h-3.5', config.color)} />
    </div>
  )
}

function StatBadge({ icon: Icon, count, color }: { icon: any; count: number; color: string }) {
  return (
    <span className="flex items-center gap-1">
      <Icon className={clsx('w-3 h-3', color)} />
      <span className="font-medium">{count}</span>
    </span>
  )
}

export function PlaylistPanel({
  items,
  selectedIndex,
  stats,
  onSelectItem,
  onLoadDirectory,
  onClearSession,
}: PlaylistPanelProps) {
  const progressPercent = stats.total > 0
    ? Math.round(((stats.approved + stats.skipped) / stats.total) * 100)
    : 0

  return (
    <div className="w-80 border-r border-border-light dark:border-border-dark flex flex-col bg-surface-sunken dark:bg-surface-dark-sunken">
      {/* Header */}
      <div className="p-4 border-b border-border-light dark:border-border-dark space-y-4">
        <div className="flex gap-2">
          <motion.button
            onClick={onLoadDirectory}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className="btn btn-secondary flex-1"
          >
            <FolderOpen className="w-4 h-4" />
            Load
          </motion.button>
          <AnimatePresence>
            {items.length > 0 && (
              <motion.button
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                onClick={onClearSession}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className="btn btn-ghost px-3"
                title="Clear session"
              >
                <X className="w-4 h-4" />
              </motion.button>
            )}
          </AnimatePresence>
        </div>

        {/* Progress Stats */}
        <AnimatePresence>
          {items.length > 0 && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              className="space-y-3"
            >
              {/* Progress Bar */}
              <div>
                <div className="flex justify-between text-xs text-stone-500 dark:text-stone-400 mb-1.5">
                  <span>Track {selectedIndex + 1} of {stats.total}</span>
                  <span>{progressPercent}% complete</span>
                </div>
                <div className="progress-track">
                  <motion.div
                    className="progress-fill"
                    initial={{ width: 0 }}
                    animate={{ width: `${progressPercent}%` }}
                    transition={{ duration: 0.5, ease: 'easeOut' }}
                  />
                </div>
              </div>

              {/* Stat Pills */}
              <div className="flex gap-4 text-xs text-stone-600 dark:text-stone-400">
                <StatBadge icon={Check} count={stats.approved} color="text-emerald-500" />
                <StatBadge icon={Edit3} count={stats.corrected} color="text-amber-500" />
                <StatBadge icon={X} count={stats.skipped} color="text-stone-400" />
                <StatBadge icon={Circle} count={stats.pending} color="text-stone-300 dark:text-stone-600" />
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Playlist */}
      <div className="flex-1 overflow-auto">
        {items.length === 0 ? (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="p-6 text-center"
          >
            <div className="w-14 h-14 mx-auto mb-4 rounded-xl bg-surface-light dark:bg-surface-dark flex items-center justify-center">
              <Music className="w-7 h-7 text-stone-300 dark:text-stone-600" />
            </div>
            <p className="text-stone-600 dark:text-stone-400 font-medium">No files loaded</p>
            <p className="text-xs text-stone-400 dark:text-stone-500 mt-1">
              Click Load to select a directory
            </p>
          </motion.div>
        ) : (
          <ul>
            {items.map((item, index) => (
              <motion.li
                key={item.path}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: index * 0.02 }}
                onClick={() => onSelectItem(index)}
                className={clsx(
                  'p-3 cursor-pointer flex items-center gap-3 transition-all duration-200 border-l-2',
                  selectedIndex === index
                    ? 'bg-amber-50 dark:bg-amber-900/20 border-l-amber-500'
                    : 'border-l-transparent hover:bg-surface-light dark:hover:bg-surface-dark'
                )}
              >
                <StatusIcon status={item.status} />
                <span
                  className={clsx(
                    'text-sm truncate flex-1',
                    item.status === 'skipped'
                      ? 'text-stone-400 dark:text-stone-500'
                      : selectedIndex === index
                        ? 'text-amber-700 dark:text-amber-400 font-medium'
                        : 'text-stone-700 dark:text-stone-300'
                  )}
                >
                  {item.name}
                </span>
              </motion.li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
