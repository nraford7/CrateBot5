/**
 * VibeEditor Component
 * Short vibe and long description text areas
 */
interface VibeEditorProps {
  vibe: string
  description: string
  hook?: string
  onVibeChange: (value: string) => void
  onDescriptionChange: (value: string) => void
}

export function VibeEditor({
  vibe,
  description,
  hook,
  onVibeChange,
  onDescriptionChange,
}: VibeEditorProps) {
  return (
    <div className="grid gap-4">
      {/* Short Vibe (Composer field) */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          Vibe (Short)
        </label>
        <textarea
          value={vibe}
          onChange={(e) => onVibeChange(e.target.value)}
          className="input w-full min-h-[60px] resize-y"
          placeholder="Short vibe description..."
          rows={2}
        />
      </div>

      {/* Long Description */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
          Description (Long)
        </label>
        <textarea
          value={description}
          onChange={(e) => onDescriptionChange(e.target.value)}
          className="input w-full min-h-[100px] resize-y"
          placeholder="Full description..."
          rows={4}
        />
      </div>

      {/* Hook (read-only display if present) */}
      {hook && (
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Detected Hook
          </label>
          <div className="p-3 bg-gray-50 dark:bg-gray-800 rounded-lg border border-border dark:border-border-dark">
            <p className="text-sm text-gray-700 dark:text-gray-300 italic">
              "{hook}"
            </p>
          </div>
        </div>
      )}
    </div>
  )
}
