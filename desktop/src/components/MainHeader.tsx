import { Settings, Disc3 } from 'lucide-react'
import { motion } from 'framer-motion'
import { useAppStore } from '../stores/appStore'

interface MainHeaderProps {
  onOpenSettings: () => void
}

export function MainHeader({ onOpenSettings }: MainHeaderProps) {
  const { model, taggingPreferences, currentTask } = useAppStore()
  const isProcessing = !!currentTask

  // Build preferences summary (using new structure)
  const writingTags = [
    taggingPreferences.genre.enabled && 'Genre',
    taggingPreferences.album.enabled && 'Timing',
    taggingPreferences.mood.enabled && 'Mood',
    taggingPreferences.comments.enabled && 'Comments (Descriptive)',
  ].filter(Boolean)

  const aiFeatures = [
    taggingPreferences.vibes.enabled && 'Vibes',
    taggingPreferences.hooks.enabled && 'Hooks',
  ].filter(Boolean)

  return (
    <header className="h-14 border-b border-border-light dark:border-border-dark bg-surface-light dark:bg-surface-dark flex items-center pr-6 drag-region">
      {/* Spacer for macOS traffic light buttons */}
      <div className="w-20 flex-shrink-0" />

      {/* Logo */}
      <div className="flex items-center gap-2.5 no-drag">
        <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-amber-600 flex items-center justify-center">
          <motion.div
            animate={isProcessing ? { rotate: 360 } : { rotate: 0 }}
            transition={{
              duration: 3,
              repeat: isProcessing ? Infinity : 0,
              ease: 'linear',
            }}
          >
            <Disc3 className="w-4 h-4 text-white drop-shadow-sm" />
          </motion.div>
        </div>
        <span className="font-display font-semibold text-stone-900 dark:text-stone-100">
          Crate<span className="text-amber-500">Bot</span>
        </span>
      </div>

      {/* Model Info */}
      <div className="ml-8 flex items-center gap-4 no-drag">
        <div className="text-sm">
          <span className="text-stone-400 dark:text-stone-500">Model:</span>
          <span className="ml-2 font-medium text-stone-700 dark:text-stone-300">
            {model.loaded ? (model.name || 'Loaded') : 'Not loaded'}
          </span>
        </div>

        <div className="h-4 w-px bg-border-light dark:bg-border-dark" />

        <div className="text-sm text-stone-400 dark:text-stone-500">
          Writing: <span className="text-stone-600 dark:text-stone-400">{writingTags.join(', ') || 'None'}</span>
          {aiFeatures.length > 0 && (
            <>
              {' '}&bull;{' '}
              <span className="text-stone-600 dark:text-stone-400">{aiFeatures.join(', ')}</span>
            </>
          )}
        </div>
      </div>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Settings Button */}
      <button
        onClick={onOpenSettings}
        className="no-drag p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
      >
        <Settings className="w-5 h-5" />
      </button>
    </header>
  )
}
