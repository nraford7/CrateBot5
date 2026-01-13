/**
 * CommentTagGrid Component - Redesigned
 * 4-column checkbox grid for comment tags (Character tags)
 */
import { useMemo } from 'react'
import { motion } from 'framer-motion'
import { clsx } from 'clsx'

interface CommentTagGridProps {
  availableTags: string[]
  selectedTags: string[]
  onChange: (tags: string[]) => void
}

export function CommentTagGrid({
  availableTags,
  selectedTags,
  onChange,
}: CommentTagGridProps) {
  // Sort tags alphabetically
  const sortedTags = useMemo(
    () => [...availableTags].sort((a, b) => a.localeCompare(b)),
    [availableTags]
  )

  const handleToggle = (tag: string) => {
    if (selectedTags.includes(tag)) {
      onChange(selectedTags.filter((t) => t !== tag))
    } else {
      onChange([...selectedTags, tag])
    }
  }

  if (sortedTags.length === 0) {
    return (
      <div className="card">
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-2">
          Comments (Character)
        </label>
        <div className="text-sm text-stone-400 dark:text-stone-500 py-4 text-center">
          No comment tags available. Load a model to see available tags.
        </div>
      </div>
    )
  }

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-3">
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300">
          Comments (Character)
        </label>
        <span className="text-xs text-stone-400 dark:text-stone-500">
          {selectedTags.length} of {sortedTags.length} selected
        </span>
      </div>
      <div className="max-h-48 overflow-y-auto rounded-lg p-3 bg-surface-sunken dark:bg-surface-dark-sunken">
        <div className="grid grid-cols-4 gap-x-4 gap-y-1">
          {sortedTags.map((tag, index) => {
            const isSelected = selectedTags.includes(tag)
            return (
              <motion.label
                key={tag}
                initial={{ opacity: 0, y: 5 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.01 }}
                className={clsx(
                  'flex items-center gap-2.5 cursor-pointer py-1.5 px-2 rounded-md transition-colors',
                  isSelected
                    ? 'bg-amber-100 dark:bg-amber-900/30'
                    : 'hover:bg-surface-light dark:hover:bg-surface-dark'
                )}
              >
                <input
                  type="checkbox"
                  checked={isSelected}
                  onChange={() => handleToggle(tag)}
                  className="checkbox"
                />
                <span
                  className={clsx(
                    'text-sm truncate',
                    isSelected
                      ? 'text-amber-700 dark:text-amber-400 font-medium'
                      : 'text-stone-600 dark:text-stone-400'
                  )}
                >
                  {tag}
                </span>
              </motion.label>
            )
          })}
        </div>
      </div>
    </div>
  )
}
