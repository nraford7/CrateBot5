/**
 * CommentTagGrid Component
 * 4-column checkbox grid for comment tags (Character tags)
 */
import { useMemo } from 'react'

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
      <div className="text-sm text-muted py-2">
        No comment tags available. Load a model to see available tags.
      </div>
    )
  }

  return (
    <div>
      <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        Comments (Character)
      </label>
      <div className="max-h-48 overflow-y-auto border border-border dark:border-border-dark rounded-lg p-3 bg-gray-50 dark:bg-gray-800/50">
        <div className="grid grid-cols-4 gap-x-4 gap-y-1">
          {sortedTags.map((tag) => (
            <label
              key={tag}
              className="flex items-center gap-2 cursor-pointer py-1 text-sm"
            >
              <input
                type="checkbox"
                checked={selectedTags.includes(tag)}
                onChange={() => handleToggle(tag)}
                className="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700"
              />
              <span className="text-gray-700 dark:text-gray-300 truncate">
                {tag}
              </span>
            </label>
          ))}
        </div>
      </div>
      <div className="mt-1 text-xs text-muted">
        {selectedTags.length} of {sortedTags.length} selected
      </div>
    </div>
  )
}
