/**
 * TaggingConfirmationDialog
 * Shows tagging settings and lexicon for confirmation before starting tagging.
 */
import { useState, useEffect } from 'react'
import { X, Play, Settings2, BookOpen, ChevronDown } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../stores/appStore'
import { api, LexiconConfig } from '../api/client'
import { getFrameOptions } from '../constants/id3Frames'

interface TaggingConfirmationDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  fileCount: number
}

// Common ID3 frame options for tag assignment
const ID3_FRAME_OPTIONS = getFrameOptions()

export function TaggingConfirmationDialog({
  isOpen,
  onClose,
  onConfirm,
  fileCount,
}: TaggingConfirmationDialogProps) {
  const { taggingPreferences, setTaggingPreferences, settings } = useAppStore()
  const [lexicon, setLexicon] = useState<LexiconConfig | null>(null)
  const [lexiconError, setLexiconError] = useState<string | null>(null)
  const [showLexiconDetails, setShowLexiconDetails] = useState(false)

  useEffect(() => {
    if (isOpen) {
      setLexiconError(null)
      api.getLexicon()
        .then(setLexicon)
        .catch((err) => {
          console.error('Failed to load lexicon:', err)
          setLexiconError('Could not load vocabulary settings')
        })
    }
  }, [isOpen])

  const updateFieldPref = (field: 'genre' | 'album' | 'mood' | 'comments' | 'likeness', key: 'enabled' | 'targetField', value: boolean | string) => {
    setTaggingPreferences({
      [field]: { ...taggingPreferences[field], [key]: value },
    })
  }

  const enabledTags = [
    taggingPreferences.genre.enabled && 'Genre',
    taggingPreferences.album.enabled && 'Timing',
    taggingPreferences.mood.enabled && 'Mood',
    taggingPreferences.comments.enabled && 'Comments (Descriptive)',
    taggingPreferences.likeness.enabled && 'Likeness',
    taggingPreferences.vibes.enabled && 'Vibes',
    taggingPreferences.hooks.enabled && 'Hooks',
  ].filter(Boolean)

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/50 z-40"
            onClick={onClose}
          />

          {/* Dialog */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="fixed inset-0 flex items-center justify-center z-50 p-4"
          >
            <div className="bg-surface-light dark:bg-surface-dark rounded-2xl shadow-2xl w-full max-w-lg max-h-[85vh] overflow-hidden flex flex-col">
              {/* Header */}
              <div className="flex items-center justify-between px-6 py-4 border-b border-border-light dark:border-border-dark">
                <h2 className="font-display font-semibold text-lg text-stone-900 dark:text-stone-100">
                  Confirm Tagging Settings
                </h2>
                <button
                  onClick={onClose}
                  className="p-2 rounded-lg text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Content */}
              <div className="flex-1 overflow-auto px-6 py-4 space-y-5">
                {/* Summary */}
                <div className="p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-xl">
                  <p className="text-sm text-amber-800 dark:text-amber-200">
                    <strong>{fileCount}</strong> files will be tagged with:{' '}
                    <strong>{enabledTags.join(', ') || 'No tags selected'}</strong>
                  </p>
                </div>

                {/* Tags to Write */}
                <section>
                  <div className="flex items-center gap-2 mb-3">
                    <Settings2 className="w-4 h-4 text-stone-400" />
                    <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300">
                      Tags to Write
                    </h3>
                  </div>
                  <div className="space-y-3">
                    {/* Genre */}
                    <div className="p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.genre.enabled}
                          onChange={(e) => updateFieldPref('genre', 'enabled', e.target.checked)}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Genre</span>
                      </label>
                      {taggingPreferences.genre.enabled && (
                        <div className="mt-2 ml-7">
                          <select
                            value={taggingPreferences.genre.targetField}
                            onChange={(e) => updateFieldPref('genre', 'targetField', e.target.value)}
                            className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                          >
                            {ID3_FRAME_OPTIONS.map(opt => (
                              <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>

                    {/* Timing */}
                    <div className="p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.album.enabled}
                          onChange={(e) => updateFieldPref('album', 'enabled', e.target.checked)}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Timing</span>
                      </label>
                      {taggingPreferences.album.enabled && (
                        <div className="mt-2 ml-7">
                          <select
                            value={taggingPreferences.album.targetField}
                            onChange={(e) => updateFieldPref('album', 'targetField', e.target.value)}
                            className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                          >
                            {ID3_FRAME_OPTIONS.map(opt => (
                              <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>

                    {/* Mood */}
                    <div className="p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.mood.enabled}
                          onChange={(e) => updateFieldPref('mood', 'enabled', e.target.checked)}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Mood</span>
                      </label>
                      {taggingPreferences.mood.enabled && (
                        <div className="mt-2 ml-7">
                          <select
                            value={taggingPreferences.mood.targetField}
                            onChange={(e) => updateFieldPref('mood', 'targetField', e.target.value)}
                            className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                          >
                            {ID3_FRAME_OPTIONS.map(opt => (
                              <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>

                    {/* Comments (Descriptive) */}
                    <div className="p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.comments.enabled}
                          onChange={(e) => updateFieldPref('comments', 'enabled', e.target.checked)}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Comments (Descriptive)</span>
                      </label>
                      {taggingPreferences.comments.enabled && (
                        <div className="mt-2 ml-7">
                          <select
                            value={taggingPreferences.comments.targetField}
                            onChange={(e) => updateFieldPref('comments', 'targetField', e.target.value)}
                            className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                          >
                            {ID3_FRAME_OPTIONS.map(opt => (
                              <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>

                    {/* Likeness Scores */}
                    <div className="p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken">
                      <label className="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={taggingPreferences.likeness.enabled}
                          onChange={(e) => updateFieldPref('likeness', 'enabled', e.target.checked)}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Likeness Scores</span>
                      </label>
                      {taggingPreferences.likeness.enabled && (
                        <div className="mt-2 ml-7">
                          <select
                            value={taggingPreferences.likeness.targetField}
                            onChange={(e) => updateFieldPref('likeness', 'targetField', e.target.value)}
                            className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                          >
                            {ID3_FRAME_OPTIONS.map(opt => (
                              <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>
                  </div>
                </section>

                {/* AI Features */}
                <section>
                  <h3 className="text-sm font-medium text-stone-700 dark:text-stone-300 mb-3">
                    AI Features
                  </h3>
                  <div className="space-y-3">
                    {/* Vibes */}
                    <div className={`p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken ${!settings.vibeAvailable ? 'opacity-50' : ''}`}>
                      <label className={`flex items-center gap-3 ${settings.vibeAvailable ? 'cursor-pointer' : ''}`}>
                        <input
                          type="checkbox"
                          checked={taggingPreferences.vibes.enabled}
                          onChange={(e) => setTaggingPreferences({
                            vibes: { ...taggingPreferences.vibes, enabled: e.target.checked }
                          })}
                          disabled={!settings.vibeAvailable}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Generate Vibes</span>
                        {!settings.vibeAvailable && (
                          <span className="text-xs text-stone-400">(needs API key)</span>
                        )}
                      </label>
                      {taggingPreferences.vibes.enabled && settings.vibeAvailable && (
                        <div className="mt-2 ml-7 space-y-2">
                          <div className="flex items-center gap-2">
                            <span className="text-xs text-stone-500 w-12">Short:</span>
                            <select
                              value={taggingPreferences.vibes.shortTargetField}
                              onChange={(e) => setTaggingPreferences({
                                vibes: { ...taggingPreferences.vibes, shortTargetField: e.target.value }
                              })}
                              className="flex-1 px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                            >
                              {ID3_FRAME_OPTIONS.map(opt => (
                                <option key={opt.value} value={opt.value}>{opt.label}</option>
                              ))}
                            </select>
                          </div>
                          <div className="flex items-center gap-2">
                            <span className="text-xs text-stone-500 w-12">Long:</span>
                            <select
                              value={taggingPreferences.vibes.longTargetField}
                              onChange={(e) => setTaggingPreferences({
                                vibes: { ...taggingPreferences.vibes, longTargetField: e.target.value }
                              })}
                              className="flex-1 px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                            >
                              {ID3_FRAME_OPTIONS.map(opt => (
                                <option key={opt.value} value={opt.value}>{opt.label}</option>
                              ))}
                            </select>
                          </div>
                        </div>
                      )}
                    </div>

                    {/* Hooks */}
                    <div className={`p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken ${!settings.hookAvailable ? 'opacity-50' : ''}`}>
                      <label className={`flex items-center gap-3 ${settings.hookAvailable ? 'cursor-pointer' : ''}`}>
                        <input
                          type="checkbox"
                          checked={taggingPreferences.hooks.enabled}
                          onChange={(e) => setTaggingPreferences({
                            hooks: { ...taggingPreferences.hooks, enabled: e.target.checked }
                          })}
                          disabled={!settings.hookAvailable}
                          className="checkbox"
                        />
                        <span className="text-sm font-medium text-stone-700 dark:text-stone-300">Detect Hooks</span>
                        {!settings.hookAvailable && (
                          <span className="text-xs text-stone-400">({settings.hookStatus})</span>
                        )}
                      </label>
                      {taggingPreferences.hooks.enabled && settings.hookAvailable && (
                        <div className="mt-2 ml-7">
                          <select
                            value={taggingPreferences.hooks.targetField}
                            onChange={(e) => setTaggingPreferences({
                              hooks: { ...taggingPreferences.hooks, targetField: e.target.value }
                            })}
                            className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                          >
                            {ID3_FRAME_OPTIONS.map(opt => (
                              <option key={opt.value} value={opt.value}>{opt.label}</option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>
                  </div>
                </section>

                {/* Overwrite Option */}
                <section>
                  <label className="flex items-center gap-3 p-3 rounded-lg bg-surface-sunken dark:bg-surface-dark-sunken cursor-pointer">
                    <input
                      type="checkbox"
                      checked={taggingPreferences.overwrite}
                      onChange={(e) => setTaggingPreferences({ overwrite: e.target.checked })}
                      className="checkbox"
                    />
                    <span className="text-sm font-medium text-stone-700 dark:text-stone-300">
                      Overwrite existing tags
                    </span>
                  </label>
                </section>

                {/* Lexicon Preview */}
                <section>
                  <button
                    onClick={() => setShowLexiconDetails(!showLexiconDetails)}
                    className="flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400 hover:underline"
                  >
                    <BookOpen className="w-4 h-4" />
                    {showLexiconDetails ? 'Hide' : 'Show'} Lexicon Details
                    <ChevronDown className={`w-4 h-4 transition-transform ${showLexiconDetails ? 'rotate-180' : ''}`} />
                  </button>
                  {lexiconError && (
                    <div className="text-xs text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 rounded px-2 py-1 mb-2 mt-2">
                      {lexiconError}
                    </div>
                  )}
                  {showLexiconDetails && lexicon && (
                    <div className="mt-3 p-3 bg-surface-sunken dark:bg-surface-dark-sunken rounded-lg text-xs space-y-2">
                      {Object.entries(lexicon.categories).map(([key, cat]) => (
                        <div key={key} className="flex justify-between">
                          <span className="capitalize text-stone-600 dark:text-stone-400">{key}:</span>
                          <span className="text-stone-800 dark:text-stone-200 font-mono">{cat.id3_frame}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </section>
              </div>

              {/* Footer */}
              <div className="flex justify-end gap-3 px-6 py-4 border-t border-border-light dark:border-border-dark">
                <button onClick={onClose} className="btn btn-secondary">
                  Cancel
                </button>
                <button
                  onClick={onConfirm}
                  disabled={enabledTags.length === 0}
                  className="btn btn-primary"
                >
                  <Play className="w-4 h-4" />
                  Start Tagging
                </button>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
