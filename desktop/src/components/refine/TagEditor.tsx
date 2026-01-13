/**
 * TagEditor Component
 * Allows users to edit tags for a track using the 4-field taxonomy:
 * genre, timing, mood, and descriptive tags.
 */

interface TagEditorProps {
  genre?: string
  timing?: string
  mood?: string
  descriptive?: string[]
  availableTags: {
    genre: string[]
    timing: string[]
    mood: string[]
    descriptive: string[]
  }
  onChange: (tags: { genre?: string; timing?: string; mood?: string; descriptive?: string[] }) => void
  disabled?: boolean
}

export function TagEditor({
  genre,
  timing,
  mood,
  descriptive = [],
  availableTags,
  onChange,
  disabled = false
}: TagEditorProps) {
  const handleGenreChange = (value: string) => {
    onChange({ genre: value, timing, mood, descriptive })
  }

  const handleTimingChange = (value: string) => {
    onChange({ genre, timing: value, mood, descriptive })
  }

  const handleMoodChange = (value: string) => {
    onChange({ genre, timing, mood: value, descriptive })
  }

  const handleDescriptiveToggle = (tag: string) => {
    const newDescriptive = descriptive.includes(tag)
      ? descriptive.filter(t => t !== tag)
      : [...descriptive, tag]
    onChange({ genre, timing, mood, descriptive: newDescriptive })
  }

  return (
    <div className="space-y-4">
      {/* Genre */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1">
          Genre
        </label>
        <select
          value={genre || ''}
          onChange={(e) => handleGenreChange(e.target.value)}
          disabled={disabled}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm disabled:opacity-50"
        >
          <option value="">Select genre...</option>
          {availableTags.genre.map(tag => (
            <option key={tag} value={tag}>{tag}</option>
          ))}
        </select>
      </div>

      {/* Timing */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1">
          Timing
        </label>
        <select
          value={timing || ''}
          onChange={(e) => handleTimingChange(e.target.value)}
          disabled={disabled}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm disabled:opacity-50"
        >
          <option value="">Select timing...</option>
          {availableTags.timing.map(tag => (
            <option key={tag} value={tag}>{tag}</option>
          ))}
        </select>
      </div>

      {/* Mood */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1">
          Mood
        </label>
        <select
          value={mood || ''}
          onChange={(e) => handleMoodChange(e.target.value)}
          disabled={disabled}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm disabled:opacity-50"
        >
          <option value="">Select mood...</option>
          {availableTags.mood.map(tag => (
            <option key={tag} value={tag}>{tag}</option>
          ))}
        </select>
      </div>

      {/* Descriptive Tags */}
      <div>
        <label className="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-2">
          Descriptive Tags
        </label>
        {availableTags.descriptive.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {availableTags.descriptive.map(tag => (
              <button
                key={tag}
                type="button"
                onClick={() => handleDescriptiveToggle(tag)}
                disabled={disabled}
                className={`px-3 py-1 text-sm rounded-full border transition-colors ${
                  descriptive.includes(tag)
                    ? 'bg-amber-500 text-white border-amber-500'
                    : 'bg-white dark:bg-stone-800 text-stone-700 dark:text-stone-300 border-stone-300 dark:border-stone-600 hover:border-amber-400'
                } disabled:opacity-50`}
              >
                {tag}
              </button>
            ))}
          </div>
        ) : (
          <p className="text-sm text-stone-500 dark:text-stone-400">
            No descriptive tags available. Train a model to enable them.
          </p>
        )}
      </div>
    </div>
  )
}
