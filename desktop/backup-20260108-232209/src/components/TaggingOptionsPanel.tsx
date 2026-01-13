import { Tags, Sparkles, Mic, Settings2 } from 'lucide-react'
import { clsx } from 'clsx'

export interface TaggingOptions {
  // ML Tags
  writeGenre: boolean
  writeAlbum: boolean
  writeComments: boolean
  writeLikeness: boolean

  // AI Features
  generateVibes: boolean
  detectHooks: boolean

  // Other
  overwrite: boolean
}

interface TaggingOptionsPanelProps {
  options: TaggingOptions
  onChange: (options: TaggingOptions) => void
  vibeAvailable: boolean
  vibeStatus: string
  hookAvailable: boolean
  hookStatus: string
  disabled?: boolean
}

export function TaggingOptionsPanel({
  options,
  onChange,
  vibeAvailable,
  vibeStatus,
  hookAvailable,
  hookStatus,
  disabled = false,
}: TaggingOptionsPanelProps) {
  const update = (key: keyof TaggingOptions, value: boolean) => {
    onChange({ ...options, [key]: value })
  }

  return (
    <div className="card">
      <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-4 flex items-center gap-2">
        <Settings2 className="w-5 h-5 text-muted" />
        Tagging Options
      </h2>

      <div className="space-y-6">
        {/* ML Tags Section */}
        <div>
          <div className="flex items-center gap-2 mb-3">
            <Tags className="w-4 h-4 text-accent" />
            <span className="font-medium text-sm text-gray-900 dark:text-white">
              ML-Predicted Tags
            </span>
          </div>
          <div className="grid grid-cols-2 gap-3 ml-6">
            <label className={clsx(
              'flex items-center gap-2 cursor-pointer',
              disabled && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeGenre}
                onChange={(e) => update('writeGenre', e.target.checked)}
                disabled={disabled}
                className="rounded border-border text-accent focus:ring-accent"
              />
              <span className="text-sm">Genre</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2 cursor-pointer',
              disabled && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeAlbum}
                onChange={(e) => update('writeAlbum', e.target.checked)}
                disabled={disabled}
                className="rounded border-border text-accent focus:ring-accent"
              />
              <span className="text-sm">Album (Mood)</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2 cursor-pointer',
              disabled && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeComments}
                onChange={(e) => update('writeComments', e.target.checked)}
                disabled={disabled}
                className="rounded border-border text-accent focus:ring-accent"
              />
              <span className="text-sm">Comments</span>
            </label>
            <label className={clsx(
              'flex items-center gap-2 cursor-pointer',
              disabled && 'opacity-50 cursor-not-allowed'
            )}>
              <input
                type="checkbox"
                checked={options.writeLikeness}
                onChange={(e) => update('writeLikeness', e.target.checked)}
                disabled={disabled}
                className="rounded border-border text-accent focus:ring-accent"
              />
              <span className="text-sm">Likeness Scores</span>
            </label>
          </div>
        </div>

        {/* AI Features Section */}
        <div>
          <div className="flex items-center gap-2 mb-3">
            <Sparkles className="w-4 h-4 text-purple-500" />
            <span className="font-medium text-sm text-gray-900 dark:text-white">
              AI Features
            </span>
          </div>
          <div className="space-y-3 ml-6">
            {/* Vibe Generation */}
            <div className="flex items-start gap-3">
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer flex-1',
                (disabled || !vibeAvailable) && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.generateVibes}
                  onChange={(e) => update('generateVibes', e.target.checked)}
                  disabled={disabled || !vibeAvailable}
                  className="rounded border-border text-accent focus:ring-accent mt-0.5"
                />
                <div>
                  <span className="text-sm">Generate Vibes</span>
                  <p className="text-xs text-muted">
                    AI-generated descriptive tags (Composer field)
                  </p>
                </div>
              </label>
              {!vibeAvailable && (
                <span className="text-xs text-amber-600 bg-amber-50 dark:bg-amber-900/20 px-2 py-1 rounded whitespace-nowrap">
                  {vibeStatus}
                </span>
              )}
            </div>

            {/* Hook Detection */}
            <div className="flex items-start gap-3">
              <label className={clsx(
                'flex items-center gap-2 cursor-pointer flex-1',
                (disabled || !hookAvailable) && 'opacity-50 cursor-not-allowed'
              )}>
                <input
                  type="checkbox"
                  checked={options.detectHooks}
                  onChange={(e) => update('detectHooks', e.target.checked)}
                  disabled={disabled || !hookAvailable}
                  className="rounded border-border text-accent focus:ring-accent mt-0.5"
                />
                <div>
                  <span className="text-sm flex items-center gap-1">
                    <Mic className="w-3 h-3" />
                    Detect Vocal Hooks
                  </span>
                  <p className="text-xs text-muted">
                    Transcribe and identify memorable phrases (Work field)
                  </p>
                </div>
              </label>
              {!hookAvailable && (
                <span className="text-xs text-muted bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded whitespace-nowrap">
                  {hookStatus}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Other Options */}
        <div className="pt-4 border-t border-border dark:border-border-dark">
          <label className={clsx(
            'flex items-center gap-2 cursor-pointer',
            disabled && 'opacity-50 cursor-not-allowed'
          )}>
            <input
              type="checkbox"
              checked={options.overwrite}
              onChange={(e) => update('overwrite', e.target.checked)}
              disabled={disabled}
              className="rounded border-border text-accent focus:ring-accent"
            />
            <div>
              <span className="text-sm">Overwrite existing tags</span>
              <p className="text-xs text-muted">
                Replace tags even if file already has them
              </p>
            </div>
          </label>
        </div>
      </div>
    </div>
  )
}
