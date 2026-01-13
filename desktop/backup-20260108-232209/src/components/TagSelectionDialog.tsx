import { useState, useEffect } from 'react'
import { X, Check, Loader2, Search, Tag } from 'lucide-react'
import { clsx } from 'clsx'

interface DiscoveredTags {
  genre: { values: Record<string, number> }
  album: { values: Record<string, number> }
  comments: { values: Record<string, number> }
  total_files: number
}

interface SelectedTags {
  genre: string[]
  album: string[]
  comments: string[]
}

interface TagSelectionDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: (selectedTags: SelectedTags) => void
  discoveredTags: DiscoveredTags | null
  isLoading: boolean
}

type TabType = 'genre' | 'album' | 'comments'

export function TagSelectionDialog({
  isOpen,
  onClose,
  onConfirm,
  discoveredTags,
  isLoading,
}: TagSelectionDialogProps) {
  const [activeTab, setActiveTab] = useState<TabType>('genre')
  const [selectedTags, setSelectedTags] = useState<SelectedTags>({
    genre: [],
    album: [],
    comments: [],
  })
  const [searchQuery, setSearchQuery] = useState('')

  // Reset selection when dialog opens with new tags
  useEffect(() => {
    if (isOpen && discoveredTags) {
      // Pre-select tags with sufficient samples (> 5)
      const preselect = (values: Record<string, number>, minCount = 5) =>
        Object.entries(values)
          .filter(([_, count]) => count >= minCount)
          .map(([tag]) => tag)

      setSelectedTags({
        genre: preselect(discoveredTags.genre.values),
        album: preselect(discoveredTags.album.values),
        comments: preselect(discoveredTags.comments.values, 3),
      })
    }
  }, [isOpen, discoveredTags])

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
    const allTags = Object.keys(discoveredTags[tab].values)
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
    const values = discoveredTags[tab].values
    return Object.entries(values)
      .filter(([tag]) => tag.toLowerCase().includes(searchQuery.toLowerCase()))
      .sort((a, b) => b[1] - a[1]) // Sort by count descending
  }

  const totalSelected =
    selectedTags.genre.length + selectedTags.album.length + selectedTags.comments.length

  const handleConfirm = () => {
    if (totalSelected === 0) return
    onConfirm(selectedTags)
  }

  const tabs: { id: TabType; label: string }[] = [
    { id: 'genre', label: 'Genre' },
    { id: 'album', label: 'Album (Mood)' },
    { id: 'comments', label: 'Comments' },
  ]

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-white dark:bg-surface-dark rounded-xl shadow-elevated w-full max-w-2xl max-h-[80vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border dark:border-border-dark">
          <div>
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
              Select Tags for Training
            </h2>
            {discoveredTags && (
              <p className="text-sm text-muted">
                Found {discoveredTags.total_files} files
              </p>
            )}
          </div>
          <button
            onClick={onClose}
            className="p-2 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {isLoading ? (
          <div className="flex-1 flex items-center justify-center p-12">
            <div className="text-center">
              <Loader2 className="w-8 h-8 text-accent animate-spin mx-auto mb-4" />
              <p className="text-muted">Scanning directory for tags...</p>
            </div>
          </div>
        ) : discoveredTags ? (
          <>
            {/* Tabs */}
            <div className="flex border-b border-border dark:border-border-dark">
              {tabs.map((tab) => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={clsx(
                    'flex-1 px-4 py-3 text-sm font-medium transition-colors',
                    activeTab === tab.id
                      ? 'text-accent border-b-2 border-accent'
                      : 'text-muted hover:text-gray-900 dark:hover:text-white'
                  )}
                >
                  {tab.label}
                  <span className="ml-2 text-xs bg-gray-100 dark:bg-gray-800 px-2 py-0.5 rounded-full">
                    {selectedTags[tab.id].length}/{Object.keys(discoveredTags[tab.id].values).length}
                  </span>
                </button>
              ))}
            </div>

            {/* Search */}
            <div className="p-4 border-b border-border dark:border-border-dark">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search tags..."
                  className="input pl-10"
                />
              </div>
              <div className="flex gap-2 mt-2">
                <button
                  onClick={() => selectAll(activeTab)}
                  className="text-xs text-accent hover:underline"
                >
                  Select all
                </button>
                <span className="text-muted">·</span>
                <button
                  onClick={() => deselectAll(activeTab)}
                  className="text-xs text-accent hover:underline"
                >
                  Deselect all
                </button>
              </div>
            </div>

            {/* Tag List */}
            <div className="flex-1 overflow-auto p-4">
              <div className="grid grid-cols-2 gap-2">
                {getFilteredTags(activeTab).map(([tag, count]) => {
                  const isSelected = selectedTags[activeTab].includes(tag)
                  return (
                    <button
                      key={tag}
                      onClick={() => toggleTag(activeTab, tag)}
                      className={clsx(
                        'flex items-center gap-2 px-3 py-2 rounded-lg text-left transition-colors',
                        isSelected
                          ? 'bg-accent/10 border border-accent text-accent'
                          : 'bg-gray-50 dark:bg-gray-800 border border-transparent hover:border-gray-200 dark:hover:border-gray-700'
                      )}
                    >
                      <div
                        className={clsx(
                          'w-4 h-4 rounded border flex items-center justify-center',
                          isSelected
                            ? 'bg-accent border-accent'
                            : 'border-gray-300 dark:border-gray-600'
                        )}
                      >
                        {isSelected && <Check className="w-3 h-3 text-white" />}
                      </div>
                      <span className="flex-1 truncate text-sm">{tag}</span>
                      <span className="text-xs text-muted">{count}</span>
                    </button>
                  )
                })}
              </div>
              {getFilteredTags(activeTab).length === 0 && (
                <div className="text-center text-muted py-8">
                  <Tag className="w-8 h-8 mx-auto mb-2 opacity-50" />
                  <p>No tags found</p>
                </div>
              )}
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center p-12 text-muted">
            No tag data available
          </div>
        )}

        {/* Footer */}
        <div className="flex items-center justify-between p-4 border-t border-border dark:border-border-dark">
          <div className="text-sm text-muted">
            {totalSelected} tags selected
          </div>
          <div className="flex gap-3">
            <button onClick={onClose} className="btn btn-secondary">
              Cancel
            </button>
            <button
              onClick={handleConfirm}
              disabled={totalSelected === 0}
              className="btn btn-primary"
            >
              Start Training
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
