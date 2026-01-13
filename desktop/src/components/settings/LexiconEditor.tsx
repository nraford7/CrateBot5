/**
 * LexiconEditor Component
 * Allows users to customize vocabulary mappings and ID3 frame assignments.
 */
import { useState, useEffect } from 'react'
import { api, LexiconConfig, LexiconCategory } from '../../api/client'
import { ID3_FRAMES, FRAME_GROUPS } from '../../constants/id3Frames'

const CANONICAL_VALUES: Record<string, string[]> = {
  genre: ['House', 'Techno', 'Jungle/DnB', 'Rap', 'DiscoFunk', 'Breakbeat', 'Ambient', 'Dubstep', 'Trance'],
  timing: ['Start', 'Build', 'Peak', 'Sustain', 'Release'],
  mood: ['Happy', 'Dark', 'Emotional', 'Aggressive', 'Dreamy', 'Groovy'],
  descriptive: []
}

interface CategoryEditorProps {
  category: string
  label: string
  config: LexiconCategory
  onUpdate: (category: string, id3_frame?: string, mappings?: Record<string, string>) => void
}

function CategoryEditor({ category, label, config, onUpdate }: CategoryEditorProps) {
  const [editingMapping, setEditingMapping] = useState<string | null>(null)
  const [mappingValue, setMappingValue] = useState('')

  const handleFrameChange = (frame: string) => {
    onUpdate(category, frame)
  }

  const handleMappingEdit = (canonical: string) => {
    setEditingMapping(canonical)
    setMappingValue(config.mappings[canonical] || '')
  }

  const handleMappingSave = (canonical: string) => {
    const newMappings = { ...config.mappings }
    if (mappingValue.trim()) {
      newMappings[canonical] = mappingValue.trim()
    } else {
      delete newMappings[canonical]
    }
    onUpdate(category, undefined, newMappings)
    setEditingMapping(null)
  }

  const canonicals = CANONICAL_VALUES[category]

  return (
    <div className="border border-stone-200 dark:border-stone-700 rounded-lg p-4 mb-4">
      <h4 className="font-medium text-stone-800 dark:text-stone-200 mb-3 capitalize">{label}</h4>

      {/* ID3 Frame selector */}
      <div className="mb-4">
        <label className="block text-sm text-stone-600 dark:text-stone-400 mb-1">ID3 Frame</label>
        <select
          value={config.id3_frame}
          onChange={(e) => handleFrameChange(e.target.value)}
          className="w-full px-3 py-2 bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded-md text-sm"
        >
          {FRAME_GROUPS.map(group => (
            <optgroup key={group} label={group}>
              {ID3_FRAMES.filter(f => f.group === group).map(frame => (
                <option key={frame.code} value={frame.code}>
                  {frame.code} - {frame.name}
                </option>
              ))}
            </optgroup>
          ))}
        </select>
        {/* Show description of selected frame */}
        {config.id3_frame && (
          <p className="text-xs text-stone-500 dark:text-stone-400 mt-1">
            {ID3_FRAMES.find(f => f.code === config.id3_frame)?.description || 'Custom frame'}
          </p>
        )}
      </div>

      {/* Vocabulary mappings */}
      {canonicals.length > 0 && (
        <div>
          <label className="block text-sm text-stone-600 dark:text-stone-400 mb-2">Vocabulary Mappings</label>
          <div className="space-y-2">
            {canonicals.map(canonical => (
              <div key={canonical} className="flex items-center gap-2">
                <span className="w-24 text-sm text-stone-700 dark:text-stone-300">{canonical}</span>
                <span className="text-stone-400">-&gt;</span>
                {editingMapping === canonical ? (
                  <>
                    <input
                      type="text"
                      value={mappingValue}
                      onChange={(e) => setMappingValue(e.target.value)}
                      placeholder={canonical}
                      className="flex-1 px-2 py-1 text-sm bg-white dark:bg-stone-800 border border-stone-300 dark:border-stone-600 rounded"
                      onKeyDown={(e) => e.key === 'Enter' && handleMappingSave(canonical)}
                      autoFocus
                    />
                    <button
                      onClick={() => handleMappingSave(canonical)}
                      className="px-2 py-1 text-xs bg-green-600 text-white rounded hover:bg-green-700"
                    >
                      Save
                    </button>
                    <button
                      onClick={() => setEditingMapping(null)}
                      className="px-2 py-1 text-xs text-stone-500 hover:text-stone-700"
                    >
                      Cancel
                    </button>
                  </>
                ) : (
                  <>
                    <span className="flex-1 text-sm text-stone-600 dark:text-stone-400">
                      {config.mappings[canonical] || canonical}
                    </span>
                    <button
                      onClick={() => handleMappingEdit(canonical)}
                      className="px-2 py-1 text-xs text-stone-600 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200"
                    >
                      Edit
                    </button>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

export function LexiconEditor() {
  const [config, setConfig] = useState<LexiconConfig | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    loadLexicon()
  }, [])

  const loadLexicon = async () => {
    try {
      setLoading(true)
      const data = await api.getLexicon()
      setConfig(data)
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load lexicon')
    } finally {
      setLoading(false)
    }
  }

  const handleUpdate = async (category: string, id3_frame?: string, mappings?: Record<string, string>) => {
    if (!config) return
    try {
      await api.updateLexicon({ category, id3_frame, mappings })
      // Optimistic update
      setConfig(prev => {
        if (!prev) return prev
        const catKey = category as keyof typeof prev.categories
        return {
          ...prev,
          categories: {
            ...prev.categories,
            [category]: {
              id3_frame: id3_frame ?? prev.categories[catKey].id3_frame,
              mappings: mappings ?? prev.categories[catKey].mappings
            }
          }
        }
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update lexicon')
      loadLexicon() // Reload on error
    }
  }

  if (loading) {
    return <div className="text-stone-500 dark:text-stone-400">Loading lexicon...</div>
  }

  if (error) {
    return (
      <div className="text-red-500">
        {error}
        <button onClick={loadLexicon} className="ml-2 underline">Retry</button>
      </div>
    )
  }

  if (!config) return null

  return (
    <div>
      <p className="text-sm text-stone-600 dark:text-stone-400 mb-4">
        Customize tag vocabulary and ID3 frame assignments for each category.
      </p>
      <CategoryEditor category="genre" label="Genre" config={config.categories.genre} onUpdate={handleUpdate} />
      <CategoryEditor category="timing" label="Timing" config={config.categories.timing} onUpdate={handleUpdate} />
      <CategoryEditor category="mood" label="Mood" config={config.categories.mood} onUpdate={handleUpdate} />
      <CategoryEditor category="descriptive" label="Descriptive" config={config.categories.descriptive} onUpdate={handleUpdate} />
    </div>
  )
}
