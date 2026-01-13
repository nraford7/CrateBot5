/**
 * TagEditor Component
 * Genre and Album dropdowns with confidence indicators
 */
interface TagEditorProps {
  genre: string
  album: string
  genreOptions: string[]
  albumOptions: string[]
  genreConfidence?: number
  albumConfidence?: number
  onGenreChange: (value: string) => void
  onAlbumChange: (value: string) => void
}

function ConfidenceBadge({ value }: { value?: number }) {
  if (value === undefined) return null

  const percent = Math.round(value * 100)
  let colorClass = 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'

  if (percent >= 80) {
    colorClass = 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
  } else if (percent >= 60) {
    colorClass = 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400'
  } else if (percent >= 40) {
    colorClass = 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400'
  }

  return (
    <span className={`text-xs font-medium px-2 py-0.5 rounded ${colorClass}`}>
      {percent}%
    </span>
  )
}

export function TagEditor({
  genre,
  album,
  genreOptions,
  albumOptions,
  genreConfidence,
  albumConfidence,
  onGenreChange,
  onAlbumChange,
}: TagEditorProps) {
  return (
    <div className="grid gap-4">
      {/* Genre */}
      <div>
        <div className="flex items-center justify-between mb-1">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Genre (Timing)
          </label>
          <ConfidenceBadge value={genreConfidence} />
        </div>
        <select
          value={genre}
          onChange={(e) => onGenreChange(e.target.value)}
          className="input w-full"
        >
          <option value="">Select genre...</option>
          {genreOptions.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      </div>

      {/* Album (Mood) */}
      <div>
        <div className="flex items-center justify-between mb-1">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Album (Mood)
          </label>
          <ConfidenceBadge value={albumConfidence} />
        </div>
        <select
          value={album}
          onChange={(e) => onAlbumChange(e.target.value)}
          className="input w-full"
        >
          <option value="">Select mood...</option>
          {albumOptions.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      </div>
    </div>
  )
}
