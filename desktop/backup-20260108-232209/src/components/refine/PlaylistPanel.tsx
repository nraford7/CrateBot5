/**
 * PlaylistPanel Component
 * Track list with status indicators
 */
import { FolderOpen, Music, Check, Edit3, X, Circle } from 'lucide-react'
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
  { icon: typeof Check; color: string; label: string }
> = {
  approved: {
    icon: Check,
    color: 'text-green-500',
    label: 'Approved',
  },
  corrected: {
    icon: Edit3,
    color: 'text-blue-500',
    label: 'Corrected',
  },
  skipped: {
    icon: X,
    color: 'text-gray-400',
    label: 'Skipped',
  },
  pending: {
    icon: Circle,
    color: 'text-gray-300 dark:text-gray-600',
    label: 'Pending',
  },
}

function StatusIcon({ status }: { status: ItemStatus }) {
  const config = statusConfig[status]
  const Icon = config.icon
  return <Icon className={`w-4 h-4 ${config.color}`} />
}

export function PlaylistPanel({
  items,
  selectedIndex,
  stats,
  onSelectItem,
  onLoadDirectory,
  onClearSession,
}: PlaylistPanelProps) {
  return (
    <div className="w-80 border-r border-border dark:border-border-dark flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-border dark:border-border-dark space-y-3">
        <div className="flex gap-2">
          <button
            onClick={onLoadDirectory}
            className="btn btn-secondary flex-1 flex items-center justify-center gap-2"
          >
            <FolderOpen className="w-4 h-4" />
            Load
          </button>
          {items.length > 0 && (
            <button
              onClick={onClearSession}
              className="btn btn-ghost px-3"
              title="Clear session"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>

        {/* Progress Stats */}
        {items.length > 0 && (
          <div className="text-xs text-muted space-y-1">
            <div className="flex justify-between">
              <span>
                Track {selectedIndex + 1} of {stats.total}
              </span>
              <span>{stats.approved + stats.skipped} reviewed</span>
            </div>
            <div className="flex gap-3">
              <span className="flex items-center gap-1">
                <Check className="w-3 h-3 text-green-500" />
                {stats.approved}
              </span>
              <span className="flex items-center gap-1">
                <Edit3 className="w-3 h-3 text-blue-500" />
                {stats.corrected}
              </span>
              <span className="flex items-center gap-1">
                <X className="w-3 h-3 text-gray-400" />
                {stats.skipped}
              </span>
              <span className="flex items-center gap-1">
                <Circle className="w-3 h-3 text-gray-300" />
                {stats.pending}
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Legend */}
      {items.length > 0 && (
        <div className="px-4 py-2 border-b border-border dark:border-border-dark">
          <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted">
            <span className="flex items-center gap-1">
              <Check className="w-3 h-3 text-green-500" /> Approved
            </span>
            <span className="flex items-center gap-1">
              <Edit3 className="w-3 h-3 text-blue-500" /> Corrected
            </span>
            <span className="flex items-center gap-1">
              <X className="w-3 h-3 text-gray-400" /> Skipped
            </span>
            <span className="flex items-center gap-1">
              <Circle className="w-3 h-3 text-gray-300" /> Pending
            </span>
          </div>
        </div>
      )}

      {/* Playlist */}
      <div className="flex-1 overflow-auto">
        {items.length === 0 ? (
          <div className="p-4 text-center text-muted">
            <Music className="w-8 h-8 mx-auto mb-2 opacity-50" />
            <p>No files loaded</p>
            <p className="text-xs mt-1">Click Load to select a directory</p>
          </div>
        ) : (
          <ul className="divide-y divide-border dark:divide-border-dark">
            {items.map((item, index) => (
              <li
                key={item.path}
                onClick={() => onSelectItem(index)}
                className={`p-3 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 flex items-center gap-3 ${
                  selectedIndex === index
                    ? 'bg-accent/10 border-l-2 border-l-accent'
                    : ''
                }`}
              >
                <StatusIcon status={item.status} />
                <span
                  className={`text-sm truncate flex-1 ${
                    item.status === 'skipped'
                      ? 'text-gray-400 dark:text-gray-500'
                      : 'text-gray-900 dark:text-white'
                  }`}
                >
                  {item.name}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
