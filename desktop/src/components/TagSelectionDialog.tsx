/**
 * TagSelectionDialog Component - Redesigned
 * Modal for selecting tags before training
 */
import { useState, useEffect } from 'react'
import { X, Check, Search, Tag, Disc3 } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'
import { getAllFrameOptions } from '../constants/id3Frames'

interface DiscoveredTags {
  genre: { values: Record<string, number> }
  timing: { values: Record<string, number> }
  mood: { values: Record<string, number> }
  descriptive: { values: Record<string, number> }
  total_files: number
}

interface SelectedTags {
  genre: string[]
  timing: string[]
  mood: string[]
  descriptive: string[]
}

interface TagSelectionDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: (selectedTags: SelectedTags) => void
  discoveredTags: DiscoveredTags | null
  isLoading: boolean
  tagSources: {
    genreFrame: string
    timingFrame: string
    moodFrame: string
    commentsFrame: string
  }
  onTagSourcesChange: (sources: {
    genreFrame: string
    timingFrame: string
    moodFrame: string
    commentsFrame: string
  }) => void
  onScan: () => Promise<void>
}

type TabType = 'genre' | 'timing' | 'mood' | 'descriptive'

const backdropVariants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
}

const modalVariants = {
  hidden: { opacity: 0, scale: 0.95, y: 20 },
  visible: { opacity: 1, scale: 1, y: 0, transition: { type: 'spring' as const, damping: 25, stiffness: 300 } },
}

export function TagSelectionDialog({
  isOpen,
  onClose,
  onConfirm,
  discoveredTags,
  isLoading,
  tagSources,
  onTagSourcesChange,
  onScan,
}: TagSelectionDialogProps) {
  const [activeTab, setActiveTab] = useState<TabType>('genre')
  const [selectedTags, setSelectedTags] = useState<SelectedTags>({
    genre: [],
    timing: [],
    mood: [],
    descriptive: [],
  })
  const [searchQuery, setSearchQuery] = useState('')
  const [showSources, setShowSources] = useState(true)
  const frameOptions = getAllFrameOptions()
  const timingOptions = [{ value: '', label: 'Auto (Split Genre)' }, ...frameOptions]

  // Reset selection when dialog opens with new tags
  useEffect(() => {
    if (isOpen && discoveredTags) {
      const getValues = (tab: TabType) => discoveredTags[tab]?.values ?? {}
      // Pre-select tags with sufficient samples (> 5)
      const preselect = (values: Record<string, number>, minCount = 5) =>
        Object.entries(values)
          .filter(([_, count]) => count >= minCount)
          .map(([tag]) => tag)

      setSelectedTags({
        genre: preselect(getValues('genre')),
        timing: preselect(getValues('timing')),
        mood: preselect(getValues('mood')),
        descriptive: preselect(getValues('descriptive'), 3),
      })
    }
  }, [isOpen, discoveredTags])

  useEffect(() => {
    if (isOpen) {
      setShowSources(true)
    }
  }, [isOpen])

  if (!isOpen) return null

  const toggleTag = (tab: TabType, tag: string) => {
    setSelectedTags((prev) => ({
      ...prev,
      [tab]: prev[tab].includes(tag)
        ? prev[tab].filter((t) => t !== tag)
        : [...prev[tab], tag],
    }))
  }

  const selectAll = (tab: TabType) => {
    if (!discoveredTags) return
    const allTags = Object.keys(discoveredTags[tab]?.values ?? {})
    setSelectedTags((prev) => ({
      ...prev,
      [tab]: allTags,
    }))
  }

  const deselectAll = (tab: TabType) => {
    setSelectedTags((prev) => ({
      ...prev,
      [tab]: [],
    }))
  }

  const getFilteredTags = (tab: TabType) => {
    if (!discoveredTags) return []
    const values = discoveredTags[tab]?.values ?? {}
    return Object.entries(values)
      .filter(([tag]) => tag.toLowerCase().includes(searchQuery.toLowerCase()))
      .sort((a, b) => b[1] - a[1]) // Sort by count descending
  }

  const totalSelected =
    selectedTags.genre.length +
    selectedTags.timing.length +
    selectedTags.mood.length +
    selectedTags.descriptive.length

  const handleConfirm = () => {
    if (totalSelected === 0) return
    onConfirm(selectedTags)
  }

  const tabs: { id: TabType; label: string }[] = [
    { id: 'genre', label: 'Genre' },
    { id: 'timing', label: 'Timing' },
    { id: 'mood', label: 'Mood' },
    { id: 'descriptive', label: 'Description' },
  ]

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          variants={backdropVariants}
          initial="hidden"
          animate="visible"
          exit="hidden"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
          onClick={onClose}
        >
          <motion.div
            variants={modalVariants}
            initial="hidden"
            animate="visible"
            exit="hidden"
            onClick={(e) => e.stopPropagation()}
            className="bg-surface-light dark:bg-surface-dark rounded-2xl shadow-2xl w-full max-w-2xl max-h-[80vh] flex flex-col overflow-hidden"
          >
            {/* Header */}
            <div className="flex items-center justify-between p-5 border-b border-border-light dark:border-border-dark">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
                  <Disc3 className="w-5 h-5 text-amber-600 dark:text-amber-400" />
                </div>
                <div>
                  <h2 className="text-lg font-display font-semibold text-stone-900 dark:text-stone-100">
                    Select Tags for Training
                  </h2>
                  {discoveredTags && (
                    <p className="text-sm text-stone-500 dark:text-stone-400">
                      Found {discoveredTags.total_files} files
                    </p>
                  )}
                </div>
              </div>
              <motion.button
                onClick={onClose}
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.9 }}
                className="p-2 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken rounded-xl transition-colors"
              >
                <X className="w-5 h-5 text-stone-500" />
              </motion.button>
            </div>

            {isLoading ? (
              <div className="flex-1 flex items-center justify-center p-12">
                <motion.div
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  className="text-center"
                >
                  <motion.div
                    animate={{ rotate: 360 }}
                    transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
                  >
                    <Disc3 className="w-12 h-12 text-amber-500 mx-auto mb-4" />
                  </motion.div>
                  <p className="text-stone-500 dark:text-stone-400">Scanning directory for tags...</p>
                </motion.div>
              </div>
            ) : (
              <>
                {showSources && !discoveredTags && (
                  <div className="p-4 border-b border-border-light dark:border-border-dark">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                      <div>
                        <label className="block text-xs font-medium text-stone-600 dark:text-stone-400 mb-1">Genre</label>
                        <select
                          value={tagSources.genreFrame}
                          onChange={(e) => onTagSourcesChange({ ...tagSources, genreFrame: e.target.value })}
                          className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                        >
                          {frameOptions.map((opt) => (
                            <option key={opt.value} value={opt.value}>{opt.label}</option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-stone-600 dark:text-stone-400 mb-1">Timing</label>
                        <select
                          value={tagSources.timingFrame}
                          onChange={(e) => onTagSourcesChange({ ...tagSources, timingFrame: e.target.value })}
                          className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                        >
                          {timingOptions.map((opt) => (
                            <option key={opt.value} value={opt.value}>{opt.label}</option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-stone-600 dark:text-stone-400 mb-1">Mood</label>
                        <select
                          value={tagSources.moodFrame}
                          onChange={(e) => onTagSourcesChange({ ...tagSources, moodFrame: e.target.value })}
                          className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                        >
                          {frameOptions.map((opt) => (
                            <option key={opt.value} value={opt.value}>{opt.label}</option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-stone-600 dark:text-stone-400 mb-1">Description</label>
                        <select
                          value={tagSources.commentsFrame}
                          onChange={(e) => onTagSourcesChange({ ...tagSources, commentsFrame: e.target.value })}
                          className="w-full px-2 py-1.5 text-xs bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                        >
                          {frameOptions.map((opt) => (
                            <option key={opt.value} value={opt.value}>{opt.label}</option>
                          ))}
                        </select>
                      </div>
                    </div>
                    <div className="mt-4 flex items-center justify-between">
                      <p className="text-xs text-stone-500 dark:text-stone-400">
                        Choose which ID3 frames should be used to discover each tag category during scanning.
                      </p>
                    </div>
                  </div>
                )}

                {discoveredTags ? (
                  <>
                    {/* Tabs */}
                    <div className="flex border-b border-border-light dark:border-border-dark">
                      <div className="flex-1 px-4 py-3 text-xs text-stone-500 dark:text-stone-400">
                        <button
                          onClick={() => {
                            setShowSources(true)
                            setActiveTab('genre')
                          }}
                          className="text-amber-600 dark:text-amber-400 hover:underline font-medium"
                        >
                          Change sources
                        </button>
                      </div>
                      {tabs.map((tab) => (
                        <button
                          key={tab.id}
                          onClick={() => setActiveTab(tab.id)}
                          className={clsx(
                            'flex-1 px-4 py-3 text-sm font-medium transition-all duration-200 relative',
                            activeTab === tab.id
                              ? 'text-amber-600 dark:text-amber-400'
                              : 'text-stone-500 hover:text-stone-700 dark:hover:text-stone-300'
                          )}
                        >
                          {tab.label}
                          <span className={clsx(
                            'ml-2 text-xs px-2 py-0.5 rounded-full transition-colors',
                            activeTab === tab.id
                              ? 'bg-amber-100 dark:bg-amber-900/30 text-amber-600 dark:text-amber-400'
                              : 'bg-surface-sunken dark:bg-surface-dark-sunken text-stone-500'
                          )}>
                            {selectedTags[tab.id].length}/{Object.keys(discoveredTags[tab.id]?.values ?? {}).length}
                          </span>
                          {activeTab === tab.id && (
                            <motion.div
                              layoutId="activeTab"
                              className="absolute bottom-0 left-0 right-0 h-0.5 bg-amber-500"
                            />
                          )}
                        </button>
                      ))}
                    </div>

                    {/* Search */}
                    <div className="p-4 border-b border-border-light dark:border-border-dark">
                      <div className="relative">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-stone-400" />
                        <input
                          type="text"
                          value={searchQuery}
                          onChange={(e) => setSearchQuery(e.target.value)}
                          placeholder="Search tags..."
                          className="input pl-10 w-full"
                        />
                      </div>
                      <div className="flex gap-3 mt-3">
                        <button
                          onClick={() => selectAll(activeTab)}
                          className="text-xs text-amber-600 dark:text-amber-400 hover:underline font-medium"
                        >
                          Select all
                        </button>
                        <span className="text-stone-300 dark:text-stone-600">|</span>
                        <button
                          onClick={() => deselectAll(activeTab)}
                          className="text-xs text-amber-600 dark:text-amber-400 hover:underline font-medium"
                        >
                          Deselect all
                        </button>
                      </div>
                    </div>

                    {/* Tag List */}
                    <div className="flex-1 overflow-auto p-4">
                      <div className="grid grid-cols-2 gap-2">
                        {getFilteredTags(activeTab).map(([tag, count], index) => {
                          const isSelected = selectedTags[activeTab].includes(tag)
                          return (
                            <motion.button
                              key={tag}
                              initial={{ opacity: 0, y: 10 }}
                              animate={{ opacity: 1, y: 0 }}
                              transition={{ delay: index * 0.02 }}
                              onClick={() => toggleTag(activeTab, tag)}
                              className={clsx(
                                'flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-left transition-all duration-200',
                                isSelected
                                  ? 'bg-amber-100 dark:bg-amber-900/30 border-2 border-amber-500'
                                  : 'bg-surface-sunken dark:bg-surface-dark-sunken border-2 border-transparent hover:border-amber-200 dark:hover:border-amber-800'
                              )}
                            >
                              <div
                                className={clsx(
                                  'w-5 h-5 rounded-md border-2 flex items-center justify-center transition-all',
                                  isSelected
                                    ? 'bg-amber-500 border-amber-500'
                                    : 'border-stone-300 dark:border-stone-600'
                                )}
                              >
                                {isSelected && <Check className="w-3 h-3 text-white" />}
                              </div>
                              <span className={clsx(
                                'flex-1 truncate text-sm',
                                isSelected
                                  ? 'text-amber-700 dark:text-amber-400 font-medium'
                                  : 'text-stone-700 dark:text-stone-300'
                              )}>
                                {tag}
                              </span>
                              <span className="text-xs text-stone-400">{count}</span>
                            </motion.button>
                          )
                        })}
                      </div>
                      {getFilteredTags(activeTab).length === 0 && (
                        <div className="text-center py-12">
                          <Tag className="w-10 h-10 mx-auto mb-3 text-stone-300 dark:text-stone-600" />
                          <p className="text-stone-500 dark:text-stone-400">No tags found</p>
                        </div>
                      )}
                    </div>
                  </>
                ) : (
                  <div className="flex-1 flex items-center justify-center p-10">
                    <div className="text-center">
                      <Tag className="w-10 h-10 mx-auto mb-3 text-stone-300 dark:text-stone-600" />
                      <p className="text-stone-500 dark:text-stone-400">
                        Choose your tag sources and click Scan Tags to begin.
                      </p>
                    </div>
                  </div>
                )}
              </>
            )}

            {/* Footer */}
            <div className="flex items-center justify-between p-5 border-t border-border-light dark:border-border-dark bg-surface-sunken dark:bg-surface-dark-sunken">
              {discoveredTags ? (
                <>
                  <div className="text-sm text-stone-500 dark:text-stone-400">
                    <span className="font-medium text-amber-600 dark:text-amber-400">{totalSelected}</span> tags selected
                  </div>
                  <div className="flex gap-3">
                    <motion.button
                      onClick={onClose}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.98 }}
                      className="btn btn-secondary"
                    >
                      Cancel
                    </motion.button>
                    <motion.button
                      onClick={handleConfirm}
                      disabled={totalSelected === 0}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.98 }}
                      className="btn btn-primary"
                    >
                      Start Training
                    </motion.button>
                  </div>
                </>
              ) : (
                <>
                  <div className="text-sm text-stone-500 dark:text-stone-400">
                    Select sources, then scan to find tags.
                  </div>
                  <div className="flex gap-3">
                    <motion.button
                      onClick={onClose}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.98 }}
                      className="btn btn-secondary"
                    >
                      Cancel
                    </motion.button>
                    <motion.button
                      onClick={() => {
                        setShowSources(false)
                        onScan()
                      }}
                      disabled={isLoading}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.98 }}
                      className="btn btn-primary"
                    >
                      {isLoading ? 'Scanning...' : 'OK'}
                    </motion.button>
                  </div>
                </>
              )}
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
