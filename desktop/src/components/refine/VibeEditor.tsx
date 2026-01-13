/**
 * VibeEditor Component - Redesigned
 * Short vibe and long description text areas
 */
import { Sparkles, FileText, Music2 } from 'lucide-react'

interface VibeEditorProps {
  vibe: string
  description: string
  hook?: string
  onVibeChange: (value: string) => void
  onDescriptionChange: (value: string) => void
}

function SectionHeader({ icon: Icon, title }: { icon: any; title: string }) {
  return (
    <div className="flex items-center gap-2 mb-2">
      <Icon className="w-4 h-4 text-amber-500" />
      <label className="block text-sm font-medium text-stone-700 dark:text-stone-300">
        {title}
      </label>
    </div>
  )
}

export function VibeEditor({
  vibe,
  description,
  hook,
  onVibeChange,
  onDescriptionChange,
}: VibeEditorProps) {
  return (
    <div className="card space-y-5">
      {/* Short Vibe (Composer field) */}
      <div>
        <SectionHeader icon={Sparkles} title="Vibe (Short)" />
        <textarea
          value={vibe}
          onChange={(e) => onVibeChange(e.target.value)}
          className="input w-full min-h-[70px] resize-y"
          placeholder="Short vibe description..."
          rows={2}
        />
      </div>

      {/* Long Description */}
      <div>
        <SectionHeader icon={FileText} title="Description (Long)" />
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
          <SectionHeader icon={Music2} title="Detected Hook" />
          <div className="p-4 bg-gradient-to-r from-violet-50 to-amber-50 dark:from-violet-900/20 dark:to-amber-900/20 rounded-xl border border-violet-200/50 dark:border-violet-800/50">
            <p className="text-sm text-stone-700 dark:text-stone-300 italic leading-relaxed">
              "{hook}"
            </p>
          </div>
        </div>
      )}
    </div>
  )
}
